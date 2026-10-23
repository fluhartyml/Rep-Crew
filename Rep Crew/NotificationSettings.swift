//
//  NotificationSettings.swift
//  Rep Crew
//
//  Settings → Notifications. His word, 2026-10-23: "the team leader toggles on and off only ones
//  they are a member of, same for crew members"; coaches can also get notices for every challenge.
//
//  Every switch is one CloudKit subscription: on saves it, off deletes it, and the launch-time
//  setup (ContentView.syncCrew) only re-creates the ones still on.
//    Your challenges  crew-<crewID>   messages, announcements and "finished today" to everyone. On by default.
//                     + oneway-<crewID> for one-way announcements (CrewMessages.swift); same switch.
//    Replies to you   to-me           On by default.
//    Challenge invites invites        On by default.
//    Join requests    join-requests   Leaders only. On by default.
//    Coach only       coach-<crewID>  kind == "finished" on a public challenge you're not in. Off by default.
//

import SwiftUI
import SwiftData

enum NotificationSettings {
    /// Subscription IDs switched off, newline-separated. Everything not in it is on.
    static let offKey = "notificationsOff"
    /// Crew IDs a coach switched on for "finished today", newline-separated. Everything not in it is off.
    static let coachKey = "coachNotificationCrewIDs"

    static let replies = "to-me"
    static let invites = "invites"
    static let joinRequests = "join-requests"

    static func isOn(_ subscriptionID: String) -> Bool { !ids(offKey).contains(subscriptionID) }
    static var coachCrewIDs: Set<String> { ids(coachKey) }

    static func ids(_ key: String) -> Set<String> {
        Set((UserDefaults.standard.string(forKey: key) ?? "").split(separator: "\n").map(String.init))
    }

    static func string(_ ids: Set<String>) -> String { ids.sorted().joined(separator: "\n") }
}

struct NotificationSettingsView: View {
    @Query(sort: \Challenge.startDate, order: .reverse) private var challenges: [Challenge]
    @AppStorage(NotificationSettings.offKey) private var off = ""
    @AppStorage(NotificationSettings.coachKey) private var coachOn = ""
    @State private var listings: [CrewListing] = []
    @State private var isCoach = false
    private var cloud = CrewCloud.shared

    /// Challenges on this phone that can still send something.
    private var mine: [Challenge] { challenges.filter { !$0.crewID.isEmpty && !$0.isFinished } }
    private var leadsOne: Bool { challenges.contains { $0.leaderID.isEmpty && !$0.crewID.isEmpty } }
    /// Public challenges you're not in.
    private var others: [CrewListing] {
        let ids = Set(challenges.map(\.crewID))
        return listings.filter { !ids.contains($0.id) }.sorted { $0.info.title < $1.info.title }
    }

    var body: some View {
        Form {
            Section {
                if mine.isEmpty {
                    Text("No challenges yet. Each one you start or join gets a switch here.").font(AppFont.body)
                }
                ForEach(mine) { challenge in
                    Toggle(isOn: offBinding("crew-\(challenge.crewID)")) {
                        Text(challenge.title).font(AppFont.body)
                    }
                }
            } header: {
                header("Your challenges")
            } footer: {
                Text("Messages, announcements, and who finished today.").font(AppFont.body)
            }

            Section {
                Toggle(isOn: offBinding(NotificationSettings.replies)) { Text("Replies to you").font(AppFont.body) }
                Toggle(isOn: offBinding(NotificationSettings.invites)) { Text("Challenge invites").font(AppFont.body) }
                if leadsOne {
                    Toggle(isOn: offBinding(NotificationSettings.joinRequests)) { Text("Join requests").font(AppFont.body) }
                }
            } header: {
                header("General")
            }

            if isCoach {
                Section {
                    if others.isEmpty {
                        Text("No other public challenges right now.").font(AppFont.body)
                    }
                    ForEach(others) { listing in
                        Toggle(isOn: coachBinding(listing.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(listing.info.title).font(AppFont.body)
                                Text(listing.leaderName).font(AppFont.body).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    header("Coach only")
                } footer: {
                    Text("Who finished today on challenges you're not in.").font(AppFont.body)
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await cloud.connect()
            isCoach = GodMode.isOn
            listings = await cloud.crewChallenges()
        }
    }

    /// On unless its subscription ID is in the off list.
    private func offBinding(_ id: String) -> Binding<Bool> {
        Binding {
            !off.split(separator: "\n").contains(Substring(id))
        } set: { isOn in
            var ids = NotificationSettings.ids(NotificationSettings.offKey)
            if isOn { ids.remove(id) } else { ids.insert(id) }
            off = NotificationSettings.string(ids)
            apply(id)
        }
    }

    /// Off unless its crew ID is in the coach list.
    private func coachBinding(_ crewID: String) -> Binding<Bool> {
        Binding {
            coachOn.split(separator: "\n").contains(Substring(crewID))
        } set: { isOn in
            var ids = NotificationSettings.ids(NotificationSettings.coachKey)
            if isOn { ids.insert(crewID) } else { ids.remove(crewID) }
            coachOn = NotificationSettings.string(ids)
            apply("coach-\(crewID)")
        }
    }

    /// Saves or deletes the one subscription the switch stands for.
    private func apply(_ id: String) {
        let crewIDs = challenges.map(\.crewID).filter { !$0.isEmpty }
        let listed = listings.map(\.id)
        Task {
            switch id {
            case NotificationSettings.invites: await cloud.subscribeToInvites()
            case NotificationSettings.joinRequests: await cloud.subscribeToJoinRequests()
            default: await cloud.subscribe(crewIDs: crewIDs, listedCrewIDs: listed)
            }
        }
    }

    private func header(_ text: String) -> some View {
        Text(text).font(AppFont.bodyBold).textCase(nil)
    }
}
