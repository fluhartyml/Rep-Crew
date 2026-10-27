//
//  TVCloud.swift
//  Rep Crew TV
//
//  The Apple TV board reads the crew's iCloud space and never writes to it. His idea, 2026-10-27: "the
//  apple tv version of the rep app could be a status or leaderboard that just served information and status".
//
//  REM: this is a read-only copy of the phone's reading rules, kept small on purpose so the TV target needs
//  none of the phone's files. Each function names the phone code it mirrors; change both together.
//    • Record types and fields: CloudKit-Schema.ckdb (repo root).
//    • Board: Rep Crew/Leaderboard.swift → standings(crewID:dayNumber:).
//    • Announcements: Rep Crew/Inbox.swift → inbox(crewIDs:led:), Rep Crew/CrewMessages.swift → messages(crewID:).
//    • Bans, removals, closings count only when the leader, a coach or the head coach wrote them
//      (Rep Crew/GodMode.swift → isModerator).
//    • Your week and View Home As: Rep Crew/TVShare.swift (private database, record "mine").
//  REM: the phone's Blocklist lives on the phone only, so the TV can't honor it. Bans it does honor.
//

import CloudKit
import Foundation

/// Must match TVWeekEntry in Rep Crew/TVShare.swift.
struct TVWeekEntry: Codable, Equatable {
    var crewID: String
    var title: String
    var weekdays: [Int]
    var goals: String
}

struct TVChallenge: Identifiable, Equatable {
    let id: String          // crewID
    let title: String
    let leaderID: String
    let startDate: Date
    let days: Int
    let goals: String

    /// 1-based day today, or nil before it starts or after it ends.
    var dayNumber: Int? {
        let cal = Calendar.current
        guard let offset = cal.dateComponents([.day], from: startDate, to: cal.startOfDay(for: .now)).day,
              offset >= 0, offset < days else { return nil }
        return offset + 1
    }

