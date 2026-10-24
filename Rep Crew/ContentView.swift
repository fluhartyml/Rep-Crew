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
    @State private var listings: [CrewListing] = []
    @State private var past: [CrewListing] = []
    /// A past challenge to run again (NewChallengeView(again:)).
    @State private var again: Invite.ChallengeInfo?
    private var cloud = CrewCloud.shared

    @State private var showingNew = false
    @State private var showingAbout = false
    @State private var showingSettings = false
    @State private var joining: Invite?
    @State private var path = NavigationPath()

    private var active: [Challenge] { challenges.filter(\.isActive) }
    /// Changes whenever today's numbers do, so the Watch gets a fresh copy.
    private var watchSignature: String { challenges.map { "\($0.title).\($0.repsToday)" }.joined(separator: "|") }
    private var upcoming: [Challenge] { challenges.filter { !$0.hasStarted } }
    private var finished: [Challenge] { challenges.filter(\.isFinished) }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if challenges.isEmpty && cloud.pending.isEmpty && others.isEmpty {
                    emptyState
                } else {
                    List {
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
                        invitations
                        section("Your challenges", active + upcoming.reversed())
                        crewChallenges
                        section("Finished", finished)
                        pastChallenges
                    }
                    .refreshable { await syncCrew() }
                }
            }
            .task { await syncCrew() }
            // Matched Health workouts check off days on Home too; asks for nothing until something is paired.
            .task(id: scenePhase) {
                if scenePhase == .active, challenges.contains(where: \.countsHealth) { await HealthLibrary.shared.refresh() }
            }
            .task(id: watchSignature) { WatchBridge.shared.sendGoals(challenges) }
            // A coach tapped a "joined the crew" notification (CrewNotifications).
            .onChange(of: cloud.openNewMembers, initial: true) { _, open in
                guard open else { return }
                cloud.openNewMembers = false
                path.append(CrewScreen.newMembers)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await syncCrew() } }
            }
            .navigationTitle(CrewCloud.displayName(crewName))   // the head coach's name for the crew (CrewName.swift)
            .navigationDestination(for: Challenge.self) { ChallengeDetailView(challenge: $0) }
            .navigationDestination(for: CrewListing.self) { CrewChallengeView(listing: $0) }
            .navigationDestination(for: CrewScreen.self) { screen in
                switch screen {
                case .leaderboards: LeaderboardsView()
                case .directory: CrewDirectoryView()
                case .newMembers: ApplicationsView()
                case .inbox: InboxView(challenges: challenges) { joining = $0 }
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
                joining = Invite(url: url)
                openedURL = nil
            }
        }
        .environment(\.crewNav, CrewNav(goHome: { path = NavigationPath() },
                                        openBoards: { path.append(CrewScreen.leaderboards) }))
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [Challenge]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { challenge in
                    NavigationLink(value: challenge) { ChallengeRow(challenge: challenge) }
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
            } header: {
                Text(title).font(AppFont.bodyBold).textCase(nil)
            }
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
        return listings.filter { !mine.contains($0.id) }.sorted { $0.info.startDay > $1.info.startDay }
    }

    /// Everyone's ended public challenges, plus Start Again on your own finished ones (in `section`).
    @ViewBuilder
    private var pastChallenges: some View {
        if !past.isEmpty && cloud.can(.start) {
            Section {
                ForEach(past) { listing in
                    Button { again = listing.info } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(listing.info.title).font(AppFont.bodyBold).foregroundStyle(.primary)
                            Text("\(listing.leaderName) · \(listing.info.days) days · Start Again").font(AppFont.body).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Past challenges").font(AppFont.bodyBold).textCase(nil)
            }
        }
    }

    @ViewBuilder
    private var crewChallenges: some View {
        if !others.isEmpty {
            Section {
                ForEach(others) { listing in
                    NavigationLink(value: listing) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(listing.info.title).font(AppFont.bodyBold)
                            Text("\(listing.leaderName) · \(listing.status)").font(AppFont.body)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Other challenges").font(AppFont.bodyBold).textCase(nil)
            }
        }
    }

    /// Pulls in who has joined your challenges, and challenges you've been checked off for.
    private func syncCrew() async {
        // Challenges this phone lost (app deleted before they reached your iCloud) come back from the crew's copy.
        await CrewRestore.run(context: context, declined: Set(declined.split(separator: "\n").map(String.init)))
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
        listings = await cloud.crewChallenges()
        past = await cloud.pastChallenges()
        let inbox = await cloud.inbox(crewIDs: challenges.map(\.crewID).filter { !$0.isEmpty },
                                      led: challenges.filter { $0.leaderID.isEmpty && !$0.crewID.isEmpty }.map(\.crewID))
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

    private var emptyState: some View {
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
        .padding(32)
    }
}

struct ChallengeRow: View {
    let challenge: Challenge

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(challenge.title).font(AppFont.bodyBold)
                Spacer()
                if challenge.isActive && challenge.isComplete(on: .now) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(AppFont.heading)
                        .foregroundStyle(.green)
                        .accessibilityLabel("Done for today")
                }
            }
            Text(status).font(AppFont.body)
        }
        .padding(.vertical, 4)
    }

    private var status: String {
        if let day = challenge.dayNumber() {
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
