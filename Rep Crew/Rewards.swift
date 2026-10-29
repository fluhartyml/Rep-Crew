//
//  Rewards.swift
//  Rep Crew
//
//  Points, awards and weekly leagues, for bragging rights. His words, 2026-10-29 evening: "putting a widget on
//  your phone helps you level up we neeed a level reward system" · "the levels could possibly be a leaderboard
//  on its own" · "for 'bragging rights'" · "level points for winning challenges" · "an award system" ·
//  "begiinner advanced intermediate leaderboards" · "dualingo inspired" (to describe it, not to copy) ·
//  "yes code it".
//
//  REM: SEPARATE FROM ACCESS LEVELS (Access.swift). Points never unlock anything; the 0–255 access level is
//  untouched. Your points level is called "Rep Level" so it never reads as the access "Level" on Home.
//
//  REM: how points are earned (Claude's numbers, shown to him before "yes code it"):
//    10   each day you meet every goal of a challenge
//    25   a 7-day streak in a challenge · 100 at 30 days
//    50   finishing a challenge, with the goal met on at least half its days
//    25   adding the Home Screen widget, once
//    5    sharing to the Lobby, once a day
//    Awards when a crew challenge ends: Most Reps 100 · Iron Streak 75 · Early Bird 75 · Every Day 50.
//  Every point has a date, so the week it counts toward is known. Rep Level = 1 + every 100 points.
//
//  REM: NO SERVER. Each phone works out its own points from its own challenges (honor system, like the reps)
//  and saves one card: a CrewMessage, kind .points, record name "points.<member ID>", on the board "points",
//  its numbers as JSON in the text — no new iCloud record type, so nothing to deploy to Production. Only a card
//  CloudKit says its member wrote counts.
//
//  REM: LEAGUES — Beginner, Intermediate, Advanced. You start where your Lobby fitness level puts you
//  (Starter → Beginner, Steady → Intermediate, Strong or Elite → Advanced). Each week's board is your league,
//  split into groups of about 30 by a fixed shuffle of member IDs, so every phone puts the same people
//  together. It resets Monday. The first time your phone opens in a new week it ranks last week's group:
//  the top few move up a league (with at least 1 point), the bottom few move down (never below Beginner).
//  "A few" is up to 5, and never more than a third of the group, so a group of 2 moves nobody.
//  The board only implies ranking, no place labels — his rule from the leaderboard: "i would imply the
//  ranking and not be explicit."
//
//  REM: Early Bird is read from when each person's finished day was last saved to iCloud (Progress), which is
//  when they finished unless they logged extra after. Close, not exact.
//

import CloudKit
import SwiftData
import SwiftUI
import WidgetKit

enum League: String, CaseIterable, Codable, Identifiable {
    case beginner, intermediate, advanced

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var up: League? { self == .beginner ? .intermediate : self == .intermediate ? .advanced : nil }
    var down: League? { self == .advanced ? .intermediate : self == .intermediate ? .beginner : nil }

    init(fitness: FitnessLevel) {
        switch fitness {
        case .starter: self = .beginner
        case .steady: self = .intermediate
        case .strong, .elite: self = .advanced
        }
    }
}

enum Award: String, CaseIterable, Codable, Identifiable {
    case mostReps, ironStreak, earlyBird, everyDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mostReps: "Most Reps"
        case .ironStreak: "Iron Streak"
        case .earlyBird: "Early Bird"
        case .everyDay: "Every Day"
        }
    }

    var symbol: String {
        switch self {
        case .mostReps: "trophy.fill"
        case .ironStreak: "flame.fill"
        case .earlyBird: "sunrise.fill"
        case .everyDay: "checkmark.seal.fill"
        }
    }

    var points: Int {
        switch self {
        case .mostReps: 100
        case .ironStreak, .earlyBird: 75
        case .everyDay: 50
        }
    }

    var blurb: String {
        switch self {
        case .mostReps: "The highest total by the last day."
        case .ironStreak: "The longest run of days without a miss."
        case .earlyBird: "First to finish on the most days."
        case .everyDay: "Met the goal on every day of the challenge."
        }
    }

    /// Most Reps, Iron Streak and Early Bird need someone to beat; Every Day doesn't.
    var needsRivals: Bool { self != .everyDay }
}

