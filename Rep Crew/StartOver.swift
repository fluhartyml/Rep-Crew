//
//  StartOver.swift
//  Rep Crew
//
//  His words, 2026-10-25: "is there a long press option for me to 'factory reset' or make a users next log in
//  act like their first login without deleting their user account? on the bbs we reset their account by
//  deleting their user account, then they lost their user number" · "yes build it".
//
//  REM: two records in the shared space, each honored only when CloudKit says who wrote it:
//    StartOver      name = "startover.<member ID>". requestedAt. Head coach only (GodMode.ids).
//    StartOverDone  name = "startover.done.<member ID>". requestedAt copied from the request. Written by the
//                   member's own phone once it started over, so the same request never fires twice, and a
//                   new phone or a reinstall doesn't start over again for an old request.
//  REM: starting over brings back the user agreement, the name and the application, as on a first login.
//  It keeps the account: iCloud ID, crew number, challenges, reps, profile photo and contact info stay.
//  Sign in with Apple isn't asked again: Apple gives the name and email only on the very first sign-in to
//  the app, so a second sign-in would bring nothing; the application asks for the email instead.
//

import CloudKit
import SwiftUI

extension CrewSettings {
    /// Set while a member is starting over, until they finish the application. Profile restore leaves their
    /// name and "application done" alone meanwhile, so the name and application screens really come back.
    static let startingOver = "startingOver"
}

extension CrewCloud {
    private static func requestID(_ memberID: String) -> CKRecord.ID { CKRecord.ID(recordName: "startover.\(memberID)") }
    private static func doneID(_ memberID: String) -> CKRecord.ID { CKRecord.ID(recordName: "startover.done.\(memberID)") }

    /// Head coach: their next launch acts like their first login.
    func requestStartOver(for memberID: String) async -> Bool {
        await connect()
        guard GodMode.isOwner, !GodMode.ids.contains(memberID) else { return false }
        let record = (try? await db.record(for: Self.requestID(memberID))) ?? CKRecord(recordType: "StartOver", recordID: Self.requestID(memberID))
        record["memberID"] = memberID
        record["requestedAt"] = Date.now
        do {
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
            return true
        } catch {
            status = "Couldn't ask them to start over: \(error.localizedDescription)"
            return false
        }
    }

    /// This phone: start over if the head coach asked since the last time. Run at launch, before profile restore.
    func startOverIfRequested() async {
        await connect()
        guard let myID, !GodMode.ids.contains(myID),
              let request = try? await db.record(for: Self.requestID(myID)),
              let author = writer(of: request), GodMode.ids.contains(author),
              let requestedAt = request["requestedAt"] as? Date else { return }
        if let done = try? await db.record(for: Self.doneID(myID)), writer(of: done) == myID,
           let handled = done["requestedAt"] as? Date, handled >= requestedAt { return }

        let defaults = UserDefaults.standard
        defaults.set(true, forKey: CrewSettings.startingOver)
        defaults.set(0, forKey: CrewSettings.agreementVersion)
        defaults.set("", forKey: CrewSettings.name)
        defaults.set(false, forKey: CrewSettings.applicationDone)
        defaults.set(false, forKey: CrewSettings.applicationEmailGiven)
        defaults.set("", forKey: CrewSettings.applicationWaiting)

        let done = (try? await db.record(for: Self.doneID(myID))) ?? CKRecord(recordType: "StartOverDone", recordID: Self.doneID(myID))
        done["memberID"] = myID
        done["requestedAt"] = requestedAt
        _ = try? await db.modifyRecords(saving: [done], deleting: [], savePolicy: .changedKeys)
        await refreshMyAccess()
    }
}

/// Long-press → Start Over at Next Launch. Head coach only; goes in any .contextMenu, beside Set Access Level.
struct StartOverMenuItem: View {
    let memberID: String

    var body: some View {
        if GodMode.isOwner && !GodMode.ids.contains(memberID) {
            Button(role: .destructive) {
                Task { _ = await CrewCloud.shared.requestStartOver(for: memberID) }
            } label: {
                Label("Start Over at Next Launch", systemImage: "arrow.counterclockwise.circle")
            }
        }
    }
}

#if DEBUG
extension CrewCloud {
    /// Creates the shared record types a fresh feature uses in the Development iCloud, so they can be deployed to
    /// Production before TestFlight. Debug builds only, once per build number: one placeholder of each, every
    /// field filled, saved and then deleted at once.
    /// REM: his "yes build it and install on the 11", 2026-10-25. The console showed Approval, StartOver,
    /// StartOverDone and Welcomed missing: CloudKit makes a type only when a record of it is first saved, and the
    /// 11 never saved one (Approve refuses coaches, Start Over can't target him). Deploying without them would leave
    /// Approve, Start Over and the shared Welcomed failing for the real crew. Add any new public type here.
    func seedSchemaTypes() async {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let doneKey = "publicSchemaSeededBuild"
        guard UserDefaults.standard.string(forKey: doneKey) != build else { return }
        await connect()
        let now = Date.now
        let fields: [(type: String, values: [String: CKRecordValue])] = [
            ("Approval", ["memberID": "schema.seed" as NSString, "approvedAt": now as NSDate]),
            ("StartOver", ["memberID": "schema.seed" as NSString, "requestedAt": now as NSDate]),
            ("StartOverDone", ["memberID": "schema.seed" as NSString, "requestedAt": now as NSDate]),
            ("Welcomed", ["memberID": "schema.seed" as NSString, "welcomedAt": now as NSDate]),
            ("LibraryHidden", ["crewID": "schema.seed" as NSString, "hiddenAt": now as NSDate]),
        ]
        let records = fields.map { item -> CKRecord in
            let record = CKRecord(recordType: item.type, recordID: CKRecord.ID(recordName: "schema.seed.\(item.type)"))
            for (key, value) in item.values { record[key] = value }
            return record
        }
        do {
            _ = try await db.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys)
            _ = try await db.modifyRecords(saving: [], deleting: records.map(\.recordID))
            UserDefaults.standard.set(build, forKey: doneKey)
        } catch {
            print("Public schema not seeded: \(error)")
        }
    }
}
#endif
