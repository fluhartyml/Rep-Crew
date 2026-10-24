//
//  Inbox.swift
//  Rep Crew
//
//  One list of what would have notified you. His words, 2026-10-24: "how about the 'inbox' is just a
//  collection of notifications? maybe?" · "yes build the inbox".
//
//  REM: built from the same iCloud records the notifications come from, not from the phone's delivered
//  notifications — iOS forgets a notification once it's swiped away, and the inbox shouldn't.
//  Shows: replies to you, announcements in your challenges and to all crews, challenge invites, join
//  requests on challenges you lead, and (coaches) new member applications. Tapping opens where it came
//  from. "New" = arrived since you last opened the inbox (kept on this phone).
//

import SwiftUI

extension CrewSettings {
    static let inboxOpened = "inboxOpenedAt"
}

struct InboxItem: Identifiable {
    enum Destination {
        case challenge(String)   // crewID
        case invite(Invite)
        case newMembers
    }
    let id: String
    let date: Date?
    let icon: String
    let title: String
    let detail: String
    let destination: Destination
}

extension CrewCloud {
    /// Everything for the inbox, newest first. `crewIDs`: challenges on this phone; `led`: the ones you lead.
    func inbox(crewIDs: [String], led: [String]) async -> [InboxItem] {
        await connect()
        guard let myID else { return [] }
        var items: [InboxItem] = []
        for crewID in Set(crewIDs) {
            for message in await messages(crewID: crewID) where message.senderID != myID {
                switch message.kind {
                case .reply where message.toID == myID:
                    items.append(InboxItem(id: message.id, date: message.sentAt, icon: "arrowshape.turn.up.left.fill",
                                           title: "\(message.senderName) replied", detail: message.text, destination: .challenge(crewID)))
                case .announcement, .announcementOneWay:
                    items.append(InboxItem(id: message.id, date: message.sentAt, icon: "megaphone.fill",
                                           title: "📣 \(message.senderName)", detail: message.text, destination: .challenge(crewID)))
                default:
                    break
                }
            }
        }
        for message in await allCrewsMessages() where message.senderID != myID {
            items.append(InboxItem(id: message.id, date: message.sentAt, icon: "megaphone.fill",
                                   title: "📣 \(message.senderName) to all crews", detail: message.text, destination: .challenge(CrewMessage.allCrews)))
        }
        for invite in pending {
            items.append(InboxItem(id: "invite.\(invite.id)", date: nil, icon: "envelope.badge.fill",
                                   title: "\(invite.from) invited you", detail: invite.challenge?.title ?? "A challenge", destination: .invite(invite)))
        }
        for crewID in Set(led) {
            for request in await joinRequests(crewID: crewID) {
                items.append(InboxItem(id: request.id, date: nil, icon: "hand.wave.fill",
                                       title: "\(request.name) asked to join", detail: "Open the challenge to answer.", destination: .challenge(crewID)))
            }
        }
        if GodMode.isOn {
            for entry in await applications() {
                items.append(InboxItem(id: "application.\(entry.id)", date: entry.sent, icon: "person.crop.circle.badge.plus",
                                       title: "\(entry.name) joined the crew", detail: "Read their application.", destination: .newMembers))
            }
        }
        // Undated items (invites, join requests) wait on you, so they go first.
        return items.sorted { ($0.date ?? .distantFuture) > ($1.date ?? .distantFuture) }
    }
}

struct InboxView: View {
    let challenges: [Challenge]
    let openInvite: (Invite) -> Void
    @AppStorage(CrewSettings.inboxOpened) private var openedAt = 0.0
    @State private var items: [InboxItem] = []
    @State private var loaded = false
    @State private var lastVisit = Date.distantPast

    var body: some View {
        List {
            if loaded && items.isEmpty {
                Text("Nothing here yet. Replies, announcements, invites and join requests land here.")
                    .font(AppFont.body).foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                row(item)
            }
        }
        .navigationTitle("Inbox")
        .refreshable { await load() }
        .task {
            lastVisit = Date(timeIntervalSince1970: openedAt)
            await load()
            openedAt = Date.now.timeIntervalSince1970
        }
    }

    @ViewBuilder
    private func row(_ item: InboxItem) -> some View {
        let label = HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.icon).font(AppFont.heading).foregroundStyle(.tint).frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(AppFont.bodyBold).foregroundStyle(.primary)
                Text(item.detail).font(AppFont.body).foregroundStyle(.primary).lineLimit(3)
                if let date = item.date {
                    Text(date.formatted(date: .abbreviated, time: .shortened)
                         + (date > lastVisit ? " · New" : ""))
                        .font(AppFont.body).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        switch item.destination {
        case .challenge(let crewID):
            if let challenge = challenges.first(where: { $0.crewID == crewID }) {
                NavigationLink(value: challenge) { label }
            } else {
                label   // all-crews announcements, or a challenge no longer on this phone
            }
        case .invite(let invite):
            Button { openInvite(invite) } label: { label }
        case .newMembers:
            NavigationLink(value: CrewScreen.newMembers) { label }
        }
    }

    private func load() async {
        items = await CrewCloud.shared.inbox(crewIDs: challenges.map(\.crewID).filter { !$0.isEmpty },
                                             led: challenges.filter { $0.leaderID.isEmpty && !$0.crewID.isEmpty }.map(\.crewID))
        loaded = true
    }
}