/// One member's numbers, as saved for everyone to see.
struct RewardCard: Codable, Equatable {
    var league = League.beginner.rawValue
    var total = 0
    var week = ""
    var weekPoints = 0
    /// Last week's result, so phones that open later in the week can still rank last week's group.
    var lastWeek = ""
    var lastLeague = ""
    var lastWeekPoints = 0
    /// Award raw value → times won.
    var awards: [String: Int] = [:]

    var repLevel: Int { 1 + total / 100 }
    var leagueValue: League { League(rawValue: league) ?? .beginner }
}

struct RewardEntry: Identifiable {
    let id: String
    let name: String
    let card: RewardCard
}

extension CrewSettings {
    /// Your League raw value; unset until your first sync, which starts it from your fitness level.
    static let league = "rewardLeague"
}

enum Rewards {
    static let board = "points"
    private static let processedWeekKey = "rewardWeekProcessed"
    private static let lastKey = "rewardLastWeek"
    private static let widgetKey = "rewardWidgetAddedAt"
    private static let groupSize = 30

    private static var defaults: UserDefaults { .standard }

    /// Weeks start Monday.
    static var calendar: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        return cal
    }

    static func weekKey(_ date: Date) -> String {
        let cal = calendar
        return "\(cal.component(.yearForWeekOfYear, from: date))-W\(cal.component(.weekOfYear, from: date))"
    }

    static var league: League {
        if let saved = defaults.string(forKey: CrewSettings.league), let league = League(rawValue: saved) { return league }
        return League(fitness: FitnessLevel(rawValue: defaults.string(forKey: CrewSettings.fitnessLevel) ?? "") ?? .starter)
    }

    // MARK: Points

    struct Event {
        let date: Date
        let points: Int
    }

    /// Every point this phone knows you earned, each with the day it was earned.
    @MainActor
    static func events(_ challenges: [Challenge], lobbyDays: Set<Date>) -> [Event] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var events: [Event] = []
        for challenge in challenges {
            var run = 0
            var scheduled = 0
            for day in challenge.allDays where day <= today {
                guard challenge.isScheduled(on: day) else { continue }
                scheduled += 1
                if challenge.isComplete(on: day) {
                    events.append(Event(date: day, points: 10))
                    run += 1
                    if run == 7 { events.append(Event(date: day, points: 25)) }
                    if run == 30 { events.append(Event(date: day, points: 100)) }
                } else if day < today {
                    run = 0
                }
            }
            // The day after it ends (or today, if it was closed early).
            let ended = min(cal.date(byAdding: .day, value: 1, to: challenge.lastDay) ?? today, today)
            if challenge.isFinished, scheduled > 0, challenge.completedDays * 2 >= scheduled {
                events.append(Event(date: ended, points: 50))
            }
            for award in cachedAwards(challenge.crewID) ?? [] {
                events.append(Event(date: ended, points: award.points))
            }
        }
        let widget = defaults.double(forKey: widgetKey)
        if widget > 0 { events.append(Event(date: Date(timeIntervalSince1970: widget), points: 25)) }
        events += lobbyDays.map { Event(date: $0, points: 5) }
        return events
    }

    // MARK: Awards

    private static func awardsKey(_ crewID: String) -> String { "awards.\(crewID)" }

    /// Nil until worked out once, after the challenge ends.
    static func cachedAwards(_ crewID: String) -> [Award]? {
        guard !crewID.isEmpty, let saved = defaults.string(forKey: awardsKey(crewID)) else { return nil }
        return saved.split(separator: ",").compactMap { Award(rawValue: String($0)) }
    }

    /// Reads the whole crew's days from iCloud and returns the awards you won. Nil when iCloud didn't answer.
    @MainActor
    static func workOutAwards(for challenge: Challenge, myID: String) async -> [Award]? {
        let cloud = CrewCloud.shared
        let query = CKQuery(recordType: "Progress", predicate: NSPredicate(format: "crewID == %@", challenge.crewID))
        var records: [CKRecord] = []
        do {
            var (results, cursor) = try await cloud.db.records(matching: query, resultsLimit: CKQueryOperation.maximumResults)
            records += results.compactMap { try? $0.1.get() }
            while let next = cursor {
                (results, cursor) = try await cloud.db.records(continuingMatchFrom: next)
                records += results.compactMap { try? $0.1.get() }
            }
        } catch let error as CKError where error.code == .unknownItem {
            // Nobody ever logged.
        } catch {
            return nil
        }
        let banned = await cloud.banned(crewID: challenge.crewID)

        var totals: [String: Int] = [:]
        var doneDays: [String: Set<Int>] = [:]
        var firstByDay: [Int: (id: String, at: Date)] = [:]
        for record in records {
            guard let id = record["memberID"] as? String, !banned.contains(id),
                  let day = record["dayNumber"] as? Int, day >= 1, day <= challenge.days else { continue }
            totals[id, default: 0] += record["reps"] as? Int ?? 0
            guard (record["complete"] as? Int ?? 0) == 1 else { continue }
            doneDays[id, default: []].insert(day)
            let at = record.modificationDate ?? .distantFuture
            if at < firstByDay[day]?.at ?? .distantFuture { firstByDay[day] = (id, at) }
        }
        // This phone's own days are the truth for you.
        totals[myID] = challenge.allGoals.flatMap(\.allEntries)
            .filter { challenge.dayNumber(on: $0.loggedAt) != nil }.reduce(0) { $0 + $1.count }

        func longestRun(_ days: Set<Int>) -> Int {
            var best = 0, run = 0
            for day in 1...max(challenge.days, 1) {
                run = days.contains(day) ? run + 1 : 0
                best = max(best, run)
            }
            return best
        }
        let people = Set(totals.keys).union(doneDays.keys)
        let streaks = Dictionary(uniqueKeysWithValues: people.map { ($0, longestRun(doneDays[$0] ?? [])) })
        var earlyWins: [String: Int] = [:]
        for (_, first) in firstByDay { earlyWins[first.id, default: 0] += 1 }

        var won: [Award] = []
        let hasRivals = people.count > 1
        if hasRivals, let best = totals.values.max(), best > 0, totals[myID] == best { won.append(.mostReps) }
        if hasRivals, let best = streaks.values.max(), best >= 2, streaks[myID] == best { won.append(.ironStreak) }
        if hasRivals, let best = earlyWins.values.max(), best > 0, earlyWins[myID] == best { won.append(.earlyBird) }
        if challenge.completedDays >= challenge.days || doneDays[myID]?.count == challenge.days { won.append(.everyDay) }
        return won
    }

    // MARK: Cards

    private static func recordID(_ memberID: String) -> CKRecord.ID { CKRecord.ID(recordName: "points.\(memberID)") }

    /// Everyone's card, minus people you blocked and cards someone else wrote.
    @MainActor
    static func loadCards() async -> [RewardEntry] {
        let cloud = CrewCloud.shared
        await cloud.connect()
        let query = CKQuery(recordType: "CrewMessage", predicate: NSPredicate(format: "crewID == %@", board))
        guard let (results, _) = try? await cloud.db.records(matching: query, resultsLimit: CKQueryOperation.maximumResults) else { return [] }
        let blocked = Blocklist.ids
        return results.compactMap { try? $0.1.get() }.compactMap { record in
            guard let message = CrewCloud.message(from: record), message.kind == .points,
                  cloud.writer(of: record) == message.senderID, !blocked.contains(message.senderID),
                  let card = try? JSONDecoder().decode(RewardCard.self, from: Data(message.text.utf8)) else { return nil }
            return RewardEntry(id: message.senderID, name: message.senderName, card: card)
        }
    }

    /// One member's card, for their profile.
    @MainActor
    static func card(for memberID: String) async -> RewardCard? {
        let cloud = CrewCloud.shared
        await cloud.connect()
        guard let record = try? await cloud.db.record(for: recordID(memberID)),
              let message = CrewCloud.message(from: record), message.kind == .points,
              message.senderID == memberID, cloud.writer(of: record) == memberID else { return nil }
        return try? JSONDecoder().decode(RewardCard.self, from: Data(message.text.utf8))
    }

    private static func save(_ card: RewardCard, myID: String, name: String) async {
        guard let json = try? JSONEncoder().encode(card), let text = String(data: json, encoding: .utf8) else { return }
        let record = CKRecord(recordType: "CrewMessage", recordID: recordID(myID))
        record["crewID"] = board
        record["text"] = text
        record["senderID"] = myID
        record["senderName"] = name
        record["kind"] = CrewMessage.Kind.points.rawValue
        record["toID"] = CrewMessage.everyone
        record["sentAt"] = Date.now
        record["title"] = "⭐ \(name)"
        _ = try? await CrewCloud.shared.db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
    }

    // MARK: Groups of about 30

    /// A fixed number from a string (Swift's own hash changes every launch).
    private static func stableHash(_ text: String) -> UInt64 {
        text.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }

    /// The people in `myID`'s group of about 30, from everyone in the league that week.
    static func group(of myID: String, among ids: Set<String>, week: String) -> Set<String> {
        let sorted = ids.union([myID]).sorted { stableHash($0 + week) < stableHash($1 + week) }
        let groups = max(1, Int((Double(sorted.count) / Double(groupSize)).rounded(.up)))
        guard let mine = sorted.firstIndex(of: myID) else { return [myID] }
        return Set(sorted.enumerated().filter { $0.offset % groups == mine % groups }.map(\.element))
    }

    /// How many move up and how many move down in a group this size.
    static func movers(_ count: Int) -> Int { min(5, count / 3) }

    // MARK: Sync

    /// True when a Rep Crew leaderboard widget is on this phone. The callback form works back to iOS 17.
    private static func hasWidget() async -> Bool {
        await withCheckedContinuation { done in
            WidgetCenter.shared.getCurrentConfigurations { result in
                done.resume(returning: (try? result.get())?.contains { $0.kind == WidgetBoardStore.kind } ?? false)
            }
        }
    }

    struct LastWeek: Codable {
        var week: String
        var league: String
        var points: Int
    }

    /// Works out your points, moves you up or down at the start of a new week, and saves your card.
    @MainActor
    static func sync(_ challenges: [Challenge]) async {
        let cloud = CrewCloud.shared
        await cloud.connect()
        guard let myID = cloud.myID else { return }

        // REM: his word, "putting a widget on your phone helps you level up".
        if defaults.double(forKey: widgetKey) == 0, await hasWidget() {
            defaults.set(Date.now.timeIntervalSince1970, forKey: widgetKey)
        }
        for challenge in challenges where challenge.isFinished && !challenge.crewID.isEmpty && cachedAwards(challenge.crewID) == nil {
            if let won = await workOutAwards(for: challenge, myID: myID) {
                defaults.set(won.map(\.rawValue).joined(separator: ","), forKey: awardsKey(challenge.crewID))
            }
        }
        let cal = Calendar.current
        let lobbyDays = Set(await cloud.lobbyPosts().filter { $0.message.senderID == myID }.map { cal.startOfDay(for: $0.message.sentAt) })
        let events = events(challenges, lobbyDays: lobbyDays)

        let now = Date.now
        let thisWeek = weekKey(now)
        let previousWeek = weekKey(cal.date(byAdding: .day, value: -7, to: now) ?? now)
        let cards = await loadCards()
        var league = league

        if defaults.string(forKey: processedWeekKey) != thisWeek {
            if defaults.string(forKey: processedWeekKey) != nil {
                let mine = events.filter { weekKey($0.date) == previousWeek }.reduce(0) { $0 + $1.points }
                var points: [String: Int] = [:]
                for entry in cards where entry.id != myID {
                    if entry.card.week == previousWeek && entry.card.league == league.rawValue {
                        points[entry.id] = entry.card.weekPoints
                    } else if entry.card.lastWeek == previousWeek && entry.card.lastLeague == league.rawValue {
                        points[entry.id] = entry.card.lastWeekPoints
                    }
                }
                points[myID] = mine
                let ranked = group(of: myID, among: Set(points.keys), week: previousWeek)
                    .sorted { (points[$0] ?? 0, $1) > (points[$1] ?? 0, $0) }
                let moving = movers(ranked.count)
                if let place = ranked.firstIndex(of: myID) {
                    let last = LastWeek(week: previousWeek, league: league.rawValue, points: mine)
                    if let json = try? JSONEncoder().encode(last) { defaults.set(json, forKey: lastKey) }
                    if place < moving, mine > 0, let up = league.up { league = up }
                    else if place >= ranked.count - moving, let down = league.down { league = down }
                }
            }
            defaults.set(thisWeek, forKey: processedWeekKey)
            defaults.set(league.rawValue, forKey: CrewSettings.league)
        }

        var card = RewardCard()
        card.league = league.rawValue
        card.total = events.reduce(0) { $0 + $1.points }
        card.week = thisWeek
        card.weekPoints = events.filter { weekKey($0.date) == thisWeek }.reduce(0) { $0 + $1.points }
        if let data = defaults.data(forKey: lastKey), let last = try? JSONDecoder().decode(LastWeek.self, from: data) {
            card.lastWeek = last.week
            card.lastLeague = last.league
            card.lastWeekPoints = last.points
        }
        for challenge in challenges {
            for award in cachedAwards(challenge.crewID) ?? [] { card.awards[award.rawValue, default: 0] += 1 }
        }
        let name = (defaults.string(forKey: CrewSettings.name) ?? "").trimmingCharacters(in: .whitespaces)
        let shownName = name.isEmpty ? "A crew member" : name
        let saved = cards.first { $0.id == myID }
        if saved?.card != card || saved?.name != shownName { await save(card, myID: myID, name: shownName) }
    }
}

