//
//  Leaderboard.swift
//  Rep Crew
//
//  Today's crew board. Michael's design, 2026-10-22: "i would insist on a leaderboard",
//  listed in numerical order by TODAY'S reps, starting fresh every morning, with no place
//  labels — "i would imply the ranking and not be explicit." Not the whole-challenge total,
//  because an underdog who is always last would never see a good day pay off.
//
//  Each phone writes one Progress record per challenge day to the crew's iCloud space:
//    Progress  name = crewID.memberID.dayNumber; crewID, memberID, name, dayNumber,
//              reps (today's total across every goal), complete (0/1), streak,
//              minutes, calories (today's matched Health workouts, 2026-10-23; 0 when missing).
//  Day numbers come from the shared start day, so every phone agrees on "today".
//

import CloudKit
import SwiftData
import SwiftUI

struct CrewStanding: Identifiable {
    let id: String
    var name: String
    var reps = 0
    var complete = false
    var streak = 0
    /// Today's matched Health minutes and calories (HealthMatch.swift). Shown under the name; the board still ranks by reps.
    var minutes = 0
    var calories = 0
    /// Banned from this challenge. Their row stays, as "Disqualified", but their profile doesn't open.
    var disqualified = false
}

/// Someone else's challenge, as the whole crew sees it.
struct CrewListing: Identifiable, Hashable {
    let info: Invite.ChallengeInfo
    let leaderID: String
    let leaderName: String

    var id: String { info.crewID }
    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    private var startDate: Date { Calendar.current.startOfDay(for: Invite.date(fromDay: info.startDay) ?? .now) }

    /// 1-based day number today, or nil before it starts.
    var dayNumber: Int? {
        guard let offset = Calendar.current.dateComponents([.day], from: startDate, to: Calendar.current.startOfDay(for: .now)).day,
              offset >= 0, offset < info.days else { return nil }
        return offset + 1
    }

    var status: String {
        if let day = dayNumber { return "Day \(day) of \(info.days)" }
        return "Starts \(startDate.formatted(date: .abbreviated, time: .omitted))"
    }

    /// "Oct 25 – Nov 7".
    var dateRange: String {
        Challenge.dateRange(from: startDate, to: Calendar.current.date(byAdding: .day, value: info.days - 1, to: startDate) ?? startDate)
    }

    var goalsText: String {
        info.goals.map { $0.exerciseUnit.goalText($0.target, name: $0.name) }.joined(separator: " and ") + " a day for \(info.days) days"
    }
}

// MARK: - iCloud

extension CrewCloud {
    /// When anyone in the crew last saved progress, for "active 2 hours ago" on the home list.
    /// His word, 2026-10-25: "i dont see if a challenge is new or if stale". Nil when there's none
    /// or iCloud didn't answer.
    func lastActivity(crewID: String) async -> Date? {
        await connect()
        guard myID != nil, !crewID.isEmpty else { return nil }
        let query = CKQuery(recordType: "Progress", predicate: NSPredicate(format: "crewID == %@", crewID))
        guard let (results, _) = try? await db.records(matching: query, desiredKeys: [], resultsLimit: 400) else { return nil }
        return results.compactMap { try? $0.1.get().modificationDate }.max()
    }

    /// Saves your total for `dayNumber`. Saving the same name again replaces it.
    func postProgress(crewID: String, dayNumber: Int, name: String, reps: Int, complete: Bool, streak: Int,
                      minutes: Int = 0, calories: Int = 0) async {
        await connect()
        guard let myID else { return }
        let record = CKRecord(recordType: "Progress", recordID: CKRecord.ID(recordName: "\(crewID).\(myID).\(dayNumber)"))
        record["crewID"] = crewID
        record["memberID"] = myID
        record["name"] = name
        record["dayNumber"] = dayNumber
        record["reps"] = reps
        record["complete"] = complete ? 1 : 0
        record["streak"] = streak
        // REM: his word 2026-10-25: "they have to opt into sharing any health related metrix". Off unless
        // switched on in Settings → Health; then the crew sees only reps.
        let share = UserDefaults.standard.bool(forKey: CrewSettings.shareHealth)
        record["minutes"] = share ? minutes : 0
        record["calories"] = share ? calories : 0
        do {
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        } catch {
            // REM: until minutes/calories are deployed to Production, a TestFlight save with new fields is
            // refused. Reps matter most, so send them again without the Health fields.
            record["minutes"] = nil
            record["calories"] = nil
            do {
                _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            } catch {
                status = "Couldn't share your reps: \(error.localizedDescription)"
            }
        }
    }

