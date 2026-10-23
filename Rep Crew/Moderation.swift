//
//  Moderation.swift
//  Rep Crew
//
//  Keeping the crew decent. Michael, 2026-10-22: "the leader can kick ban anyone that posts
//  pervy pictures". App Review guideline 1.2 (read 2026-10-22) asks apps with user content for
//  a filter, a way to report, the ability to block abusive users, and published contact info.
//  This file covers three of those:
//
//    Ban     The leader removes someone from a challenge for good. CrewBan record, name =
//            ban.<crewID>.<memberID>; every phone honors it only when the leader wrote it, shows
//            them as "Disqualified" on the board, and hides their photos and messages.
//    Report  Anyone reports a photo. A Report record reaches the developer (CloudKit Console
//            today; god mode later), and the photo disappears for the person who reported it.
//    Block   Anyone blocks a person. Kept on this phone only; their rows, photos and messages
//            vanish everywhere for you. Unblock in Settings.
//

import CloudKit
import SwiftUI

extension CrewSettings {
    /// People you blocked, one per line: "<iCloud ID>\t<name>".
    static let blocked = "blockedPeople"
    /// Photos you reported, newline-separated record names, hidden on this phone.
    static let hiddenPhotos = "hiddenPhotoIDs"
}

/// People and photos this phone hides.
enum Blocklist {
    private static var defaults: UserDefaults { .standard }

    static var people: [(id: String, name: String)] {
        (defaults.string(forKey: CrewSettings.blocked) ?? "").split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            return parts.isEmpty ? nil : (parts[0], parts.count > 1 ? parts[1] : "Crew member")
        }
    }

    static var ids: Set<String> { Set(people.map(\.id)) }

    static func block(_ id: String, name: String) {
        guard !ids.contains(id) else { return }
        let lines = people.map { "\($0.id)\t\($0.name)" } + ["\(id)\t\(name)"]
        defaults.set(lines.joined(separator: "\n"), forKey: CrewSettings.blocked)
    }

    static func unblock(_ id: String) {
        let lines = people.filter { $0.id != id }.map { "\($0.id)\t\($0.name)" }
        defaults.set(lines.joined(separator: "\n"), forKey: CrewSettings.blocked)
    }

    static var hiddenPhotos: Set<String> {
        Set((defaults.string(forKey: CrewSettings.hiddenPhotos) ?? "").split(separator: "\n").map(String.init))
    }

    static func hidePhoto(_ id: String) {
        defaults.set((hiddenPhotos.union([id])).joined(separator: "\n"), forKey: CrewSettings.hiddenPhotos)
    }
}

// MARK: - iCloud

extension CrewCloud {
    /// Who the leader removed from this challenge. `leaderID` nil = look it up.
    func banned(crewID: String, leaderID: String? = nil) async -> Set<String> {
        var leader = leaderID
        if leader == nil {
            leader = (try? await db.record(for: CKRecord.ID(recordName: crewID)))?["leaderID"] as? String
        }
        guard let leader, !leader.isEmpty else { return [] }
        let query = CKQuery(recordType: "CrewBan", predicate: NSPredicate(format: "crewID == %@", crewID))
        guard let (results, _) = try? await db.records(matching: query) else { return [] }
        return Set(results.compactMap { try? $0.1.get() }
            .filter { $0["bannedBy"] as? String == leader }
            .compactMap { $0["memberID"] as? String })
    }

    /// Everyone this phone shouldn't show in a challenge: banned there, or blocked by you.
    func hidden(crewID: String, leaderID: String? = nil) async -> Set<String> {
        await banned(crewID: crewID, leaderID: leaderID).union(Blocklist.ids)
    }

    /// Leader only: removes someone from the challenge for good.
    func ban(crewID: String, memberID: String, name: String) async -> Bool {
        await connect()
        guard let myID else { return false }
        let record = CKRecord(recordType: "CrewBan", recordID: CKRecord.ID(recordName: "ban.\(crewID).\(memberID)"))
        record["crewID"] = crewID
        record["memberID"] = memberID
        record["memberName"] = name
        record["bannedBy"] = myID
        do {
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            // Take them off the challenge's check-box list too, so it isn't offered to them again.
            if let challenge = try? await db.record(for: CKRecord.ID(recordName: crewID)),
               var members = challenge["memberIDs"] as? [String], members.contains(memberID) {
                members.removeAll { $0 == memberID }
                challenge["memberIDs"] = members
                _ = try? await db.modifyRecords(saving: [challenge], deleting: [], savePolicy: .changedKeys)
            }
            return true
        } catch {
            status = "Couldn't remove \(name): \(error.localizedDescription)"
            return false
        }
    }

    /// Sends a photo to the developer for review and hides it on this phone.
    func report(_ photo: CrewPhoto) async -> Bool {
        await connect()
        guard let myID else { return false }
        let record = CKRecord(recordType: "Report")
        record["kind"] = "photo"
        record["photoID"] = photo.id
        record["crewID"] = photo.crewID
        record["senderID"] = photo.senderID
        record["senderName"] = photo.senderName
        record["reporterID"] = myID
        record["reportedAt"] = Date.now
        do {
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            Blocklist.hidePhoto(photo.id)
            return true
        } catch {
            status = "Couldn't send your report: \(error.localizedDescription)"
            return false
        }
    }
}

// MARK: - Settings

/// The people you blocked, each with Unblock.
struct BlockedPeopleSection: View {
    @AppStorage(CrewSettings.blocked) private var blocked = ""

    var body: some View {
        let people = Blocklist.people
        if !people.isEmpty {
            Section {
                ForEach(people, id: \.id) { person in
                    HStack {
                        Text(person.name).font(AppFont.bodyBold)
                        Spacer()
                        Button("Unblock") { Blocklist.unblock(person.id) }
                            .font(AppFont.body)
                            .buttonStyle(.bordered)
                    }
                }
            } header: {
                Text("Blocked").font(AppFont.bodyBold).textCase(nil)
            } footer: {
                Text("You don't see their reps, photos or messages. They aren't told.").font(AppFont.body)
            }
            // Reading `blocked` here redraws the list when someone is unblocked.
            .id(blocked)
        }
    }
}