    /// "Oct 22 – Nov 4".
    var dateRange: String {
        let end = Calendar.current.date(byAdding: .day, value: days - 1, to: startDate) ?? startDate
        return "\(startDate.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

struct TVStanding: Identifiable, Equatable {
    let id: String
    var name: String
    var reps = 0
    var complete = false
    var streak = 0
    var minutes = 0
    var calories = 0
    var disqualified = false
}

struct TVAnnouncement: Identifiable, Equatable {
    let id: String
    let senderName: String
    let text: String
    let sentAt: Date
    /// The challenge's title, or "All crews".
    let crewTitle: String
}

@MainActor @Observable
final class TVCloud {
    static let shared = TVCloud()

    private let container = CKContainer(identifier: "iCloud.com.accountability.dailyrepcrew")
    private var db: CKDatabase { container.publicCloudDatabase }

    /// Mirrors GodMode.ids on the phone.
    private static let headCoachIDs: Set<String> = ["_9c345d5e0487de171f04792dc4b88366"]

    private(set) var myID: String?
    /// Plain words for the screen when iCloud isn't there; nil when connected.
    private(set) var problem: String?
    private var coaches: Set<String> = []

    private(set) var challenges: [TVChallenge] = []
    private(set) var announcements: [TVAnnouncement] = []
    /// nil = the phone hasn't saved a week yet.
    private(set) var week: [TVWeekEntry]?
    /// View Home As, from his phone (TVShare.swift). nil = himself.
    private(set) var viewAsName: String?
    private(set) var loaded = false

    func connect() async {
        if myID != nil { return }
        do {
            guard try await container.accountStatus() == .available else {
                problem = "This Apple TV isn't signed in to iCloud. Sign in from Settings → Users and Accounts."
                return
            }
            myID = try await container.userRecordID().recordName
            problem = nil
        } catch {
            problem = "iCloud problem: \(error.localizedDescription)"
        }
    }

    /// Everything the three screens show, asked all at once.
    func refresh() async {
        await connect()
        guard let myID else { loaded = true; return }
        await loadCoaches()
        async let personal = loadPersonal()
        async let found = activeChallenges(me: myID)
        let (state, list) = await (personal, found)
        week = state.week
        viewAsName = state.viewAsName
        challenges = list
        announcements = await loadAnnouncements(me: myID, includeMine: state.viewAsName != nil)
        loaded = true
    }

    // MARK: Challenges

    /// Challenges you lead or joined that are on today, minus ones the leader or a coach closed. Oldest first.
    private func activeChallenges(me: String) async -> [TVChallenge] {
        var crewIDs: Set<String> = []
        var records: [String: CKRecord] = [:]
        let led = CKQuery(recordType: "CrewChallenge", predicate: NSPredicate(format: "leaderID == %@", me))
        if let (results, _) = try? await db.records(matching: led, resultsLimit: 200) {
            for record in results.compactMap({ try? $0.1.get() }) { records[record.recordID.recordName] = record }
        }
        let joined = CKQuery(recordType: "Membership", predicate: NSPredicate(format: "memberID == %@", me))
        if let (results, _) = try? await db.records(matching: joined, resultsLimit: 200) {
            for record in results.compactMap({ try? $0.1.get() }) {
                if let crewID = record["crewID"] as? String, records[crewID] == nil { crewIDs.insert(crewID) }
            }
        }
        if !crewIDs.isEmpty, let results = try? await db.records(for: crewIDs.map { CKRecord.ID(recordName: $0) }) {
            for (id, result) in results { if let record = try? result.get() { records[id.recordName] = record } }
        }
        var list = records.values.compactMap(Self.challenge(from:)).filter { $0.dayNumber != nil }
        let closed = await closedCrewIDs(list)
        list.removeAll { closed.contains($0.id) }
        return list.sorted { ($0.startDate, $0.title) < ($1.startDate, $1.title) }
    }

    private static func challenge(from record: CKRecord) -> TVChallenge? {
        guard let title = record["title"] as? String, let startDay = record["startDay"] as? String,
              let start = dayFormat.date(from: startDay), let days = record["days"] as? Int else { return nil }
        struct Goal: Decodable { var name: String; var target: Int; var unit: String? }
        let goals = (record["goals"] as? String).flatMap { try? JSONDecoder().decode([Goal].self, from: Data($0.utf8)) } ?? []
        let text = goals.map { goalText($0.target, name: $0.name, unit: $0.unit) }.joined(separator: " and ")
        return TVChallenge(id: record.recordID.recordName, title: title, leaderID: record["leaderID"] as? String ?? "",
                           startDate: Calendar.current.startOfDay(for: start), days: days, goals: text)
    }

    /// Mirrors Invite.dayFormat on the phone: yyyy-MM-dd, the sender's calendar day.
    private static let dayFormat: DateFormatter = {
        let format = DateFormatter()
        format.calendar = Calendar(identifier: .gregorian)
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"
        return format
    }()

    /// Mirrors ExerciseUnit.goalText: "100 push-ups", "2.5 miles of running". Miles are stored in tenths.
    static func goalText(_ target: Int, name: String, unit: String?) -> String {
        let unit = unit ?? "reps"
        guard unit != "reps", !unit.isEmpty else { return "\(target.formatted()) \(name.lowercased())" }
        let amount = unit == "miles" ? (Double(target) / 10).formatted(.number.precision(.fractionLength(0...1))) : target.formatted()
        let one = unit == "miles" ? target == 10 : target == 1
        let word = one ? String(unit.dropLast()) : unit
        return "\(amount) \(word) of \(name.lowercased())"
    }

    /// Mirrors ChallengeClosure (ChallengeClose.swift): a closed.<crewID> record the leader or a coach wrote.
    private func closedCrewIDs(_ list: [TVChallenge]) async -> Set<String> {
        guard !list.isEmpty else { return [] }
        let leaders = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0.leaderID) })
        let ids = list.map { CKRecord.ID(recordName: "closed.\($0.id)") }
        guard let results = try? await db.records(for: ids) else { return [] }
        var closed: Set<String> = []
        for (_, result) in results {
            guard let record = try? result.get(), let crewID = record["crewID"] as? String else { continue }
            if isModerator(writer(of: record), leaderID: leaders[crewID]) { closed.insert(crewID) }
        }
        return closed
    }

    // MARK: Board

    /// Mirrors standings(crewID:dayNumber:) on the phone: everyone in the crew with today's reps; yesterday's
    /// record carries a streak for anyone who hasn't logged yet. Banned people show as "Disqualified".
    func standings(_ challenge: TVChallenge) async -> [TVStanding] {
        guard let day = challenge.dayNumber else { return [] }
        var board: [String: TVStanding] = [:]
        if let leader = try? await db.record(for: CKRecord.ID(recordName: challenge.id)), let id = leader["leaderID"] as? String {
            board[id] = TVStanding(id: id, name: leader["leaderName"] as? String ?? "Crew leader")
        }
        let joined = CKQuery(recordType: "Membership", predicate: NSPredicate(format: "crewID == %@", challenge.id))
        if let (results, _) = try? await db.records(matching: joined) {
            for record in results.compactMap({ try? $0.1.get() }) {
                guard let id = record["memberID"] as? String else { continue }
                board[id] = TVStanding(id: id, name: record["name"] as? String ?? "Crew member")
            }
        }
        let progress = CKQuery(recordType: "Progress", predicate: NSPredicate(format: "crewID == %@ AND dayNumber IN %@", challenge.id, [day - 1, day]))
        if let (results, _) = try? await db.records(matching: progress) {
            let records = results.compactMap { try? $0.1.get() }.sorted { ($0["dayNumber"] as? Int ?? 0) < ($1["dayNumber"] as? Int ?? 0) }
            for record in records {
                guard let id = record["memberID"] as? String else { continue }
                var row = board[id] ?? TVStanding(id: id, name: "Crew member")
                if let name = record["name"] as? String, !name.isEmpty { row.name = name }
                let complete = (record["complete"] as? Int ?? 0) == 1
                if record["dayNumber"] as? Int == day {
                    row.reps = record["reps"] as? Int ?? 0
                    row.complete = complete
                    row.streak = record["streak"] as? Int ?? 0
                    row.minutes = record["minutes"] as? Int ?? 0
                    row.calories = record["calories"] as? Int ?? 0
                } else if complete {
                    row.streak = record["streak"] as? Int ?? 0
                }
                board[id] = row
            }
        }
        let banned = await banned(crewID: challenge.id, leaderID: challenge.leaderID)
        // His design: listed by today's reps, no place labels. A disqualified row sinks to the bottom.
        return board.values.map { row in
            var row = row
            if banned.contains(row.id) { row.name = "Disqualified"; row.disqualified = true }
            return row
        }.sorted { ($0.disqualified ? 0 : 1, $0.reps, $1.name) > ($1.disqualified ? 0 : 1, $1.reps, $0.name) }
    }

    private func banned(crewID: String, leaderID: String) async -> Set<String> {
        let query = CKQuery(recordType: "CrewBan", predicate: NSPredicate(format: "crewID == %@", crewID))
        guard let (results, _) = try? await db.records(matching: query) else { return [] }
        return Set(results.compactMap { try? $0.1.get() }
            .filter { isModerator(writer(of: $0), leaderID: leaderID) }
            .compactMap { $0["memberID"] as? String })
    }

    // MARK: Announcements

    /// Announcements from your challenges plus a coach's to all crews, newest first. Your own are left out,
    /// as on the phone's Inbox, except while he's viewing as another level: then he sees them as a member would.
    private func loadAnnouncements(me: String, includeMine: Bool) async -> [TVAnnouncement] {
        let titles = Dictionary(uniqueKeysWithValues: challenges.map { ($0.id, $0.title) })
        let leaders = Dictionary(uniqueKeysWithValues: challenges.map { ($0.id, $0.leaderID) })
        let boards = await withTaskGroup(of: [TVAnnouncement].self) { group in
            for challenge in challenges {
                group.addTask { await self.announcements(crewID: challenge.id, title: titles[challenge.id] ?? "",
                                                         leaderID: leaders[challenge.id], me: me, includeMine: includeMine) }
            }
            group.addTask { await self.announcements(crewID: "all-crews", title: "All crews", leaderID: nil, me: me, includeMine: includeMine) }
            var all: [TVAnnouncement] = []
            for await found in group { all += found }
            return all
        }
        return boards.sorted { $0.sentAt > $1.sentAt }
    }

    private func announcements(crewID: String, title: String, leaderID: String?, me: String, includeMine: Bool) async -> [TVAnnouncement] {
        let query = CKQuery(recordType: "CrewMessage", predicate: NSPredicate(format: "crewID == %@", crewID))
        guard let (results, _) = try? await db.records(matching: query, resultsLimit: 100) else { return [] }
        let removed = await removedMessages(crewID: crewID, leaderID: leaderID)
        let banned = crewID == "all-crews" ? [] : await banned(crewID: crewID, leaderID: leaderID ?? "")
        return results.compactMap { try? $0.1.get() }.compactMap { record -> TVAnnouncement? in
            guard let kind = record["kind"] as? String, kind == "announcement" || kind == "announcementOneWay",
                  let text = record["text"] as? String, let sender = record["senderID"] as? String,
                  includeMine || sender != me, !banned.contains(sender),
                  !removed.contains(record.recordID.recordName),
                  (record["toID"] as? String ?? "all") == "all" else { return nil }
            // A coach's announcement to all crews counts only when a coach or he really wrote it.
            if crewID == "all-crews", !isModerator(writer(of: record), leaderID: nil) { return nil }
            return TVAnnouncement(id: record.recordID.recordName, senderName: record["senderName"] as? String ?? "Crew member",
                                  text: text, sentAt: record["sentAt"] as? Date ?? record.creationDate ?? .now, crewTitle: title)
        }
    }

    private func removedMessages(crewID: String, leaderID: String?) async -> Set<String> {
        let query = CKQuery(recordType: "MessageRemoval", predicate: NSPredicate(format: "crewID == %@", crewID))
        guard let (results, _) = try? await db.records(matching: query) else { return [] }
        return Set(results.compactMap { try? $0.1.get() }
            .filter { isModerator(writer(of: $0), leaderID: leaderID) }
            .compactMap { $0["messageID"] as? String })
    }

    // MARK: Your week and View Home As (private database)

    private func loadPersonal() async -> (week: [TVWeekEntry]?, viewAsName: String?) {
        guard let record = try? await container.privateCloudDatabase.record(for: CKRecord.ID(recordName: "mine")) else { return (nil, nil) }
        let week = (record["week"] as? String).flatMap { try? JSONDecoder().decode([TVWeekEntry].self, from: Data($0.utf8)) }
        let viewAs = record["viewAsLevel"] as? Int == nil ? nil : (record["viewAsName"] as? String ?? "another level")
        return (week, viewAs)
    }

    // MARK: Who wrote it

    /// Mirrors loadCoaches(): coaches are the CoachGrants the head coach wrote.
    private func loadCoaches() async {
        let query = CKQuery(recordType: "CoachGrant", predicate: NSPredicate(value: true))
        guard let (results, _) = try? await db.records(matching: query, resultsLimit: 200) else { return }
        coaches = Set(results.compactMap { try? $0.1.get() }.compactMap { record in
            guard let by = writer(of: record), Self.headCoachIDs.contains(by) else { return nil }
            return record["coachID"] as? String
        })
    }

    private func writer(of record: CKRecord) -> String? {
        guard let name = record.creatorUserRecordID?.recordName else { return nil }
        return name == CKCurrentUserDefaultName ? myID : name
    }

    private func isModerator(_ id: String?, leaderID: String?) -> Bool {
        guard let id else { return false }
        return id == leaderID || Self.headCoachIDs.contains(id) || coaches.contains(id)
    }
}
