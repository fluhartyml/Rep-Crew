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
//  REM: his finding, 2026-10-24: "the old read messages sometimes appear as new and arnt able to be
//  deleted". Two causes in the code: an undated item (invite, join request) stayed new until answered,
//  and a reinstall (Debug ⇄ TestFlight on his 11) reset "last opened" to never, so everything read as new.
//  Now each item is read once the inbox has shown it (by ID), a fresh install starts with what's already
//  there read, and a swipe deletes an item from this phone's inbox (InboxState).
//

import SwiftUI
import UserNotifications

extension CrewSettings {
    static let inboxOpened = "inboxOpenedAt"
    static let inboxUnread = "inboxUnread"
    static let inboxSeen = "inboxSeenIDs"
    static let inboxDeleted = "inboxDeletedIDs"
}

/// Which inbox items this phone has shown and which it deleted, by item ID, newline-joined.
enum InboxState {
    /// Kept to the newest few hundred, so the lists don't grow forever.
    private static let limit = 500

    static var seen: [String] { ids(CrewSettings.inboxSeen) }
    static var deleted: Set<String> { Set(ids(CrewSettings.inboxDeleted)) }

    /// `opened`: when the inbox was last opened; 0 = never on this install, so nothing already there is news.
    static func isUnread(_ item: InboxItem, since opened: Double, seen: Set<String>) -> Bool {
        guard opened > 0, !seen.contains(item.id) else { return false }
        return (item.date ?? .distantFuture) > Date(timeIntervalSince1970: opened)
    }

    static func markSeen(_ items: [InboxItem]) { add(items.map(\.id), to: CrewSettings.inboxSeen) }
    static func delete(_ item: InboxItem) { add([item.id], to: CrewSettings.inboxDeleted) }

    private static func ids(_ key: String) -> [String] {
        (UserDefaults.standard.string(forKey: key) ?? "").split(separator: "\n").map(String.init)
    }

    private static func add(_ new: [String], to key: String) {
        var list = ids(key).filter { !new.contains($0) } + new
        if list.count > limit { list.removeFirst(list.count - limit) }
        UserDefaults.standard.set(list.joined(separator: "\n"), forKey: key)
    }
}

/// Unread = not yet shown in the inbox and arrived since it was last opened (InboxState).
/// His word 2026-10-24: "yes build it with the app icon badge" — red count, unread only (Apple's badge rule).
enum InboxBadge {
    static func unread(_ items: [InboxItem], since opened: Double) -> Int {
        let seen = Set(InboxState.seen)
        return items.filter { InboxState.isUnread($0, since: opened, seen: seen) }.count
    }
    static var current: Int { UserDefaults.standard.integer(forKey: CrewSettings.inboxUnread) }
    /// Home's count and the app icon's, kept the same.
    static func set(_ count: Int) async {
        UserDefaults.standard.set(count, forKey: CrewSettings.inboxUnread)
        try? await UNUserNotificationCenter.current().setBadgeCount(count)
    }
}

struct InboxItem: Identifiable {
    enum Destination {
        case challenge(String)   // crewID
        case invite(Invite)
        case newMembers
        case person(ProfileTarget)   // a direct message: opens the sender's profile, where Message answers
    }
    let id: String
    let date: Date?
    let icon: String
    let title: String
    let detail: String
    let destination: Destination
    /// Shown under the item without changing its place. A join request keeps date nil so it stays
    /// first until answered, but still shows when it was asked (his word 2026-10-24,
    /// "add the date to the asked to join item").
    var shownDate: Date? = nil
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
        for message in await messages(crewID: CrewMessage.direct(to: myID)) where message.senderID != myID && message.toID == myID {
            items.append(InboxItem(id: message.id, date: message.sentAt, icon: "envelope.fill",
                                   title: "✉️ \(message.senderName)", detail: message.text,
                                   destination: .person(ProfileTarget(id: message.senderID, name: message.senderName))))
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
                                       title: "\(request.name) asked to join", detail: "Open the challenge to answer.", destination: .challenge(crewID),
                                       shownDate: request.requestedAt))
            }
        }
        if GodMode.isOn {
            for entry in await applications() {
                items.append(InboxItem(id: "application.\(entry.id)", date: entry.sent, icon: "person.crop.circle.badge.plus",
                                       title: "\(entry.name) joined the crew", detail: "Read their application.", destination: .newMembers))
            }
        }
        // Undated items (invites, join requests) wait on you, so they go first.
        let deleted = InboxState.deleted
        return items.filter { !deleted.contains($0.id) }.sorted { ($0.date ?? .distantFuture) > ($1.date ?? .distantFuture) }
    }
}

struct InboxView: View {
    let challenges: [Challenge]
    let openInvite: (Invite) -> Void
    @AppStorage(CrewSettings.inboxOpened) private var openedAt = 0.0
    @State private var items: [InboxItem] = []
    @State private var loaded = false
    /// Unread when this visit began; their blue dots stay for the visit.
    @State private var unread: Set<String> = []
    @State private var profileOf: ProfileTarget?

    var body: some View {
        List {
            if loaded && items.isEmpty {
                Text("Nothing here yet. Replies, announcements, invites and join requests land here.")
                    .font(AppFont.body).foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                row(item)
                    .swipeActions {
                        Button(role: .destructive) { delete(item) } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        }
        .navigationTitle("Inbox")
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $profileOf) { ProfileView(target: $0, canMessage: true) }
    }

    private func delete(_ item: InboxItem) {
        InboxState.delete(item)
        items.removeAll { $0.id == item.id }
    }

    @ViewBuilder
    private func row(_ item: InboxItem) -> some View {
        let label = HStack(alignment: .top, spacing: 12) {
            // Blue dot = unread, like Mail.
            Circle().fill(.blue).frame(width: 10, height: 10).padding(.top, 8)
                .opacity(unread.contains(item.id) ? 1 : 0)
                .accessibilityLabel(unread.contains(item.id) ? "Unread" : "")
            Image(systemName: item.icon).font(AppFont.heading).foregroundStyle(.tint).frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(AppFont.bodyBold).foregroundStyle(.primary)
                Text(item.detail).font(AppFont.body).foregroundStyle(.primary).lineLimit(3)
                if let date = item.shownDate ?? item.date {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
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
        case .person(let sender):
            Button { profileOf = sender } label: { label }
        }
    }

    private func load() async {
        items = await CrewCloud.shared.inbox(crewIDs: challenges.map(\.crewID).filter { !$0.isEmpty },
                                             led: challenges.filter { $0.leaderID.isEmpty && !$0.crewID.isEmpty }.map(\.crewID))
        let seen = Set(InboxState.seen)
        unread.formUnion(items.filter { InboxState.isUnread($0, since: openedAt, seen: seen) }.map(\.id))
        InboxState.markSeen(items)
        openedAt = Date.now.timeIntervalSince1970
        await InboxBadge.set(0)
        loaded = true
    }
}
