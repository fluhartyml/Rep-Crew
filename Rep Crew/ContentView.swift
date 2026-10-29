//
//  ContentView.swift
//  Rep Crew
//
//  The list of challenges: running now, starting later, and finished.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    /// An invite link the app was opened with (held by RootView until you're signed in).
    @Binding var openedURL: URL?
    @Environment(\.modelContext) private var context
    @Query(sort: \Challenge.startDate, order: .reverse) private var challenges: [Challenge]
    @Query private var crew: [CrewMember]
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(CrewSettings.declined) private var declined = ""
    @AppStorage(CrewSettings.name) private var name = ""
    @AppStorage(CrewSettings.testFlight) private var testFlight = ""
    @AppStorage(CrewSettings.crewNumber) private var crewNumber = 0
    @AppStorage(CrewSettings.crewName) private var crewName = ""
    @AppStorage(CrewSettings.inboxUnread) private var inboxUnread = 0
    @AppStorage(CrewSettings.inboxOpened) private var inboxOpened = 0.0
    /// Read by the lists below so they redraw the moment a closing arrives (ChallengeClose.swift).
    @AppStorage(CrewSettings.closedChallenges) private var closedChallenges = ""
    @State private var listings: [CrewListing] = []
    /// Home's three reveals (Smitty's drop-down), remembered on this phone.
    @AppStorage("home.reveal.active") private var showActive = true
    @AppStorage("home.reveal.available") private var showAvailable = false
    @AppStorage("home.reveal.finished") private var showFinished = false
    /// crewID → when anyone in the crew last saved progress (lastActivity).
    @State private var activity: [String: Date] = [:]
    /// A past challenge to run again (NewChallengeView(again:)).
    @State private var again: Invite.ChallengeInfo?
    private var cloud = CrewCloud.shared

    @State private var showingNew = false
    @State private var showingAbout = false
    @State private var showingSettings = false
    @State private var messagingHeadCoach = false
    @State private var joining: Invite?
    @State private var path = NavigationPath()
    /// Head coach announcements not yet accepted on this phone (MustRead.swift).
    @State private var mustRead: [CrewMessage] = []
    /// Events you posted that haven't ended (HomeTiers.swift → My Events).
    @State private var myEvents: [CrewEvent] = []

    private var active: [Challenge] { _ = closedChallenges; return challenges.filter(\.isActive) }
    /// Changes whenever today's numbers do, so the Watch gets a fresh copy.
    private var watchSignature: String { challenges.map { "\($0.title).\($0.repsToday)" }.joined(separator: "|") }
    /// Changes when your week does, so the Apple TV board gets it (TVShare.swift).
    private var weekSignature: String { challenges.map { "\($0.crewID).\($0.title).\($0.weekdays).\($0.isFinished)" }.joined(separator: "|") }
    private var upcoming: [Challenge] { _ = closedChallenges; return challenges.filter { !$0.hasStarted && !$0.isClosed } }
    private var finished: [Challenge] { _ = closedChallenges; return challenges.filter(\.isFinished) }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                // REM: one Home per access range (HomeTiers.swift). Always the list now, so Inbox, Events and
                // the welcome card show even before the first challenge; "No challenges yet" became a section.
                let tier = HomeTier.current
                    List {
                        ViewAsBanner()
                        // REM: his word, 2026-10-29: "swipe right and left between your groups you are in" (Groups.swift).
                        GroupsPagerSection()
                        // REM: his word, 2026-10-25: Home "integrated with the user profile", headed by role.
                        ProfileCardSection(tier: tier)
                        WelcomeCardSection(tier: tier)
                        // REM: his word, 2026-10-26: "crew member should say 'My Memberships' because it is plural you
                        // have more than one challenge", moved "above head coach" · "yes build it". Crew = the group;
                        // My Memberships = what you belong to (Developer Notes, OFFICIAL WORDS).
                        Section {
                            // A row, not a toolbar button: a fifth toolbar button pushed others into an overflow menu (build 61).
                            NavigationLink(value: CrewScreen.inbox) {
                                HStack {
                                    Label("Inbox", systemImage: "tray.full.fill").font(AppFont.bodyBold)
                                    Spacer()
                                    if inboxUnread > 0 {
                                        Text("\(inboxUnread)")
                                            .font(AppFont.bodyBold).foregroundStyle(.white)
                                            .padding(.horizontal, 10).padding(.vertical, 2)
                                            .background(Capsule().fill(.red))
                                            .accessibilityLabel("\(inboxUnread) unread")
                                    }
                                }
                            }
                            // REM: his idea 2026-10-24, the Events board (Events.swift).
                            NavigationLink(value: CrewScreen.events) {
                                Label("Events", systemImage: "pin.fill").font(AppFont.bodyBold)
                            }
                            // REM: his word, 2026-10-29: "please code the feed by level" — the Lobby (Lobby.swift).
                            NavigationLink { LobbyView() } label: {
                                Label("Lobby", systemImage: "person.3.sequence.fill").font(AppFont.bodyBold)
                            }
                            // REM: his word, 2026-10-26: "it probably should have challenges > just like myweek> does",
                            // and his "yes build it" — Active, Available and Finished moved off Home onto one page.
                            NavigationLink(value: CrewScreen.challenges) {
                                HStack {
                                    Label("Challenges", systemImage: "flag.checkered").font(AppFont.bodyBold)
                                    Spacer()
                                    Text("\(active.count) active").font(AppFont.body).foregroundStyle(.secondary)
                                }
                            }
                            // REM: Smitty's weekly schedule, his design 2026-10-26 (MyWeek.swift).
                            NavigationLink(value: CrewScreen.myWeek) {
                                Label("My Week", systemImage: "calendar").font(AppFont.bodyBold)
                            }
                            // REM: his word, 2026-10-26: a library of every challenge ever made (Library.swift).
                            NavigationLink(value: CrewScreen.library) {
                                Label("Library", systemImage: "books.vertical.fill").font(AppFont.bodyBold)
                            }
                            // REM: his word, 2026-10-26: "there thould be a send message to head coach … like 'message
                            // to sysop'" · "yes build it". A direct message into his Inbox; he answers from there.
                            // Not shown to him (he'd be writing to himself), except while he views Home as another
                            // level, so he can test it (his "ill use view as").
                            if !GodMode.isOwner, let headCoach = GodMode.ids.first {
                                Button { messagingHeadCoach = true } label: {
                                    Label("Message the Head Coach", systemImage: "envelope.fill").font(AppFont.bodyBold)
                                }
                                .sheet(isPresented: $messagingHeadCoach) {
                                    InboxComposeView(target: ProfileTarget(id: headCoach, name: "the Head Coach"))
                                }
                            }
                        } header: {
                            Text("My Memberships").font(AppFont.bodyBold).textCase(nil)
                        }
                        if tier == .headCoach { HeadCoachToolsSection() }
                        // REM: his word, 2026-10-25: "on the head coach home page to be quick links to user list
                        // editor". User List now sits in the Coach section, with New Crew Members and the Directory.
                        if tier >= .coach { CoachToolsSection() }
                        if tier >= .moderator {
                            CrewsYouLeadSection(challenges: active.filter { $0.leaderID.isEmpty && !$0.crewID.isEmpty })
                        }
                        MyEventsSection(events: myEvents) { Task { await loadMyEvents() } }
                        invitations
                        if tier >= .messageBase { CrewBoardsSection(challenges: active) }
                        // A brand-new member with nothing yet still sees "Join Your First Challenge" right on Home.
                        if firstTime { crewChallenges(title: "Join Your First Challenge") }
                        if challenges.isEmpty && cloud.pending.isEmpty && others.isEmpty && cloud.can(.start) { emptyState }
                    }
                    .refreshable { await syncCrew() }
            }
            .task { await syncCrew() }
            // Matched Health workouts check off days on Home too; asks for nothing until something is paired.
            .task(id: scenePhase) {
                if scenePhase == .active, challenges.contains(where: \.countsHealth) { await HealthLibrary.shared.refresh() }
            }
            .task(id: watchSignature) { WatchBridge.shared.sendGoals(challenges) }
            // Reps-to-go reminders (RepReminders.swift) and the widget follow every logged rep, and catch up when the app comes back.
            .task(id: "\(watchSignature).\(scenePhase == .active)") {
                guard scenePhase == .active else { return }
                WidgetSync.applyTaps(challenges, context: context)   // + taps from the widget first
                WidgetSync.save(challenges)   // the Home Screen widget (WidgetSync.swift)
                await RepReminders.reschedule(challenges)
            }
            .task(id: weekSignature) {
                // REM: a short wait so tapping through the weekday sheets saves once, not on every tap.
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                await cloud.saveWeek(challenges)
            }
            // A coach tapped a "joined the crew" notification (CrewNotifications).
            .onChange(of: cloud.openNewMembers, initial: true) { _, open in
                guard open else { return }
                cloud.openNewMembers = false
                path.append(CrewScreen.newMembers)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await syncCrew() } }
            }
            .task(id: scenePhase) {
                if scenePhase == .active { mustRead = await cloud.unacceptedMustReads() }
            }
            // Points, awards and the weekly league move (Rewards.swift), each time the app comes to the front.
            .task(id: scenePhase) {
                if scenePhase == .active { await Rewards.sync(challenges) }
            }
            .fullScreenCover(item: Binding(get: { mustRead.first }, set: { _ in })) { message in
                MustReadView(message: message) {
                    MustRead.accept(message.id)
                    mustRead.removeAll { $0.id == message.id }
                }
            }
            .navigationTitle(CrewCloud.displayName(crewName))   // the head coach's name for the crew (CrewName.swift)
            .navigationDestination(for: Challenge.self) { ChallengeDetailView(challenge: $0) }
            .navigationDestination(for: CrewListing.self) { CrewChallengeView(listing: $0) }
            .navigationDestination(for: CrewGroup.self) { GroupHomeView(group: $0) }
            .navigationDestination(for: CrewScreen.self) { screen in
                switch screen {
                case .leaderboards: LeaderboardsView()
                case .directory: CrewDirectoryView()
                case .newMembers: ApplicationsView()
                case .inbox: InboxView(challenges: challenges) { joining = $0 }
                case .events: EventsView()
                case .userList: UserListView()
                case .library: LibraryView()
                case .myWeek: MyWeekView()
                case .challenges: challengesPage
                case .leagues: LeaguesView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingAbout = true } label: {
                        Image(systemName: "info.circle").font(AppFont.heading)
                    }
                    .accessibilityLabel("About Rep Crew")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape").font(AppFont.heading)
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { path.append(CrewScreen.leaderboards) } label: {
                        Image(systemName: "chart.bar.fill").font(AppFont.heading)
                    }
                    .accessibilityLabel("Leaderboards")
                }
                // Access level (Access.swift): only ranges allowed to start challenges get the + button.
                ToolbarItem(placement: .topBarTrailing) {
                    if cloud.can(.start) { Button { showingNew = true } label: {
                        Image(systemName: "plus.circle.fill").font(AppFont.heading)
                    }
                    .accessibilityLabel("New challenge") }
                }
            }
            .sheet(isPresented: $showingNew) { NewChallengeView() }
            .sheet(item: Binding(get: { again.map(AgainItem.init) }, set: { again = $0?.info })) { NewChallengeView(again: $0.info) }
            .sheet(isPresented: $showingAbout) { AboutView() }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(item: $joining) { JoinView(invite: $0) }
            .onChange(of: openedURL, initial: true) { _, url in
                guard let url else { return }
                openedURL = nil
                // REM: the widget opens its challenge: repcrew://challenge?crew=<crewID> (LeaderboardWidget.swift).
                if url.host == "challenge" {
                    let crewID = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "crew" }?.value
                    if let challenge = challenges.first(where: { $0.crewID == crewID }) {
                        path = NavigationPath()
                        path.append(challenge)
                    }
                    return
                }
                joining = Invite(url: url)
            }
            .onReceive(NotificationCenter.default.publisher(for: .widgetTapped)) { _ in
                WidgetSync.applyTaps(challenges, context: context)
            }
        }
        .environment(\.crewNav, CrewNav(goHome: { path = NavigationPath() },
                                        openBoards: { path.append(CrewScreen.leaderboards) }))
    }

    private var firstTime: Bool { HomeTier.current == .verified && challenges.isEmpty }

    /// Home → Challenges. REM: Smitty's ask, 2026-10-26, his "yes build it": "one thing that says finished challenges
    /// active challenges available challenges … then you click on those and it would … just open up the next page" —
    /// a drop-down, so a crowded app never buries Home. Three reveals, each remembered on this phone: Active open,
    /// Available and Finished closed until tapped. Moved here from Home at his word the same day.
    private var challengesPage: some View {
        List {
            section("Active challenges", active + upcoming.reversed(), isOpen: $showActive)
            crewChallenges(title: firstTime ? "Join Your First Challenge" : "Available challenges")
            section("Finished challenges", finished, isOpen: $showFinished, libraryLink: true)
        }
        .refreshable { await syncCrew() }
        .navigationTitle("Challenges")
    }

    /// A tappable section header with a chevron that opens and closes it.
    private func revealHeader(_ title: String, count: Int, isOpen: Binding<Bool>) -> some View {
        Button { withAnimation { isOpen.wrappedValue.toggle() } } label: {
            HStack {
                Text(title).font(AppFont.bodyBold)
                Text("\(count)").font(AppFont.body).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right").font(AppFont.bodyBold)
                    .rotationEffect(.degrees(isOpen.wrappedValue ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .accessibilityValue(isOpen.wrappedValue ? "Open" : "Closed")
        .accessibilityHint("Shows or hides these challenges")
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [Challenge], isOpen: Binding<Bool>, libraryLink: Bool = false) -> some View {
        Section {
            if isOpen.wrappedValue {
                if items.isEmpty && !libraryLink {
                    Text("None right now.").font(AppFont.body).foregroundStyle(.secondary)
                }
                ForEach(items) { challenge in
                    NavigationLink(value: challenge) { ChallengeRow(challenge: challenge, crewActivity: activity[challenge.crewID]) }
                    // Its own row: two buttons in one List row both fire on a tap (PhotoBoard REM).
                    if challenge.isFinished && cloud.can(.start) {
                        Button { again = Invite.ChallengeInfo(challenge) } label: {
                            Label("Start Again", systemImage: "arrow.counterclockwise").font(AppFont.body)
                        }
                        .deleteDisabled(true)   // a swipe here must not delete the challenge above it
                    }
                }
                .onDelete { offsets in
                    // REM: a challenge you delete stays deleted: without this, CrewRestore would rebuild
                    // it from the crew's copy on the next sync. Kept on this phone only (declined list).
                    let gone = offsets.map { items[$0].crewID }.filter { !$0.isEmpty }
                    if !gone.isEmpty { declined = (declined.split(separator: "\n").map(String.init) + gone).joined(separator: "\n") }
                    for index in offsets { context.delete(items[index]) }
                    try? context.save()
                }
                if libraryLink {
                    NavigationLink(value: CrewScreen.library) {
                        Label("Library: every challenge ever made", systemImage: "books.vertical.fill").font(AppFont.body)
                    }
                }
            }
        } header: {
            revealHeader(title, count: items.count, isOpen: isOpen)
        }
    }

    /// Challenges a leader checked you off for, waiting on Accept or Decline.
    @ViewBuilder
    private var invitations: some View {
        if !cloud.pending.isEmpty {
            Section {
                ForEach(cloud.pending) { invite in
                    Button { joining = invite } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(invite.challenge?.title ?? "Challenge").font(AppFont.bodyBold).foregroundStyle(.primary)
                            Text("From \(invite.from) · tap to accept or decline").font(AppFont.body).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Invitations").font(AppFont.bodyBold).textCase(nil)
            }
        }
    }

    /// Everyone else's challenges: not on this phone and not already waiting as an invitation.
    private var others: [CrewListing] {
        let mine = Set(challenges.map(\.crewID)).union(cloud.pending.compactMap { $0.challenge?.crewID })
        _ = closedChallenges
        // A coach's closing leaves the leader's record running, so it's filtered here too.
        return listings.filter { !mine.contains($0.id) && !ChallengeClosure.isClosed($0.id) }.sorted { $0.info.startDay > $1.info.startDay }
    }

    @ViewBuilder
    private func crewChallenges(title: String) -> some View {
        // A verified new user with nothing yet sees "Join Your First Challenge" open, whatever was saved.
        let firstTime = title == "Join Your First Challenge"
        let isOpen = firstTime ? .constant(true) : $showAvailable
        Section {
            if isOpen.wrappedValue {
                if others.isEmpty {
                    Text("None right now.").font(AppFont.body).foregroundStyle(.secondary)
                }
                ForEach(others) { listing in
                    NavigationLink(value: listing) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(listing.info.title).font(AppFont.bodyBold)
                            Text("\(listing.leaderName) · \(listing.status)").font(AppFont.body)
                            Text("\(listing.dateRange) · \(Challenge.activityText(activity[listing.id]))")
                                .font(AppFont.body).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        } header: {
            revealHeader(title, count: others.count, isOpen: isOpen)
        }
    }

    /// Pulls in who has joined your challenges, and challenges you've been checked off for.
    private func syncCrew() async {
        // Challenges this phone lost (app deleted before they reached your iCloud) come back from the crew's copy.
        await CrewRestore.run(context: context, declined: Set(declined.split(separator: "\n").map(String.init)))
        // Closings first: ensurePublished would put a closed challenge's end date back.
        await cloud.refreshClosures(Dictionary(challenges.filter { !$0.crewID.isEmpty }.map { ($0.crewID, $0.leaderID) },
                                               uniquingKeysWith: { first, _ in first }))
        // Challenges you started go to the shared space so the whole crew can see them.
        let leader = name.trimmingCharacters(in: .whitespaces)
        for challenge in challenges where challenge.leaderID.isEmpty && !challenge.isFinished {
            if challenge.crewID.isEmpty { challenge.crewID = UUID().uuidString }
            await cloud.ensurePublished(Invite.ChallengeInfo(challenge), leaderName: leader.isEmpty ? "Your crew leader" : leader,
                                        leaderNumber: crewNumber, testFlight: testFlight.trimmingCharacters(in: .whitespaces),
                                        isPublic: challenge.isPublic)
        }
        for member in await cloud.members() where !crew.contains(where: { $0.cloudID == member.id }) {
            context.insert(CrewMember(name: member.name, crewNumber: member.number, cloudID: member.id))
        }
        try? context.save()
        let skip = Set(challenges.map(\.crewID).filter { !$0.isEmpty })
            .union(declined.split(separator: "\n").map(String.init))
        await cloud.refreshPending(skipping: skip)
        await CrewNotifications.requestPermission()
        // A leader's Edit Exercises reaches your copy of their challenge (EditExercises.swift).
        await GoalSync.run(challenges, context: context)
        let found = await cloud.crewChallenges()
        await cloud.refreshClosures(Dictionary(found.map { ($0.id, $0.leaderID) }, uniquingKeysWith: { first, _ in first }))
        listings = found
        var seen: [String: Date] = [:]
        for crewID in Set(challenges.filter { !$0.isFinished }.map(\.crewID) + found.map(\.id)) where !crewID.isEmpty {
            if let date = await cloud.lastActivity(crewID: crewID) { seen[crewID] = date }
        }
        activity = seen
        await loadMyEvents()
        // Your real user number (Application.swift → userNumbers), replacing the invite-chain one.
        if let myID = cloud.myID, let number = await cloud.userNumbers()[myID] { crewNumber = number }
        let inboxCrewIDs = challenges.map(\.crewID).filter { !$0.isEmpty }
        let inboxLed = challenges.filter { $0.leaderID.isEmpty && !$0.crewID.isEmpty }.map(\.crewID)
        InboxBadge.remember(crewIDs: inboxCrewIDs, led: inboxLed)
        let inbox = await cloud.inbox(crewIDs: inboxCrewIDs, led: inboxLed)
        await InboxBadge.set(InboxBadge.unread(inbox, since: inboxOpened))
        // Each respects its Settings → Notifications switch, so one turned off isn't re-created here.
        await cloud.subscribe(crewIDs: challenges.map(\.crewID).filter { !$0.isEmpty }, listedCrewIDs: listings.map(\.id))
        await cloud.subscribeToJoinRequests()
        await cloud.subscribeToInvites()
        await cloud.subscribeToNewMembers()
        // A coach's key goes up; everyone re-seals Coaches-only fields if the coaches changed.
        await cloud.publishCoachKey()
        await MyProfile.restoreIfNeeded()
        await MyProfile.saveIfChanged()
        // After the coach keys load (publishCoachKey above), so the answers can be sealed to them.
        await cloud.sendWaitingApplication()
    }

    private func loadMyEvents() async {
        let me = cloud.myID
        myEvents = await cloud.events().filter { $0.message.senderID == me && !$0.isPast }
    }

    /// Shown as a section when you have no challenges and may start one.
    private var emptyState: some View {
        Section {
        VStack(spacing: 20) {
            Image(systemName: "figure.strengthtraining.functional")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("No challenges yet").font(AppFont.title)
            Text("Set a daily goal, like 100 push-ups a day for 14 days, then log your reps as you go.")
                .font(AppFont.body)
                .multilineTextAlignment(.center)
            Button { showingNew = true } label: {
                Text("Start a challenge").font(AppFont.bodyBold).padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        }
    }
}

struct ChallengeRow: View {
    let challenge: Challenge
    /// When anyone in the crew last saved progress; your own reps on this phone count too.
    var crewActivity: Date? = nil

    private var lastActive: Date? { [crewActivity, challenge.lastLogged].compactMap { $0 }.max() }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(challenge.title).font(AppFont.bodyBold)
                Spacer()
                // Green when today is done, and today's sets (DailyStats.swift).
                if challenge.isActive { DaySeal(challenge: challenge, day: .now) }
            }
            Text(status).font(AppFont.body)
            // His "yes add it there too", 2026-10-25: who started it and when, and when it closed (HomeTiers.swift).
            ChallengeByline(challenge: challenge)
            Text("\(challenge.dateRange) · \(Challenge.activityText(lastActive))")
                .font(AppFont.body).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var status: String {
        if challenge.isClosed {
            return "Closed · \(challenge.completedDays) of \(challenge.days) days completed"
        } else if let day = challenge.dayNumber() {
            return "Day \(day) of \(challenge.days)"
        } else if !challenge.hasStarted {
            return "Starts \(challenge.startDate.formatted(date: .abbreviated, time: .omitted))"
        } else {
            return "\(challenge.completedDays) of \(challenge.days) days completed"
        }
    }
}

#Preview {
    ContentView(openedURL: .constant(nil)).modelContainer(for: [Challenge.self, ExerciseGoal.self, RepEntry.self, CrewMember.self], inMemory: true)
}

/// Wraps a past challenge for `.sheet(item:)`.
private struct AgainItem: Identifiable {
    let info: Invite.ChallengeInfo
    var id: String { info.crewID + info.title }
}
