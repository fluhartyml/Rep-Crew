//
//  HomeTiers.swift
//  Rep Crew
//
//  One Home screen per access range. His words, 2026-10-25: "one home screen per acs defined levels new
//  user, no application, new user application, verified new user, member, message base member, moderator
//  coach and head coach using our crew member metephorical nomenclature" · "yes build all eight home screens".
//
//  REM: each screen is everything the one below it has, plus its own section:
//    0  New user, no application        → welcome card: Send Your Application
//    1  Application not verified        → welcome card: add your email to get verified
//    2  Verified new user               → "Join Your First Challenge" over the challenge list
//    3  Member                          → the standard Home
//    4  Message base member             → Crew Boards: a quick link to each challenge's message board
//    5  Moderator (the crew leader)     → Crews You Lead: who logged today, Message Crew, Close Challenge
//    6  Coach                           → Coach Tools: New Crew Members, User List, Crew Directory
//    7  Head Coach                      → Head Coach Tools: Must-Read, Coaches, Crew Name, Access Levels
//  REM: the screen follows the RANGE a level falls in (by its place in the access table, low to high), so it
//  keeps working when he edits the ranges or renames them. Coach and Head Coach come from Coach Mode
//  (GodMode.isOn / isOwner), as everywhere else. A ninth range he adds below 250 shows the Moderator screen.
//
//  REM: his word, 2026-10-25: "as head coach i need to temporarily pretend to be at each defines crew level so
//  i can shake down each access level as if i were a new user or a crew leader". View Home As sets
//  CrewCloud.viewAsLevel: Home, every ability check (can) and Coach Mode then act on that level. It is in
//  memory only, so quitting the app always ends it, and the bar at the top of Home ends it with one tap.
//

import SwiftUI

enum HomeTier: Int, Comparable {
    case newUser, applied, verified, member, messageBase, moderator, coach, headCoach

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    /// The screen this phone shows now.
    @MainActor static var current: HomeTier {
        if GodMode.isOwner { return .headCoach }
        if GodMode.isOn { return .coach }
        let cloud = CrewCloud.shared
        let level = cloud.effectiveLevel
        if level >= MemberAccessSection.coachLevel { return .coach }
        let index = lowerBands(cloud.accessTable).firstIndex { $0.contains(level) } ?? 0
        return HomeTier(rawValue: min(index, HomeTier.moderator.rawValue)) ?? .newUser
    }

    /// The ranges below Coach, low to high, as closed ranges.
    static func lowerBands(_ table: AccessTable) -> [ClosedRange<Int>] {
        let ranges: [ClosedRange<Int>] = table.bands.map { band in min(band.low, band.high)...max(band.low, band.high) }
        return ranges.filter { $0.lowerBound < MemberAccessSection.coachLevel }.sorted { $0.lowerBound < $1.lowerBound }
    }
}

// MARK: - View Home As (head coach)

/// Every range he can try, by the name in his table, with the level it starts at. Head Coach itself is left out.
@MainActor private var viewAsChoices: [(name: String, level: Int)] {
    CrewCloud.shared.accessTable.bands
        .filter { max($0.low, $0.high) < 255 }
        .sorted { min($0.low, $0.high) < min($1.low, $1.high) }
        .map { ($0.name, min($0.low, $0.high)) }
}

private struct ViewAsMenu<Label: View>: View {
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            ForEach(viewAsChoices, id: \.level) { choice in
                Button("\(choice.name) (\(choice.level))") { CrewCloud.shared.viewAsLevel = choice.level }
            }
            if CrewCloud.shared.viewAsLevel != nil {
                Button("Stop, Back to Head Coach", role: .destructive) { CrewCloud.shared.viewAsLevel = nil }
            }
        } label: { label() }
    }
}

/// The bar at the top of Home while he is viewing as another level.
struct ViewAsBanner: View {
    private var cloud = CrewCloud.shared

