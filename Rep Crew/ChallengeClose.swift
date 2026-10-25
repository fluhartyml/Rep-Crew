//
//  ChallengeClose.swift
//  Rep Crew
//
//  Closing a challenge before its last day. His words, 2026-10-24: "i also want to close a challenge,
//  my own but as a coach i should be able to close a challence and it sould say coach so and so closed
//  this challenge" · "or crew leader" · "if its their own challenge they are the crew leader if they are
//  250 or above ... they are a coach" · "can you do everything we discussed please?"
//
//  REM: the closing is a CrewMessage named closed.<crewID>, so it needs no new iCloud type: the crew's
//  own subscription turns it into the notification, it shows on the crew's messages, and any phone can
//  fetch it by name without a query. It counts only when the leader, a coach or he wrote it (CloudKit's
//  creator, not a field). A coach can't edit another leader's CrewChallenge record, so for a coach the
//  message IS the closing; the leader's own close also ends the record, so it drops off the crew list
//  and moves to Past challenges at once.
//  "Coach" is the long-press coach or the head coach (isModerator). A level of 250 set by hand alone
//  isn't trusted by the shared space (Access.swift), so it doesn't unlock this.
//

import CloudKit
import Foundation

extension CrewSettings {
    /// crewID → the closing notice, newline-separated "crewID\tnotice" lines.
    static let closedChallenges = "closedChallenges"
    /// crewID → when it was closed, "crewID\tseconds since 1970" lines (for "Closed Oct 25" on the boards).
    static let closedDates = "closedChallengeDates"
}

/// The challenges this phone knows were closed, and by whom.
enum ChallengeClosure {
    static var all: [String: String] {
        var found: [String: String] = [:]
        for line in (UserDefaults.standard.string(forKey: CrewSettings.closedChallenges) ?? "").split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            if parts.count == 2 { found[parts[0]] = parts[1] }
        }
        return found
    }

    static func notice(_ crewID: String) -> String? { crewID.isEmpty ? nil : all[crewID] }
    static func isClosed(_ crewID: String) -> Bool { notice(crewID) != nil }

    static func save(_ closed: [String: String]) {
        let text = closed.map { "\($0.key)\t\($0.value)" }.sorted().joined(separator: "\n")
        UserDefaults.standard.set(text, forKey: CrewSettings.closedChallenges)
    }

    static func recordName(_ crewID: String) -> String { "closed.\(crewID)" }

    /// When it was closed, if this phone knows.
    static func closedAt(_ crewID: String) -> Date? {
        for line in (UserDefaults.standard.string(forKey: CrewSettings.closedDates) ?? "").split(separator: "\n") {
            let parts = line.split(separator: "\t").map(String.init)
            if parts.count == 2, parts[0] == crewID, let seconds = Double(parts[1]) { return Date(timeIntervalSince1970: seconds) }
        }
        return nil
    }

    static func setClosedAt(_ date: Date, for crewID: String) {
        var lines = (UserDefaults.standard.string(forKey: CrewSettings.closedDates) ?? "").split(separator: "\n").map(String.init)
            .filter { !$0.hasPrefix(crewID + "\t") }
        lines.append("\(crewID)\t\(date.timeIntervalSince1970)")
        UserDefaults.standard.set(lines.joined(separator: "\n"), forKey: CrewSettings.closedDates)
    }

    /// What the crew reads. His rule: your own challenge → Crew Leader; someone else's → Coach.
    static func notice(byLeader: Bool, name: String) -> String {
        "\(byLeader ? "Crew Leader" : "Coach") \(name) closed this challenge."
    }
}

extension CrewCloud {
    /// Closes the challenge for everyone. `leaderID` empty = it's yours.
    func close(crewID: String, leaderID: String, senderName: String) async -> Bool {
        await connect()
        guard let myID, !crewID.isEmpty else { return false }
        let mine = leaderID.isEmpty || leaderID == myID
        guard mine || GodMode.isOn else { return false }
        let notice = ChallengeClosure.notice(byLeader: mine, name: senderName)
        let record = CKRecord(recordType: "CrewMessage", recordID: CKRecord.ID(recordName: ChallengeClosure.recordName(crewID)))
        record["crewID"] = crewID
        record["text"] = notice
        record["senderID"] = myID
        record["senderName"] = senderName
        record["kind"] = CrewMessage.Kind.closed.rawValue
        record["toID"] = CrewMessage.everyone
        record["sentAt"] = Date.now
        record["title"] = "🔒 \(senderName)"
        do {
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Someone already closed it; their notice stands and is read on the next refresh.
        } catch {
            status = "Couldn't close the challenge: \(error.localizedDescription)"
            return false
        }
        if mine, let challenge = try? await db.record(for: CKRecord.ID(recordName: crewID)) {
            challenge["endsAt"] = Date.now
            _ = try? await db.modifyRecords(saving: [challenge], deleting: [], savePolicy: .changedKeys)
        }
        var closed = ChallengeClosure.all
        closed[crewID] = notice
        ChallengeClosure.save(closed)
        ChallengeClosure.setClosedAt(.now, for: crewID)
        return true
    }

    /// Reads the closings for these challenges (crewID → leaderID; empty = yours) and keeps the ones the
    /// leader, a coach or he really wrote. A failed fetch keeps what this phone already knew.
    func refreshClosures(_ challenges: [String: String]) async {
        await connect()
        guard let myID, !challenges.isEmpty else { return }
        let ids = challenges.keys.filter { !$0.isEmpty }.map { CKRecord.ID(recordName: ChallengeClosure.recordName($0)) }
        guard let results = try? await db.records(for: ids) else { return }
        var closed = ChallengeClosure.all
        for (id, result) in results {
            guard let record = try? result.get(), let crewID = record["crewID"] as? String,
                  let notice = record["text"] as? String,
                  ChallengeClosure.recordName(crewID) == id.recordName else { continue }
            let leader = challenges[crewID].flatMap { $0.isEmpty ? myID : $0 }
            if isModerator(writer(of: record), leaderID: leader) {
                closed[crewID] = notice
                if let date = record.creationDate { ChallengeClosure.setClosedAt(date, for: crewID) }
            }
        }
        ChallengeClosure.save(closed)
    }
}
