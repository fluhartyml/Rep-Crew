//
//  CrewMessages.swift
//  Rep Crew
//
//  Short motivational messages to the crew — not a chat. Michael's design, 2026-10-22:
//  the leader sends announcements, anyone can message the whole crew, and a notification
//  can be answered right from the lock screen with Reply (just the sender) or Reply All.
//
//  Each message is a CrewMessage record in the crew's iCloud space. Every phone keeps a
//  CloudKit subscription per crew (messages to everyone) and one for messages addressed
//  to it; iCloud turns a new record into the notification. No server.
//

import CloudKit
import SwiftUI
import UserNotifications

struct CrewMessage: Identifiable {
    /// announcementOneWay: an announcement sent with Allow replies off. Shown exactly like one, minus
    /// Reply / Reply All. Builds before it read the unknown kind as .message.
    enum Kind: String { case announcement, announcementOneWay, message, reply, welcome, finished }

    let id: String
    let crewID: String
    let text: String
    let senderID: String
    let senderName: String
    let kind: Kind
    /// "all", or the one person a Reply went to.
    let toID: String
    let sentAt: Date

    static let everyone = "all"
}

// MARK: - iCloud

extension CrewCloud {
    func send(_ text: String, crewID: String, kind: CrewMessage.Kind, to toID: String = CrewMessage.everyone, senderName: String) async -> Bool {
        await connect()
        guard let myID else { return false }
        let record = CKRecord(recordType: "CrewMessage")
        record["crewID"] = crewID
        record["text"] = text
        record["senderID"] = myID
        record["senderName"] = senderName
        record["kind"] = kind.rawValue
        record["toID"] = toID
        record["sentAt"] = Date.now
        // The notification's title line, worked out once here so every phone shows the same thing.
        switch kind {
        case .announcement, .announcementOneWay: record["title"] = "📣 \(senderName)"
        case .message: record["title"] = senderName
        case .reply: record["title"] = "\(senderName) replied"
        case .welcome: record["title"] = "✅ \(senderName)"
        case .finished: record["title"] = "🏁 \(senderName)"
        }
        do {
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            return true
        } catch {
            status = "Couldn't send your message: \(error.localizedDescription)"
            return false
        }
    }

    /// The crew's recent messages that are yours to see: everything sent to all, plus replies to or from you.
    func messages(crewID: String) async -> [CrewMessage] {
        await connect()
        guard let myID else { return [] }
        let query = CKQuery(recordType: "CrewMessage", predicate: NSPredicate(format: "crewID == %@", crewID))
        do {
            let (results, _) = try await db.records(matching: query, resultsLimit: 100)
            let leader = (try? await db.record(for: CKRecord.ID(recordName: crewID)))?["leaderID"] as? String ?? myID
            let hide = await hidden(crewID: crewID, leaderID: leader)
            let removed = await removedMessages(crewID: crewID, leaderID: leader)
            return results.compactMap { try? $0.1.get() }.compactMap(Self.message(from:))
                .filter { $0.toID == CrewMessage.everyone || $0.toID == myID || $0.senderID == myID }
                .filter { !hide.contains($0.senderID) && !removed.contains($0.id) }
                .sorted { $0.sentAt > $1.sentAt }
        } catch let error as CKError where error.code == .unknownItem {
            return []   // No one has sent a message yet, so the record type doesn't exist yet.
        } catch {
            status = "Couldn't load messages: \(error.localizedDescription)"
            return []
        }
    }

    /// His word, 2026-10-22: "the crew leader needs kick ban and moderator permissions to remove
    /// announcements or photos". Yours: deleted. Someone else's, as leader: a MessageRemoval
    /// (name = removed.<message ID>) hides it on every phone — honored only when the leader left it.
    func removeMessage(_ message: CrewMessage) async -> Bool {
        await connect()
        guard let myID else { return false }
        do {
            if message.senderID == myID {
                _ = try await db.modifyRecords(saving: [], deleting: [CKRecord.ID(recordName: message.id)])
            } else {
                let record = CKRecord(recordType: "MessageRemoval", recordID: CKRecord.ID(recordName: "removed.\(message.id)"))
                record["crewID"] = message.crewID
                record["messageID"] = message.id
                record["removedBy"] = myID
                _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            }
            return true
        } catch {
            status = "Couldn't remove the message: \(error.localizedDescription)"
            return false
        }
    }

    private func removedMessages(crewID: String, leaderID: String) async -> Set<String> {
        let query = CKQuery(recordType: "MessageRemoval", predicate: NSPredicate(format: "crewID == %@", crewID))
        guard let (results, _) = try? await db.records(matching: query) else { return [] }
        return Set(results.compactMap { try? $0.1.get() }
            .filter { isModerator(writer(of: $0), leaderID: leaderID) }
            .compactMap { $0["messageID"] as? String })
    }