// MARK: - Leagues screen

struct LeaguesView: View {
    @Query(sort: \Challenge.startDate, order: .reverse) private var challenges: [Challenge]
    @AppStorage(CrewSettings.league) private var leagueRaw = ""
    @State private var entries: [RewardEntry] = []
    @State private var loaded = false
    @State private var profileOf: ProfileTarget?
    private var cloud = CrewCloud.shared

    private var myID: String { cloud.myID ?? "me" }
    private var league: League { League(rawValue: leagueRaw) ?? Rewards.league }
    private var me: RewardCard? { entries.first { $0.id == myID }?.card }
    private var thisWeek: String { Rewards.weekKey(.now) }

    /// Your group of about 30 in your league this week, by this week's points.
    private var weekly: [RewardEntry] {
        let inLeague = entries.filter { $0.card.week == thisWeek && $0.card.league == league.rawValue }
        let group = Rewards.group(of: myID, among: Set(inLeague.map(\.id)), week: thisWeek)
        return inLeague.filter { group.contains($0.id) }
            .sorted { $0.card.weekPoints != $1.card.weekPoints ? $0.card.weekPoints > $1.card.weekPoints : $0.name < $1.name }
    }

    private var allTime: [RewardEntry] {
        Array(entries.sorted { $0.card.total != $1.card.total ? $0.card.total > $1.card.total : $0.name < $1.name }.prefix(30))
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(league.title) League").font(AppFont.title)
                    Text("This week: \(me?.weekPoints ?? 0) points").font(AppFont.bodyBold)
                    Text("Rep Level \(me?.repLevel ?? 1) · \(me?.total ?? 0) points in all").font(AppFont.body).foregroundStyle(.secondary)
                    if let me { AwardBadges(awards: me.awards) }
                }
                .padding(.vertical, 4)
            }

            Section {
                if !loaded {
                    HStack(spacing: 12) { ProgressView(); Text("Loading…").font(AppFont.body) }
                } else if weekly.isEmpty {
                    Text("No one has points in your league this week yet.").font(AppFont.body)
                }
                ForEach(weekly) { entry in
                    row(entry, value: "\(entry.card.weekPoints) points")
                }
            } header: {
                Text("This week").font(AppFont.bodyBold).textCase(nil)
            } footer: {
                let moving = Rewards.movers(weekly.count)
                Text(moving > 0
                     ? "Starts fresh every Monday. At the end of the week the top \(moving) move up a league and the bottom \(moving) move down."
                     : "Starts fresh every Monday. Once your group has a few more people, the top and bottom of each week move up and down a league.")
                    .font(AppFont.body)
            }

            Section {
                ForEach(allTime) { entry in
                    row(entry, value: "Rep Level \(entry.card.repLevel)")
                }
            } header: {
                Text("All time").font(AppFont.bodyBold).textCase(nil)
            }

            Section {
                earn("Meet every goal of a challenge for the day", 10)
                earn("A 7-day streak in a challenge", 25)
                earn("A 30-day streak in a challenge", 100)
                earn("Finish a challenge, meeting the goal on at least half its days", 50)
                earn("Add the Rep Crew widget to your Home Screen", 25)
                earn("Share to the Lobby, once a day", 5)
            } header: {
                Text("How to earn points").font(AppFont.bodyBold).textCase(nil)
            } footer: {
                Text("Every 100 points is a Rep Level. Points are for bragging rights; they don't change what you can do in the app.").font(AppFont.body)
            }

            Section {
                ForEach(Award.allCases) { award in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: award.symbol).font(AppFont.heading).foregroundStyle(.orange).frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(award.title) · \(award.points) points").font(AppFont.bodyBold)
                            Text(award.blurb).font(AppFont.body).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Awards when a challenge ends").font(AppFont.bodyBold).textCase(nil)
            }
        }
        .navigationTitle("Leagues")
        .navigationBarTitleDisplayMode(.inline)
        .crewNavGlyphs()
        .sheet(item: $profileOf) { ProfileView(target: $0) }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        await Rewards.sync(challenges)
        entries = await Rewards.loadCards()
        loaded = true
    }

    private func row(_ entry: RewardEntry, value: String) -> some View {
        let isMe = entry.id == myID
        return Button { if !isMe { profileOf = ProfileTarget(id: entry.id, name: entry.name) } } label: {
            HStack {
                Text(isMe ? "You" : entry.name).font(isMe ? AppFont.bodyBold : AppFont.body).lineLimit(1)
                Spacer()
                Text(value).font(AppFont.bodyBold).monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func earn(_ text: String, _ points: Int) -> some View {
        HStack(alignment: .top) {
            Text(text).font(AppFont.body)
            Spacer()
            Text("\(points)").font(AppFont.bodyBold).monospacedDigit()
        }
    }
}

/// Award badges, "×2" when won more than once.
struct AwardBadges: View {
    let awards: [String: Int]

    var body: some View {
        let won = Award.allCases.filter { (awards[$0.rawValue] ?? 0) > 0 }
        if !won.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(won) { award in
                    let times = awards[award.rawValue] ?? 0
                    Label(times > 1 ? "\(award.title) ×\(times)" : award.title, systemImage: award.symbol)
                        .font(AppFont.body)
                }
            }
        }
    }
}

/// On a profile: Rep Level, league and awards.
struct RewardsSection: View {
    let card: RewardCard

    var body: some View {
        Section {
            Text("Rep Level \(card.repLevel) · \(card.leagueValue.title) League").font(AppFont.bodyBold)
            Text("\(card.total) points in all").font(AppFont.body).foregroundStyle(.secondary)
            AwardBadges(awards: card.awards)
        } header: {
            Text("Rewards").font(AppFont.bodyBold).textCase(nil)
        }
    }
}
