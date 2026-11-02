//
//  RootTabs.swift
//  Rep Crew
//
//  Five tabs along the bottom: Home, Leaderboard, Feed, Comms, Profile.
//  REM: his word, 2026-11-02: "yes bring the tabs over to rep crew". R&D'd in Legend (Legend/Tabs/RootTabs.swift,
//  Hannah's Duolingo-inspired suggestion, settled to five 2026-10-30) and "never put them in smittys app". A tester
//  on the 11-02 call expected them ("they were tabs like a Duolingo").
//  REM: same five names as Legend. Each tab is a Rep Crew screen that already existed: Feed = the Lobby,
//  Comms = the Inbox, Profile = your own profile. Home keeps its rows to the same places, so nothing moved.
//  REM: each tab keeps its own NavigationStack, so a page opened in one tab is still there when you come back.

import SwiftUI
import SwiftData

enum CrewTab: Hashable { case home, leaderboard, feed, comms, profile }

struct RootTabs: View {
    @Binding var openedURL: URL?
    @State private var tab: CrewTab = .home

    var body: some View {
        // REM: .tabItem, not Legend's Tab(...): Rep Crew still runs on iOS 17, and Tab is iOS 18 only. Same look.
        TabView(selection: $tab) {
            ContentView(openedURL: $openedURL)
                .tabItem { Label("Home", systemImage: "house.fill") }.tag(CrewTab.home)
            TabStack { LeaderboardsView() }
                .tabItem { Label("Leaderboard", systemImage: "chart.bar.fill") }.tag(CrewTab.leaderboard)
            TabStack { LobbyView() }
                .tabItem { Label("Feed", systemImage: "bubble.left.and.bubble.right.fill") }.tag(CrewTab.feed)
            CommsTab()
                .tabItem { Label("Comms", systemImage: "envelope.fill") }.tag(CrewTab.comms)
            MyProfileTab()
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }.tag(CrewTab.profile)
        }
        // REM: the home and leaderboard glyphs on other screens (CrewNav) switch tabs here.
        // Home sets its own CrewNav inside ContentView, which still pushes Leaderboards on Home's stack.
        .environment(\.crewNav, CrewNav(goHome: { tab = .home }, openBoards: { tab = .leaderboard }))
        // An invite or widget link always lands on Home, where it is handled.
        .onChange(of: openedURL) { _, url in if url != nil { tab = .home } }
    }
}

/// A tab's own NavigationStack, able to open every page the tab's screen links to.
private struct TabStack<Root: View>: View {
    @ViewBuilder var root: Root
    @Query(sort: \Challenge.startDate, order: .reverse) private var challenges: [Challenge]
    @State private var joining: Invite?

    var body: some View {
        NavigationStack {
            root
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
                    case .leagues: LeaguesView()
                    // REM: only Home links to its Challenges page, so no other tab ever opens it.
                    case .challenges: LibraryView()
                    }
                }
        }
        .sheet(item: $joining) { JoinView(invite: $0) }
    }
}

/// Comms = the Inbox (Legend's Comms is Inbox + Send Mail).
private struct CommsTab: View {
    @Query(sort: \Challenge.startDate, order: .reverse) private var challenges: [Challenge]
    @State private var joining: Invite?

    var body: some View {
        TabStack {
            InboxView(challenges: challenges) { joining = $0 }
        }
        .sheet(item: $joining) { JoinView(invite: $0) }
    }
}

/// Profile = your own profile page, the one others see when they tap you.
private struct MyProfileTab: View {
    private var cloud = CrewCloud.shared

    var body: some View {
        if let id = cloud.myID {
            ProfileView(target: ProfileTarget(id: id, name: "You"), showsDone: false)
        } else {
            ProgressView("Loading your profile…").font(AppFont.body)
        }
    }
}
