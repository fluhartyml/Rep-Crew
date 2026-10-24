//
//  ContactSeal.swift
//  Rep Crew
//
//  Coaches-only contact info. His words, 2026-10-23: "every textbox has a privacy toggle but the
//  coache or coaches can overide the toggle and see" · "if i want an assistant coach (another
//  coach) i long press on him" · "yes build it".
//
//  Profiles live in the public database, which anyone signed in can read, so hiding a field on
//  screen wouldn't keep it private. Instead a field marked "Coaches only" leaves the Profile's plain
//  fields and goes into Profile.sealed, encrypted once for each coach and once for its owner:
//
//    Every phone has one key (Curve25519), kept in iCloud Keychain so it follows the person to a
//    new phone. A coach's phone publishes its public half as a CoachKey record
//    (name = coachkey.<coach ID>), honored only when CloudKit says that coach wrote it and the
//    writer is still a coach or him. Making someone a coach is still only the long-press; their
//    key shows up the first time they open the app as a coach.
//
//    Sealed = JSON list of envelopes { to, eph, box }: for each reader, a fresh key agreement
//    with their public key → HKDF-SHA256 → ChaChaPoly over the private fields as JSON.
//
//  A member's phone re-seals whenever the set of coach keys changes (it's part of the profile's
//  save signature), so a new coach can read profiles once each member has opened the app again,
//  and a removed coach stops getting new copies.
//

import CloudKit
import CryptoKit
import Foundation
import Security

/// The fields a member marked Coaches only. Nil = not private.
struct PrivateContact: Codable {
    var phone: String?
    var email: String?
    var facetime: String?

    var isEmpty: Bool { phone == nil && email == nil && facetime == nil }
}

/// This phone's contact key, in iCloud Keychain.
enum ContactKey {
    private static let service = "com.accountability.dailyrepcrew.contactKey"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "contactKey",
         kSecAttrSynchronizable as String: kCFBooleanTrue as Any]
    }

    /// The key, made and stored the first time when `create` is true.
    static func mine(create: Bool) -> Curve25519.KeyAgreement.PrivateKey? {
        var read = query
        read[kSecReturnData as String] = true
        var item: CFTypeRef?
        if SecItemCopyMatching(read as CFDictionary, &item) == errSecSuccess, let data = item as? Data {
            return try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        }
        guard create else { return nil }
        let key = Curve25519.KeyAgreement.PrivateKey()
        var add = query
        add[kSecValueData as String] = key.rawRepresentation
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess ? key : nil
    }
}

enum ContactSeal {
    private struct Envelope: Codable {
        let to: String
        let eph: Data
        let box: Data
    }

    private static func symmetricKey(_ secret: SharedSecret, for id: String) -> SymmetricKey {
        secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data("RepCrew.contact".utf8),
                                       sharedInfo: Data(id.utf8), outputByteCount: 32)
    }

    /// One envelope per reader (iCloud ID → public key).
    static func seal(_ contact: PrivateContact, to readers: [String: Data]) -> Data? {
        guard let plain = try? JSONEncoder().encode(contact) else { return nil }
        var envelopes: [Envelope] = []
        for (id, publicKey) in readers {
            guard let theirs = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKey) else { continue }
            let ephemeral = Curve25519.KeyAgreement.PrivateKey()
            guard let secret = try? ephemeral.sharedSecretFromKeyAgreement(with: theirs),
                  let box = try? ChaChaPoly.seal(plain, using: symmetricKey(secret, for: id)).combined else { continue }
            envelopes.append(Envelope(to: id, eph: ephemeral.publicKey.rawRepresentation, box: box))
        }
        return envelopes.isEmpty ? nil : try? JSONEncoder().encode(envelopes)
    }

    /// The private fields, when one of the envelopes is for this phone.
    static func open(_ sealed: Data, for id: String, key: Curve25519.KeyAgreement.PrivateKey) -> PrivateContact? {
        guard let envelopes = try? JSONDecoder().decode([Envelope].self, from: sealed),
              let mine = envelopes.first(where: { $0.to == id }),
              let ephemeral = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: mine.eph),
              let secret = try? key.sharedSecretFromKeyAgreement(with: ephemeral),
              let box = try? ChaChaPoly.SealedBox(combined: mine.box),
              let plain = try? ChaChaPoly.open(box, using: symmetricKey(secret, for: id)) else { return nil }
        return try? JSONDecoder().decode(PrivateContact.self, from: plain)
    }
}

// MARK: - iCloud

extension CrewCloud {
    /// Coaches' public keys, by iCloud ID. Only keys a coach (or he) wrote for themselves.
    func loadCoachKeys() async {
        let query = CKQuery(recordType: "CoachKey", predicate: NSPredicate(value: true))
        guard let (results, _) = try? await db.records(matching: query, resultsLimit: 200) else { return }
        var found: [String: Data] = [:]
        for record in results.compactMap({ try? $0.1.get() }) {
            guard let id = record["coachID"] as? String, writer(of: record) == id,
                  isModerator(id, leaderID: nil), let key = record["publicKey"] as? Data else { continue }
            found[id] = key
        }
        coachKeys = found
    }

    /// A coach's phone: publishes its public key so members can seal to it.
    func publishCoachKey() async {
        await connect()
        guard let myID, GodMode.isOn, let key = ContactKey.mine(create: true) else { return }
        let publicKey = key.publicKey.rawRepresentation
        guard coachKeys[myID] != publicKey else { return }
        let record = CKRecord(recordType: "CoachKey", recordID: CKRecord.ID(recordName: "coachkey.\(myID)"))
        record["coachID"] = myID
        record["publicKey"] = publicKey
        do {
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            coachKeys[myID] = publicKey
        } catch {
            status = "Couldn't set up coach access: \(error.localizedDescription)"
        }
    }

    /// Who a profile's private fields are sealed to: every coach, and its owner.
    func sealReaders() -> [String: Data] {
        var readers = coachKeys
        if let myID, let key = ContactKey.mine(create: true) { readers[myID] = key.publicKey.rawRepresentation }
        return readers
    }

    /// Part of the profile's save signature, so a change in coaches re-seals it.
    var coachKeysSignature: String {
        coachKeys.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value.base64EncodedString())" }.joined(separator: ",")
    }
}