    /// Everyone in the crew with today's reps. Anyone who hasn't logged yet shows 0, and a
    /// streak still counts if they finished yesterday.
    func standings(crewID: String, dayNumber: Int) async -> [CrewStanding] {
        await connect()
        guard myID != nil else { return [] }
        var board: [String: CrewStanding] = [:]
        var leaderID = ""

        // Whoever started it, if they shared it through iCloud.
        if let leader = try? await db.record(for: CKRecord.ID(recordName: crewID)),
           let id = leader["leaderID"] as? String {
            leaderID = id
            board[id] = CrewStanding(id: id, name: leader["leaderName"] as? String ?? "Crew leader")
        }

        // Everyone who joined.
        let joined = CKQuery(recordType: "Membership", predicate: NSPredicate(format: "crewID == %@", crewID))
        if let (results, _) = try? await db.records(matching: joined) {
            for record in results.compactMap({ try? $0.1.get() }) {
                guard let id = record["memberID"] as? String else { continue }
                board[id] = CrewStanding(id: id, name: record["name"] as? String ?? "Crew member")
            }
        }

        // Yesterday's records carry streaks for anyone who hasn't logged today; today's win.
        let days = [dayNumber - 1, dayNumber]
        let progress = CKQuery(recordType: "Progress", predicate: NSPredicate(format: "crewID == %@ AND dayNumber IN %@", crewID, days))
        do {
            let (results, _) = try await db.records(matching: progress)
            let records = results.compactMap { try? $0.1.get() }
                .sorted { ($0["dayNumber"] as? Int ?? 0) < ($1["dayNumber"] as? Int ?? 0) }
            for record in records {
                guard let id = record["memberID"] as? String else { continue }
                var row = board[id] ?? CrewStanding(id: id, name: "Crew member")
                if let name = record["name"] as? String, !name.isEmpty { row.name = name }
                let complete = (record["complete"] as? Int ?? 0) == 1
                if record["dayNumber"] as? Int == dayNumber {
                    row.reps = record["reps"] as? Int ?? 0
                    row.complete = complete
                    row.streak = record["streak"] as? Int ?? 0
                    // Missing on records from older builds → 0.
                    row.minutes = record["minutes"] as? Int ?? 0
                    row.calories = record["calories"] as? Int ?? 0
                } else if complete {
                    row.streak = record["streak"] as? Int ?? 0
                }
                board[id] = row
            }
        } catch let error as CKError where error.code == .unknownItem {
            // No one has logged yet, so the record type doesn't exist yet.
        } catch {
            status = "Couldn't load the crew board: \(error.localizedDescription)"
        }
        // His word: "if a crew member is banned their name is replaced on leaderboards as
        // 'Disqualified'". People you blocked still don't show at all.
        let banned = await banned(crewID: crewID, leaderID: leaderID)
        let blocked = Blocklist.ids
        return board.values.filter { !blocked.contains($0.id) }.map { row in
            var row = row
            if banned.contains(row.id) { row.name = "Disqualified"; row.disqualified = true }
            return row
        }
    }
}

// MARK: - Your standing, from this phone

extension Challenge {
    var repsToday: Int { allGoals.reduce(0) { $0 + $1.total(on: .now) } }

    /// Days in a row with every goal met, through today if it's done, else through yesterday.
    /// REM: his rule for My Week, 2026-10-26: "if your challenge doesnt appear on monday because its on wednesdays
    /// sheet then it is not ripe and hasnt passed its next day in a streak if it is thursday and you didnt do
    /// wednesdays challenge it has broken your streak". Days it isn't on are skipped; a missed day it IS on breaks it.
    var streak: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: .now)
        if isScheduled(on: day) && !isComplete(on: day) { day = cal.date(byAdding: .day, value: -1, to: day) ?? day }
        var count = 0
        while day >= startDate {
            if isScheduled(on: day) {
                guard isComplete(on: day) else { break }
                count += 1
            }
            day = cal.date(byAdding: .day, value: -1, to: day) ?? startDate.addingTimeInterval(-86_400)
        }
        return count
    }

    /// Your row comes from this phone, so a tap shows up on the board at once.
    @MainActor var myStanding: CrewStanding {
        CrewStanding(id: CrewCloud.shared.myID ?? "me", name: "You", reps: repsToday,
                     complete: isComplete(on: .now), streak: streak,
                     minutes: healthMinutesToday, calories: healthCaloriesToday)
    }
}

