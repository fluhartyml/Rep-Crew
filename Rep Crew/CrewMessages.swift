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
    enum Kind: String { case announcement, message, reply, welcome }

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
        case .announcement: record["title"] = "📣 \(senderName)"
        case .message: record["title"] = senderName
        case .reply: record["title"] = "\(senderName) replied"
        case .welcome: record["title"] = "✅ \(senderName)"
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
            let hide = await hidden(crewID: crewID)
            return results.compactMap { try? $0.1.get() }.compactMap(Self.message(from:))
                .filter { $0.toID == CrewMessage.everyone || $0.toID == myID || $0.senderID == myID }
                .filter { !hide.contains($0.senderID) }
                .sorted { $0.sentAt > $1.sentAt }
        } catch let error as CKError where error.code == .unknownItem {
            return []   // No one has sent a message yet, so the record type doesn't exist yet.
        } catch {
            status = "Couldn't load messages: \(error.localizedDescription)"
            return []
        }
    }

    /// One subscription per crew for messages to everyone, and one for replies addressed to you.
    /// Saving with the same ID replaces the old one, so this is safe to run on every launch.
    func subscribe(crewIDs: [String]) async {
        await connect()
        guard let myID else { return }
        var subscriptions = crewIDs.map { crewID in
            subscription(id: "crew-\(crewID)", NSPredicate(format: "crewID == %@ AND toID == %@", crewID, CrewMessage.everyone))
        }
        subscriptions.append(subscription(id: "to-me", NSPredicate(format: "toID == %@", myID)))
        do {
            _ = try await db.modifySubscriptions(saving: subscriptions, deleting: [])
        } catch let error as CKError where error.code == .unknownItem || error.code == .partialFailure {
            // Before the first message is ever sent there is no CrewMessage type to subscribe to.
            // The next launch after someone sends one picks it up.
        } catch {
            status = "Couldn't turn on crew notifications: \(error.localizedDescription)"
        }
    }

    private func subscription(id: String, _ predicate: NSPredicate) -> CKQuerySubscription {
        let subscription = CKQuerySubscription(recordType: "CrewMessage", predicate: predicate,
                                               subscriptionID: id, options: [.firesOnRecordCreation])
        let info = CKSubscription.NotificationInfo()
        // A key with no translation is used as the format itself, so the record's own fields fill it in.
        info.titleLocalizationKey = "%1$@"
        info.titleLocalizationArgs = ["title"]
        info.alertLocalizationKey = "%1$@"
        info.alertLocalizationArgs = ["text"]
        info.soundName = "default"
        info.category = CrewNotifications.category
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
                                                                 intentIdentifiers: [])])
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

    private var isLeader: Bool { challenge.leaderID.isEmpty || challenge.leaderID == CrewCloud.shared.myID }

    var body: some View {
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
            }
        } header: {
            Text("Crew messages").font(AppFont.bodyBold).textCase(nil)
        }
        .task(id: challenge.crewID) { await load() }
        .sheet(isPresented: $composing) {
            ComposeView(title: isLeader ? "Announcement" : "Message the Crew") { text in
                let me = name.trimmingCharacters(in: .whitespaces)
                let sent = await CrewCloud.shared.send(text, crewID: challenge.crewID, kind: isLeader ? .announcement : .message,
                                                       senderName: me.isEmpty ? "A crew member" : me)
                if sent {
                    await CrewCloud.shared.subscribe(crewIDs: [challenge.crewID])
                    await load()
                }
                return sent
            }
        }
    }

    private func heading(_ message: CrewMessage) -> String {
        let from = message.senderID == CrewCloud.shared.myID ? "You" : message.senderName
        switch message.kind {
        case .announcement: return "📣 \(from)"
        case .message: return from
        case .reply: return message.toID == CrewMessage.everyone ? "\(from), to everyone" : "\(from), reply"

        case .welcome: return "✅ \(from)"
        }
    }

    private func load() async {
        guard !challenge.crewID.isEmpty else { return }
        messages = await CrewCloud.shared.messages(crewID: challenge.crewID)
    }
}

private struct ComposeView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let send: (String) async -> Bool

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
                    Text(failed ? "It didn't send. Check iCloud in Settings and try again." : "It pops up on every crew member's phone.")
                        .font(AppFont.body)
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
                            if await send(trimmed) { dismiss() } else { failed = true }
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