    var body: some View {
        if GodMode.isRealOwner, let level = cloud.viewAsLevel {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Viewing as \(cloud.accessTable.band(for: level)?.name ?? "level \(level)")")
                        .font(AppFont.bodyBold)
                    Text("Level \(level). The app acts as this level until you stop or quit it.")
                        .font(AppFont.body).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                ViewAsMenu { Label("Change Level", systemImage: "arrow.up.arrow.down").font(AppFont.bodyBold) }
                Button { cloud.viewAsLevel = nil } label: {
                    Label("Stop, Back to Head Coach", systemImage: "xmark.circle.fill").font(AppFont.bodyBold)
                }
            }
            .listRowBackground(Color.orange.opacity(0.25))
        }
    }
}

// MARK: - 0 and 1: the welcome card

struct WelcomeCardSection: View {
    let tier: HomeTier
    @AppStorage(CrewSettings.crewName) private var crewName = ""
    @State private var applying = false

    var body: some View {
        if tier <= .applied {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome to \(CrewCloud.displayName(crewName))").font(AppFont.heading)
                    Text(tier == .newUser
                         ? "Look around as much as you like. To join and start challenges, send the head coach your application."
                         : "Your application is in. Add your email to it to get verified, then you can join and start challenges.")
                        .font(AppFont.body)
                }
                .padding(.vertical, 4)
                Button { applying = true } label: {
                    Label(tier == .newUser ? "Send Your Application" : "Add Your Email",
                          systemImage: tier == .newUser ? "paperplane.fill" : "envelope.fill")
                        .font(AppFont.bodyBold)
                }
            }
            .sheet(isPresented: $applying) {
                ApplicationView()
                    .task { await CrewCloud.shared.refreshMyAccess() }
            }
        }
    }
}

// MARK: - 4: Crew Boards

/// One challenge's message board on its own page.
struct CrewBoardView: View {
    let challenge: Challenge