// MARK: - One challenge's board

/// A challenge's line ("Day N of M · Crew x/y ✓"), then everyone by today's reps.
/// His design: a challenge of one is still on the board — a personal goal others can join.
struct BoardBlock<Link: Hashable>: View {
    var title: String?
    var link: Link?
    let crewID: String
    let day: Int
    let days: Int
    /// What the board's totals count in: the challenge's one unit, or reps when its exercises differ.
    var unit: ExerciseUnit = .reps
    /// You, when you're in this challenge.
    var me: CrewStanding?
    /// You lead this challenge, so you can remove people from it.
    var canBan = false

    @State private var others: [CrewStanding] = []
    @State private var banning: CrewStanding?
    @State private var blocking: CrewStanding?
    @State private var profileOf: ProfileTarget?
    @State private var reload = 0

    /// Highest reps first. Ties go alphabetical so the order doesn't jump around.
    private var rows: [CrewStanding] {
        let rest = others.filter { $0.id != me?.id }
        return ((me.map { [$0] } ?? []) + rest)
            .sorted { $0.reps != $1.reps ? $0.reps > $1.reps : $0.name < $1.name }
    }

    var body: some View {
        Group {
            if let link {
                NavigationLink(value: link) { heading }
            } else {
                heading
            }
            ForEach(rows) { row in
                standing(row)
                    .contextMenu {
                        if row.id != me?.id {
                            Button { blocking = row } label: {
                                Label("Block \(row.name)", systemImage: "hand.raised.fill")
                            }
                            if canBan {
                                Button(role: .destructive) { banning = row } label: {
                                    Label("Remove from Challenge", systemImage: "person.fill.xmark")
                                }
                            }
                            // His word: "i should be able to grant and ungrant coach permissions
                            // to worthy individuals". Only he sees this.
                            AccessLevelMenu(memberID: row.id, name: row.name)
                            if GodMode.isOwner && !GodMode.ids.contains(row.id) {
                                let isCoach = CrewCloud.shared.coaches[row.id] != nil
                                Button {
                                    Task { _ = await CrewCloud.shared.setCoach(row.id, name: row.name, on: !isCoach) }
                                } label: {
                                    Label(isCoach ? "Remove Coach" : "Make Coach",
                                          systemImage: isCoach ? "person.badge.minus" : "person.badge.shield.checkmark")
                                }
                            }
                        }
                    }
            }
        }
        .confirmationDialog("Remove \(banning?.name ?? "them") from this challenge?",
                            isPresented: Binding(get: { banning != nil }, set: { if !$0 { banning = nil } }),
                            titleVisibility: .visible, presenting: banning) { row in
            Button("Remove and Ban", role: .destructive) {
                Task {
                    if await CrewCloud.shared.ban(crewID: crewID, memberID: row.id, name: row.name) { reload += 1 }
                }
            }
        } message: { _ in
            Text("Their name shows as Disqualified on the board, their photos and messages are hidden, and they can't rejoin.")
        }
        .confirmationDialog("Block \(blocking?.name ?? "them")?",
                            isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } }),
                            titleVisibility: .visible, presenting: blocking) { row in
            Button("Block", role: .destructive) {
                Blocklist.block(row.id, name: row.name)
                reload += 1
            }
        } message: { _ in
            Text("You won't see their reps, photos or messages anywhere. They aren't told. Unblock in Settings.")
        }
        .sheet(item: $profileOf, onDismiss: { reload += 1 }) { ProfileView(target: $0) }
        // Keeps the board current while the screen is open.
        .task(id: "\(crewID).\(day).\(reload)") {
            guard !crewID.isEmpty else { return }
            while !Task.isCancelled {
                others = await CrewCloud.shared.standings(crewID: crewID, dayNumber: day)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// REM: his word, 2026-10-23: "the crew each need a profile page". A tap on a name opens it —
    /// the board is where the whole crew is listed. Not before iCloud answers, and not for someone banned.
    @ViewBuilder private func standing(_ row: CrewStanding) -> some View {
        if row.disqualified || row.id == "me" {
            StandingRow(row: row, isMe: row.id == me?.id, unit: unit)
        } else {
            Button { profileOf = ProfileTarget(id: row.id, name: row.name) } label: {
                StandingRow(row: row, isMe: row.id == me?.id, unit: unit).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens their profile")
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title { Text(title).font(AppFont.heading) }
            Text("Day \(day) of \(days) · Crew \(rows.filter(\.complete).count)/\(rows.count) ✓")
                .font(AppFont.bodyBold)
                .foregroundStyle(title == nil ? .primary : .secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - On the challenge screen

struct LeaderboardSection: View {
    let challenge: Challenge
    @AppStorage(CrewSettings.name) private var name = ""

    var body: some View {
        if let day = challenge.dayNumber(), !challenge.crewID.isEmpty {
            Section {
                BoardBlock<Challenge>(crewID: challenge.crewID, day: day, days: challenge.days, unit: challenge.sharedUnit, me: challenge.myStanding,
                                      canBan: challenge.leaderID.isEmpty || GodMode.isOn)
            } header: {
                Text("Leaderboard").font(AppFont.bodyBold).textCase(nil)
            }
            // Re-runs whenever your reps change; the short wait lets a run of taps land as one save.
            .task(id: "\(day).\(challenge.repsToday).\(challenge.isComplete(on: .now)).\(challenge.healthMinutesToday).\(challenge.healthCaloriesToday)") {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                // A challenge rebuilt from the crew's copy (CrewRestore.swift) may not know how today's reps
                // split between exercises; don't post a lower total over what the crew's board already has.
                guard !(day == challenge.restoredDay && challenge.repsToday < challenge.restoredRepsToday) else { return }
                let me = name.trimmingCharacters(in: .whitespaces)
                await CrewCloud.shared.postProgress(crewID: challenge.crewID, dayNumber: day,
                                                    name: me.isEmpty ? "A crew member" : me,
                                                    reps: challenge.repsToday, complete: challenge.isComplete(on: .now),
                                                    streak: challenge.streak,
                                                    minutes: challenge.healthMinutesToday, calories: challenge.healthCaloriesToday)
                await announceFinished(day: day, me: me)
            }
        }
    }
}

extension LeaderboardSection {
    /// Roadmap 7, from the original call: "James completed his daily challenge" goes to the crew.
    /// Once per challenge day, the first time every goal is met; an undo and redo doesn't resend.
    func announceFinished(day: Int, me: String) async {
        guard challenge.isComplete(on: .now) else { return }
        let key = "finished.\(challenge.crewID).\(day)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let goals = challenge.sortedGoals.map { $0.unit.goalText($0.dailyTarget, name: $0.name) }.joined(separator: " and ")
        if await CrewCloud.shared.send("Finished today: \(goals). Day \(day) of \(challenge.days).",
                                       crewID: challenge.crewID, kind: .finished,
                                       senderName: me.isEmpty ? "A crew member" : me) {
            UserDefaults.standard.set(true, forKey: key)
        }
    }
}

private struct StandingRow: View {
    let row: CrewStanding
    let isMe: Bool
    var unit: ExerciseUnit = .reps

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name).font(isMe ? AppFont.bodyBold : AppFont.body).lineLimit(1)
                    VerifiedSeal(memberID: row.id)
                }
                // Only when nonzero. Plain numbers from Health — no ring words.
                if !healthLine.isEmpty {
                    Text(healthLine).font(AppFont.body).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Spacer()
            Text(unit.label(row.reps)).font(AppFont.bodyBold).monospacedDigit()
            if row.streak > 0 {
                Text("🔥 \(row.streak)").font(AppFont.body).monospacedDigit()
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.name), \(unit.label(row.reps)) today" + (healthLine.isEmpty ? "" : ", \(healthLine) from Health")
                            + (row.streak > 0 ? ", \(row.streak) day streak" : ""))
    }

    private var healthLine: String {
        [row.minutes > 0 ? "\(row.minutes) min" : nil, row.calories > 0 ? "\(row.calories) cal" : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Every board, grouped

/// His word, 2026-10-22: "grouped by if the user is a member of the challenge and the
/// grouping of all other challenges."
struct LeaderboardsView: View {
    @Query(sort: \Challenge.startDate, order: .reverse) private var challenges: [Challenge]
    @State private var listings: [CrewListing] = []

    private var mine: [Challenge] { challenges.filter { $0.isActive && !$0.crewID.isEmpty } }
    private var others: [CrewListing] {
        let joined = Set(challenges.map(\.crewID))
        return listings.filter { !joined.contains($0.id) && $0.dayNumber != nil }
    }

    var body: some View {
        List {
            // REM: his word, 2026-10-23: "yes do it". A fifth Home button pushed Leaderboards and + into
            // an overflow menu that wouldn't open on the 11 Pro (build 64), so the directory lives here.
            Section {
                NavigationLink(value: CrewScreen.directory) {
                    Label("Crew Directory", systemImage: "person.3.fill").font(AppFont.bodyBold)
                }
            }
            Section {
                if mine.isEmpty {
                    Text("You're not in a challenge running today.").font(AppFont.body)
                }
                ForEach(mine) { challenge in
                    if let day = challenge.dayNumber() {
                        BoardBlock(title: challenge.title, link: challenge, crewID: challenge.crewID,
                                   day: day, days: challenge.days, unit: challenge.sharedUnit, me: challenge.myStanding,
                                   canBan: challenge.leaderID.isEmpty || GodMode.isOn)
                    }
                }
            } header: {
                Text("Your challenges").font(AppFont.bodyBold).textCase(nil)
            }
            Section {
                if others.isEmpty {
                    Text("No one else has a public challenge running today.").font(AppFont.body)
                }
                ForEach(others) { listing in
                    if let day = listing.dayNumber {
                        BoardBlock(title: listing.info.title, link: listing, crewID: listing.id,
                                   day: day, days: listing.info.days, unit: listing.info.sharedUnit)
                    }
                }
            } header: {
                Text("Other challenges").font(AppFont.bodyBold).textCase(nil)
            }
        }
        .navigationTitle("Leaderboards")
        .navigationBarTitleDisplayMode(.inline)
        .crewNavGlyphs(showBoards: false)
        .task { listings = await CrewCloud.shared.crewChallenges() }
        .refreshable { listings = await CrewCloud.shared.crewChallenges() }
    }
}

// MARK: - Finding your way

/// Pushed screens that aren't Home.
enum CrewScreen: Hashable { case leaderboards, directory, newMembers, inbox, events, userList, library, myWeek, challenges }

/// Home and Leaderboards, one tap from any screen. His word: "maybe a home glyph for non
/// home sheets so you can always find your way home".
struct CrewNav {
    var goHome: () -> Void = {}
    var openBoards: () -> Void = {}
}

private struct CrewNavKey: EnvironmentKey {
    static let defaultValue = CrewNav()
}

extension EnvironmentValues {
    var crewNav: CrewNav {
        get { self[CrewNavKey.self] }
        set { self[CrewNavKey.self] = newValue }
    }
}

private struct CrewNavGlyphs: ViewModifier {
    @Environment(\.crewNav) private var nav
    let showBoards: Bool

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if showBoards {
                    Button { nav.openBoards() } label: {
                        Image(systemName: "chart.bar.fill").font(AppFont.bodyBold)
                    }
                    .accessibilityLabel("Leaderboards")
                }
                Button { nav.goHome() } label: {
                    Image(systemName: "house.fill").font(AppFont.bodyBold)
                }
                .accessibilityLabel("Home")
            }
        }
    }
}

extension View {
    func crewNavGlyphs(showBoards: Bool = true) -> some View {
        modifier(CrewNavGlyphs(showBoards: showBoards))
    }
}

// MARK: - Someone else's challenge

struct CrewChallengeView: View {
    let listing: CrewListing

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(listing.status).font(AppFont.title)
                    Text(listing.goalsText).font(AppFont.body)
                    Text("Led by \(listing.leaderName)").font(AppFont.body).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            AskToJoinSection(listing: listing)
            if let day = listing.dayNumber {
                Section {
                    BoardBlock<CrewListing>(crewID: listing.id, day: day, days: listing.info.days, canBan: GodMode.isOn)
                } header: {
                    Text("Leaderboard").font(AppFont.bodyBold).textCase(nil)
                }
            }
            PhotoBoardSection(crewID: listing.id, leaderID: listing.leaderID, canAdd: false)
        }
        .navigationTitle(listing.info.title)
        .navigationBarTitleDisplayMode(.inline)
        .crewNavGlyphs()
    }
}