    /// One subscription per crew for messages to everyone, and one for replies addressed to you.
    /// Saving with the same ID replaces the old one, so this is safe to run on every launch.
    /// Settings → Notifications decides which are kept (NotificationSettings.swift): switched-off ones,
    /// crews no longer on this phone, and coach ones no longer wanted are deleted here.
    /// `listedCrewIDs`: the public challenges listed right now, so a coach's switch for one that ended goes too
    /// (an empty list is read as "iCloud didn't answer" and keeps them).
    func subscribe(crewIDs: [String], listedCrewIDs: [String]) async {
        await connect()
        guard let myID else { return }
        var subscriptions = crewIDs.filter { NotificationSettings.isOn("crew-\($0)") }.flatMap(crewSubscriptions)
        if NotificationSettings.isOn(NotificationSettings.replies) {
            subscriptions.append(subscription(id: NotificationSettings.replies, NSPredicate(format: "toID == %@", myID)))
        }
        // Coaches: "finished today" on public challenges they're not in, only where they switched it on.
        if GodMode.isOn {
            let listed = Set(listedCrewIDs)
            for crewID in NotificationSettings.coachCrewIDs where (listed.isEmpty || listed.contains(crewID)) && !crewIDs.contains(crewID) {
                subscriptions.append(subscription(id: "coach-\(crewID)", NSPredicate(format: "crewID == %@ AND kind == %@ AND toID == %@",
                                                                                     crewID, CrewMessage.Kind.finished.rawValue, CrewMessage.everyone)))
            }
        }
        // Deleted in their own call first, so a missing CrewMessage type on the save can't keep a stale one.
        let keep = Set(subscriptions.map(\.subscriptionID))
        if let existing = try? await db.allSubscriptions() {
            let stale = existing.map(\.subscriptionID).filter { id in
                !keep.contains(id) && (id == NotificationSettings.replies || id.hasPrefix("crew-") || id.hasPrefix("oneway-")
                                       || id.hasPrefix("coach-"))
            }
            if !stale.isEmpty { _ = try? await db.modifySubscriptions(saving: [], deleting: stale) }
        }
        guard !subscriptions.isEmpty else { return }
        do {
            _ = try await db.modifySubscriptions(saving: subscriptions, deleting: [])
        } catch let error as CKError where error.code == .unknownItem || error.code == .partialFailure {
            // Before the first message is ever sent there is no CrewMessage type to subscribe to.
            // The next launch after someone sends one picks it up.
        } catch {
            status = "Couldn't turn on crew notifications: \(error.localizedDescription)"
        }
    }

    /// Just this crew's, after you send in it: saves without touching any other subscription.
    func subscribe(crewID: String) async {
        await connect()
        guard myID != nil, NotificationSettings.isOn("crew-\(crewID)") else { return }
        _ = try? await db.modifySubscriptions(saving: crewSubscriptions(crewID), deleting: [])
    }

    /// A subscription has one fixed category, so one-way announcements get their own (no reply actions)
    /// and the regular one leaves them out. Both sit under the challenge's one switch.
    private func crewSubscriptions(_ crewID: String) -> [CKQuerySubscription] {
        let oneWay = CrewMessage.Kind.announcementOneWay.rawValue
        return [subscription(id: "crew-\(crewID)", NSPredicate(format: "crewID == %@ AND toID == %@ AND kind != %@",
                                                               crewID, CrewMessage.everyone, oneWay)),
                subscription(id: "oneway-\(crewID)", NSPredicate(format: "crewID == %@ AND toID == %@ AND kind == %@",
                                                                 crewID, CrewMessage.everyone, oneWay),
                             category: CrewNotifications.oneWayCategory)]
    }

    private func subscription(id: String, _ predicate: NSPredicate, category: String = CrewNotifications.category) -> CKQuerySubscription {
        let subscription = CKQuerySubscription(recordType: "CrewMessage", predicate: predicate,
                                               subscriptionID: id, options: [.firesOnRecordCreation])
        let info = CKSubscription.NotificationInfo()
        // A key with no translation is used as the format itself, so the record's own fields fill it in.
        info.titleLocalizationKey = "%1$@"
        info.titleLocalizationArgs = ["title"]
        info.alertLocalizationKey = "%1$@"
        info.alertLocalizationArgs = ["text"]
        info.soundName = "default"
        info.category = category
        info.desiredKeys = ["crewID", "senderID", "senderName"]
        subscription.notificationInfo = info
        return subscription
    }

