//
//  ContentView.swift
//  Rep Crew
//
//  The list of challenges: running now, starting later, and finished.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Challenge.startDate, order: .reverse) private var challenges: [Challenge]
    @Query private var crew: [CrewMember]
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(CrewSettings.declined) private var declined = ""
    @AppStorage(CrewSettings.name) private var name = ""
    @AppStorage(CrewSettings.testFlight) private var testFlight = ""
    @AppStorage(CrewSettings.crewNumber) private var crewNumber = 0
    @State private var listings: [CrewListing] = []
    private var cloud = CrewCloud.shared

    @State private var showingNew = false
    @State private var showingAbout = false
    @State private var showingSettings = false
    @State private var joining: Invite?

    private var active: [Challenge] { challenges.filter(\.isActive) }
    private var upcoming: [Challenge] { challenges.filter { !$0.hasStarted } }
    private var finished: [Challenge] { challenges.filter(\.isFinished) }

    var body: some View {
        NavigationStack {
            Group {
                if challenges.isEmpty && cloud.pending.isEmpty && others.isEmpty {
                    emptyState
                } else {
                    List {
                        invitations
                        section("Your challenges", active + upcoming.reversed())
                        crewChallenges
                        section("Finished", finished)
                    }
                    .refreshable { await syncCrew() }
                }
            }
            .task { await syncCrew() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await syncCrew() } }
            }
            .navigationTitle("Rep Crew")
            .navigationDestination(for: Challenge.self) { ChallengeDetailView(challenge: $0) }
            .navigationDestination(for: CrewListing.self) { CrewChallengeView(listing: $0) }
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
                    Button { showingNew = true } label: {
                        Image(systemName: "plus.circle.fill").font(AppFont.heading)
                    }
                    .accessibilityLabel("New challenge")
                }
            }
            .sheet(isPresented: $showingNew) { NewChallengeView() }
            .sheet(isPresented: $showingAbout) { AboutView() }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(item: $joining) { JoinView(invite: $0) }
            .onOpenURL { url in joining = Invite(url: url) }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [Challenge]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { challenge in
                    NavigationLink(value: challenge) { ChallengeRow(challenge: challenge) }
                }
                .onDelete { offsets in
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
        await cloud.subscribe(crewIDs: challenges.map(\.crewID).filter { !$0.isEmpty })
        listings = await cloud.crewChallenges()
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
    ContentView().modelContainer(for: [Challenge.self, ExerciseGoal.self, RepEntry.self, CrewMember.self], inMemory: true)
}