    var body: some View {
        List { CrewMessagesSection(challenge: challenge) }
            .navigationTitle(challenge.title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct CrewBoardsSection: View {
    let challenges: [Challenge]

    var body: some View {
        let boards = challenges.filter { !$0.crewID.isEmpty }
        if !boards.isEmpty {
            Section {
                ForEach(boards) { challenge in
                    NavigationLink { CrewBoardView(challenge: challenge) } label: {
                        Label(challenge.title, systemImage: "bubble.left.and.bubble.right.fill").font(AppFont.bodyBold)
                    }
                }
            } header: {
                Text("Crew Boards").font(AppFont.bodyBold).textCase(nil)
            }
        }
    }
}

// MARK: - 5: Crews You Lead

struct CrewsYouLeadSection: View {
    /// Running challenges you started (leaderID empty means this phone leads it).
    let challenges: [Challenge]
    @AppStorage(CrewSettings.name) private var name = ""
    @AppStorage(CrewSettings.closedChallenges) private var closedChallenges = ""
    /// crewID → names of who logged reps today, and how many are in the crew.
    @State private var today: [String: (logged: [String], total: Int)] = [:]
    @State private var closing: Challenge?
    @State private var closeFailed = false

    var body: some View {
        if !challenges.isEmpty {
            Section {
                ForEach(challenges) { challenge in
                    NavigationLink(value: challenge) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(challenge.title).font(AppFont.bodyBold)
                            Text(loggedText(challenge)).font(AppFont.body).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    // Their own rows: two buttons in one List row both fire on a tap (PhotoBoard REM).
                    NavigationLink { CrewBoardView(challenge: challenge) } label: {
                        Label("Message Crew", systemImage: "bubble.left.fill").font(AppFont.body)
                    }
                    Button(role: .destructive) { closing = challenge } label: {
                        Label("Close Challenge", systemImage: "lock.fill").font(AppFont.body)
                    }
                }
                if closeFailed {
                    Text("That didn't go through. Check that you're signed in to iCloud, then try again.").font(AppFont.body)
                }
            } header: {
                Text("Crews You Lead").font(AppFont.bodyBold).textCase(nil)
            }
            .task(id: challenges.map(\.crewID)) { await load() }
            .confirmationDialog("Close \(closing?.title ?? "this challenge")?",
                                isPresented: Binding(get: { closing != nil }, set: { if !$0 { closing = nil } }),
                                titleVisibility: .visible) {
                Button("Close Challenge for Everyone", role: .destructive) {
                    if let challenge = closing { Task { await close(challenge) } }
                }
            } message: {
                Text("It ends today for the whole crew and moves to Finished. Everyone's reps stay. This can't be undone.")
            }
        }
    }

    private func loggedText(_ challenge: Challenge) -> String {
        guard let day = today[challenge.crewID] else { return "Checking who logged today…" }
        if day.logged.isEmpty { return "Nobody has logged today yet · \(day.total) in the crew" }
        return "Logged today: \(day.logged.joined(separator: ", ")) · \(day.logged.count) of \(day.total)"
    }

    private func load() async {
        var found: [String: (logged: [String], total: Int)] = [:]
        for challenge in challenges where !challenge.crewID.isEmpty {
            guard let day = challenge.dayNumber() else { continue }
            let board = await CrewCloud.shared.standings(crewID: challenge.crewID, dayNumber: day)
            found[challenge.crewID] = (board.filter { $0.reps > 0 && !$0.disqualified }.map(\.name).sorted(), board.count)
        }
        today = found
    }

    private func close(_ challenge: Challenge) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let ok = await CrewCloud.shared.close(crewID: challenge.crewID, leaderID: challenge.leaderID,
                                              senderName: trimmed.isEmpty ? "A crew member" : trimmed)
        if ok { closedChallenges = UserDefaults.standard.string(forKey: CrewSettings.closedChallenges) ?? "" }
        closeFailed = !ok
        closing = nil
    }
}

// MARK: - 6: Coach Tools

struct CoachToolsSection: View {
    @AppStorage(CrewSettings.welcomed) private var welcomed = ""
    /// Applications not yet sent a welcome letter.
    @State private var waiting = 0

    var body: some View {
        Section {
            NavigationLink(value: CrewScreen.newMembers) {
                HStack {
                    Label("New Crew Members", systemImage: "person.crop.circle.badge.plus").font(AppFont.bodyBold)
                    Spacer()
                    if waiting > 0 {
                        Text("\(waiting)")
                            .font(AppFont.bodyBold).foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 2)
                            .background(Capsule().fill(.red))
                            .accessibilityLabel("\(waiting) waiting for a welcome letter")
                    }
                }
            }
            NavigationLink(value: CrewScreen.userList) {
                Label("User List", systemImage: "person.3.sequence.fill").font(AppFont.bodyBold)
            }
            NavigationLink(value: CrewScreen.directory) {
                Label("Crew Directory", systemImage: "person.text.rectangle.fill").font(AppFont.bodyBold)
            }
        } header: {
            Text("Coach Tools").font(AppFont.bodyBold).textCase(nil)
        } footer: {
            Text("The number on New Crew Members counts applications that haven't had a welcome letter.").font(AppFont.body)
        }
        .task(id: welcomed) {
            let sent = Set(welcomed.split(separator: "\n").map(String.init))
            waiting = await CrewCloud.shared.applications().filter { !sent.contains($0.id) }.count
        }
    }
}

// MARK: - 7: Head Coach Tools

struct HeadCoachToolsSection: View {
    var body: some View {
        Section {
            NavigationLink { MustReadAdminView() } label: {
                Label("Must-Read Announcements", systemImage: "exclamationmark.bubble.fill").font(AppFont.bodyBold)
            }
            NavigationLink { CoachesView() } label: {
                Label("Coaches", systemImage: "person.2.badge.gearshape.fill").font(AppFont.bodyBold)
            }
            NavigationLink { CrewNameView() } label: {
                Label("Crew Name", systemImage: "character.cursor.ibeam").font(AppFont.bodyBold)
            }
            NavigationLink { AccessTableView() } label: {
                Label("Access Levels", systemImage: "list.number").font(AppFont.bodyBold)
            }
            ViewAsMenu { Label("View Home As…", systemImage: "eye.fill").font(AppFont.bodyBold) }
        } header: {
            Text("Head Coach Tools").font(AppFont.bodyBold).textCase(nil)
        } footer: {
            Text("View Home As lets you use the app as any level, to try it the way a new user or crew leader sees it. It ends when you tap Stop or quit the app.")
                .font(AppFont.body)
        }
    }
}