    private static func message(from record: CKRecord) -> CrewMessage? {
        guard let crewID = record["crewID"] as? String, let text = record["text"] as? String,
              let senderID = record["senderID"] as? String else { return nil }
        return CrewMessage(id: record.recordID.recordName, crewID: crewID, text: text, senderID: senderID,
                           senderName: record["senderName"] as? String ?? "Crew member",
                           kind: CrewMessage.Kind(rawValue: record["kind"] as? String ?? "") ?? .message,
                           toID: record["toID"] as? String ?? CrewMessage.everyone,
                           sentAt: record["sentAt"] as? Date ?? record.creationDate ?? .now)
    }
}

// MARK: - Notifications

/// Reply and Reply All, typed right on the notification.
final class CrewNotifications: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let category = "CREW_MESSAGE"
    /// One-way announcements: no Reply or Reply All on the lock screen.
    static let oneWayCategory = "CREW_ANNOUNCEMENT"
    private static let reply = "REPLY"
    private static let replyAll = "REPLY_ALL"

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let reply = UNTextInputNotificationAction(identifier: Self.reply, title: "Reply", options: [],
                                                  textInputButtonTitle: "Send", textInputPlaceholder: "Reply to the sender")
        let replyAll = UNTextInputNotificationAction(identifier: Self.replyAll, title: "Reply All", options: [],
                                                     textInputButtonTitle: "Send", textInputPlaceholder: "Reply to the whole crew")
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [reply, replyAll],
                                                                 intentIdentifiers: []),
                                          UNNotificationCategory(identifier: Self.oneWayCategory, actions: [], intentIdentifiers: [])])
        application.registerForRemoteNotifications()
        return true
    }

    /// Asked once, the first time the app opens after this build.
    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    // Show crew messages even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let typed = response as? UNTextInputNotificationResponse,
              case let text = typed.userText.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              let note = CKQueryNotification(fromRemoteNotificationDictionary: response.notification.request.content.userInfo),
              let crewID = note.recordFields?["crewID"] as? String,
              let senderID = note.recordFields?["senderID"] as? String else { return }
        let toID = response.actionIdentifier == Self.reply ? senderID : CrewMessage.everyone
        let name = UserDefaults.standard.string(forKey: CrewSettings.name)?.trimmingCharacters(in: .whitespaces) ?? ""
        _ = await CrewCloud.shared.send(text, crewID: crewID, kind: .reply, to: toID,
                                        senderName: name.isEmpty ? "A crew member" : name)
    }
}

// MARK: - On the challenge screen

struct CrewMessagesSection: View {
    let challenge: Challenge
    @AppStorage(CrewSettings.name) private var name = ""
    @State private var messages: [CrewMessage] = []
    @State private var composing = false
    @State private var removing: CrewMessage?
    @State private var banning: CrewMessage?
    @State private var replying: ReplyTarget?
    @State private var profileOf: ProfileTarget?
    @State private var failed = false

    private var isLeader: Bool { challenge.leaderID.isEmpty || challenge.leaderID == CrewCloud.shared.myID }
    /// Leader, or god: can remove anyone's message and ban from it.
    private var canModerate: Bool { isLeader || GodMode.isOn }

    var body: some View {
        list
        .confirmationDialog("Remove this message for the whole crew?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { message in
            Button("Remove Message", role: .destructive) {
                Task {
                    failed = !(await CrewCloud.shared.removeMessage(message))
                    await load()
                }
            }
        }
        .confirmationDialog("Remove this message and ban \(banning?.senderName ?? "them") from the challenge?",
                            isPresented: Binding(get: { banning != nil }, set: { if !$0 { banning = nil } }),
                            titleVisibility: .visible, presenting: banning) { message in
            Button("Remove and Ban", role: .destructive) {
                Task {
                    let banned = await CrewCloud.shared.ban(crewID: challenge.crewID, memberID: message.senderID, name: message.senderName)
                    let removed = await CrewCloud.shared.removeMessage(message)
                    failed = !(banned && removed)
                    await load()
                }
            }
        } message: { _ in
            Text("Their name shows as Disqualified on the board, their photos and messages are hidden, and they can't rejoin.")
        }
        .sheet(isPresented: $composing) {
            ComposeView(title: isLeader ? "Announcement" : "Message the Crew", offersOneWay: isLeader) { text, allowReplies in
                await send(text, kind: !isLeader ? .message : allowReplies ? .announcement : .announcementOneWay)
            }
        }
        // His word, 2026-10-23: "yes add reply and reply all in the app". Same send as the lock-screen actions.
        .sheet(item: $replying) { target in
            ComposeView(title: target.toAll ? "Reply All" : "Reply to \(target.message.senderName)",
                        footer: target.toAll ? "It pops up on every crew member's phone." : "Only \(target.message.senderName) gets it.") { text, _ in
                await send(text, kind: .reply, to: target.toAll ? CrewMessage.everyone : target.message.senderID)
            }
        }
    }

    /// Split from body so the type checker can manage it.
    private var list: some View {
        Section {
            Button { composing = true } label: {
                Label(isLeader ? "Send an Announcement" : "Message the Crew",
                      systemImage: isLeader ? "megaphone.fill" : "text.bubble.fill")
                    .font(AppFont.bodyBold)
            }
            ForEach(messages.prefix(10)) { message in
                VStack(alignment: .leading, spacing: 4) {
                    Text(heading(message)).font(AppFont.bodyBold)
                    Text(message.text).font(AppFont.body)
                    Text(message.sentAt.formatted(date: .abbreviated, time: .shortened))
                        .font(AppFont.body).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .contextMenu { menu(for: message) }
            }
            if failed {
                Text("That didn't go through. Check iCloud in Settings and try again.").font(AppFont.body)
            }
        } header: {
            Text("Crew messages").font(AppFont.bodyBold).textCase(nil)
        }
        .task(id: challenge.crewID) { await load() }
        .sheet(item: $profileOf, onDismiss: { Task { await load() } }) { ProfileView(target: $0) }
    }

    private func send(_ text: String, kind: CrewMessage.Kind, to toID: String = CrewMessage.everyone) async -> Bool {
        let me = name.trimmingCharacters(in: .whitespaces)
        let sent = await CrewCloud.shared.send(text, crewID: challenge.crewID, kind: kind, to: toID,
                                               senderName: me.isEmpty ? "A crew member" : me)
        if sent {
            await CrewCloud.shared.subscribe(crewID: challenge.crewID)
            await load()
        }
        return sent
    }

    @ViewBuilder
    private func menu(for message: CrewMessage) -> some View {
        let mine = message.senderID == CrewCloud.shared.myID
        // One-way announcements take no replies, here or on the lock screen.
        if !mine && message.kind != .announcementOneWay {
            Button { replying = ReplyTarget(message: message, toAll: false) } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
            Button { replying = ReplyTarget(message: message, toAll: true) } label: {
                Label("Reply All", systemImage: "arrowshape.turn.up.left.2")
            }
        }
        // REM: the second way to a profile, after the leaderboard: whoever sent this.
        if !mine {
            Button { profileOf = ProfileTarget(id: message.senderID, name: message.senderName) } label: {
                Label("View Profile", systemImage: "person.crop.circle")
            }
        }
        if mine || canModerate {
            Button(role: .destructive) { removing = message } label: {
                Label("Remove Message", systemImage: "trash")
            }
        }
        if !mine && canModerate {
            Button(role: .destructive) { banning = message } label: {
                Label("Remove and Ban \(message.senderName)", systemImage: "person.fill.xmark")
            }
        }
    }

    private func heading(_ message: CrewMessage) -> String {
        let from = message.senderID == CrewCloud.shared.myID ? "You" : message.senderName
        switch message.kind {
        case .announcement, .announcementOneWay: return "📣 \(from)"
        case .message: return from
        case .reply: return message.toID == CrewMessage.everyone ? "\(from), to everyone" : "\(from), reply"
        case .welcome: return "✅ \(from)"
        case .finished: return "🏁 \(from)"
        }
    }

    private func load() async {
        guard !challenge.crewID.isEmpty else { return }
        messages = await CrewCloud.shared.messages(crewID: challenge.crewID)
    }
}

/// Who a Reply or Reply All from the message list goes to.
private struct ReplyTarget: Identifiable {
    let message: CrewMessage
    let toAll: Bool
    var id: String { "\(message.id).\(toAll)" }
}

private struct ComposeView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var footer = "It pops up on every crew member's phone."
    /// The leader's announcement: shows the Allow replies switch.
    var offersOneWay = false
    /// The text, and whether replies are allowed.
    let send: (String, Bool) async -> Bool

    // His word, 2026-10-23: "the announcer can toggle one way announcement or replies enabled". Remembered.
    @AppStorage("announcementAllowsReplies") private var allowReplies = true

    @State private var text = ""
    @State private var sending = false
    @State private var failed = false
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Keep it short — like \"Halfway there, crew!\"", text: $text, axis: .vertical)
                        .font(AppFont.body)
                        .lineLimit(2...4)
                        .focused($focused)
                } footer: {
                    Text(failed ? "It didn't send. Check iCloud in Settings and try again." : footer)
                        .font(AppFont.body)
                }
                if offersOneWay {
                    Section {
                        Toggle(isOn: $allowReplies) { Text("Allow replies").font(AppFont.body) }
                    } footer: {
                        Text(allowReplies ? "Your crew can Reply or Reply All." : "One way: no Reply or Reply All.").font(AppFont.body)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.font(AppFont.body)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        sending = true
                        Task {
                            if await send(trimmed, !offersOneWay || allowReplies) { dismiss() } else { failed = true }
                            sending = false
                        }
                    }
                    .font(AppFont.bodyBold)
                    .disabled(trimmed.isEmpty || sending)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }
}
