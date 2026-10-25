//
//  MustRead.swift
//  Rep Crew
//
//  Announcements everyone must read. His word, 2026-10-25: "i want a head coach user wide upon next launch
//  of the app announcement that the user has to read and press accept after reading".
//
//  REM: each one is a CrewMessage (kind .announcementOneWay) on the board crewID "must-read" — an existing
//  record type and index, so nothing new to deploy in iCloud. It counts only when CloudKit says the head
//  coach wrote it (GodMode.ids), never by the senderID field anyone could fill in.
//  REM: Home checks when the app opens or comes back to the front. Each one you haven't accepted covers the
//  screen, oldest first; Accept unlocks after scrolling to the end, as with the user agreement. Accepted
//  IDs are kept on this phone. Deleting one in Coach Mode stops it showing to anyone who hasn't accepted yet.
//  REM: builds before this never ask for crewID "must-read", so they never see one.
//  REM: his word, 2026-10-25: new users get the backlog ("yes please") and "the head coach needs to be able to
//  delete or have the announcement automatically expire after a set date". The text field holds JSON
//  (MustReadBody: text + optional expiresAt), as Events do, so no new iCloud field. Past its date it shows
//  to no one, accepted or not; it stays in Coach Mode marked Expired until he deletes it.
//

import CloudKit
import SwiftUI

extension CrewSettings {
    /// IDs of the must-read announcements this phone accepted, newline-separated.
    static let mustReadAccepted = "mustReadAccepted"
}

/// What a must-read's text field holds. Plain text (none posted that way, but safe) reads as no expiry.
struct MustReadBody: Codable {
    var text: String
    var expiresAt: Date?

    init(text: String, expiresAt: Date?) {
        self.text = text
        self.expiresAt = expiresAt
    }

    init(_ message: CrewMessage) {
        self = (try? JSONDecoder().decode(MustReadBody.self, from: Data(message.text.utf8)))
            ?? MustReadBody(text: message.text, expiresAt: nil)
    }

    var isExpired: Bool { expiresAt.map { $0 <= .now } ?? false }
}

extension CrewCloud {
    static let mustReadBoard = "must-read"

    /// Every must-read the head coach posted, oldest first.
    func mustReads() async -> [CrewMessage] {
        await connect()
        let query = CKQuery(recordType: "CrewMessage", predicate: NSPredicate(format: "crewID == %@", Self.mustReadBoard))
        guard let (results, _) = try? await db.records(matching: query, resultsLimit: 200) else { return [] }
        return results.compactMap { try? $0.1.get() }
            .filter { record in writer(of: record).map(GodMode.ids.contains) ?? false }
            .compactMap(Self.message(from:))
            .sorted { $0.sentAt < $1.sentAt }
    }

    /// The ones this phone still has to accept. The head coach never has to accept his own.
    func unacceptedMustReads() async -> [CrewMessage] {
        let accepted = MustRead.accepted
        return await mustReads().filter { !accepted.contains($0.id) && !GodMode.isOwner && !MustReadBody($0).isExpired }
    }

    /// Head coach only.
    func postMustRead(_ text: String, expiresAt: Date?, senderName: String) async -> Bool {
        guard GodMode.isOwner,
              let data = try? JSONEncoder().encode(MustReadBody(text: text, expiresAt: expiresAt)),
              let json = String(data: data, encoding: .utf8) else { return false }
        return await send(json, crewID: Self.mustReadBoard, kind: .announcementOneWay, senderName: senderName)
    }
}

enum MustRead {
    static var accepted: Set<String> {
        Set((UserDefaults.standard.string(forKey: CrewSettings.mustReadAccepted) ?? "").split(separator: "\n").map(String.init))
    }

    static func accept(_ id: String) {
        let all = accepted.union([id])
        UserDefaults.standard.set(all.sorted().joined(separator: "\n"), forKey: CrewSettings.mustReadAccepted)
    }
}

/// Full screen until Accept.
struct MustReadView: View {
    let message: CrewMessage
    let onAccept: () -> Void
    @State private var readToEnd = false

    var body: some View {
        NavigationStack {
            ScrollView {
                // Lazy, so the marker at the end appears only when it's scrolled onto the screen.
                LazyVStack(alignment: .leading, spacing: 16) {
                    Label("From \(message.senderName), Head Coach", systemImage: "megaphone.fill").font(AppFont.bodyBold)
                    Text(message.sentAt.formatted(date: .long, time: .shortened)).font(AppFont.body).foregroundStyle(.secondary)
                    Text(MustReadBody(message).text).font(AppFont.body).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    Color.clear.frame(height: 1).onAppear { readToEnd = true }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button(action: onAccept) {
                        Text("Accept").font(AppFont.bodyBold).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!readToEnd)
                    if !readToEnd {
                        Text("Scroll to the end to accept.").font(AppFont.body).foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("Please Read")
            .interactiveDismissDisabled()
        }
    }
}

/// Settings → Coach Mode → Must-Read Announcements. Head coach only.
struct MustReadAdminView: View {
    @AppStorage(CrewSettings.name) private var name = ""
    @State private var posted: [CrewMessage] = []
    @State private var loaded = false
    @State private var draft = ""
    @State private var sending = false
    @State private var note: String?
    @State private var expires = false
    @State private var expiresAt = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now

    var body: some View {
        List {
            Section {
                TextField("What everyone must read", text: $draft, axis: .vertical)
                    .font(AppFont.body).lineLimit(4...12)
                Toggle(isOn: $expires) { Text("Expires").font(AppFont.body) }
                if expires {
                    DatePicker("Expires on", selection: $expiresAt, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                        .font(AppFont.body)
                }
                Button { Task { await post() } } label: {
                    Label("Post to Everyone", systemImage: "megaphone.fill").font(AppFont.bodyBold)
                }
                .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let note { Text(note).font(AppFont.body) }
            } footer: {
                Text("The next time each crew member opens Rep Crew, it covers the screen until they scroll to the end and tap Accept. Everyone who joins later sees it too, until you delete it or it expires.")
                    .font(AppFont.body)
            }
            Section {
                if !loaded {
                    ProgressView()
                } else if posted.isEmpty {
                    Text("None posted.").font(AppFont.body).foregroundStyle(.secondary)
                }
                ForEach(posted.reversed()) { message in
                    let body = MustReadBody(message)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(body.text).font(AppFont.body).lineLimit(4)
                        Text(status(message, body)).font(AppFont.body).foregroundStyle(body.isExpired ? .red : .secondary)
                    }
                    .swipeActions {
                        Button(role: .destructive) { Task { await delete(message) } } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("Posted").font(AppFont.bodyBold).textCase(nil)
            } footer: {
                if !posted.isEmpty { Text("Swipe left to delete one.").font(AppFont.body) }
            }
        }
        .navigationTitle("Must-Read Announcements")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        posted = await CrewCloud.shared.mustReads()
        loaded = true
    }

    private func post() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        sending = true
        note = nil
        let me = name.trimmingCharacters(in: .whitespaces)
        if await CrewCloud.shared.postMustRead(text, expiresAt: expires ? expiresAt : nil, senderName: me.isEmpty ? "Coach" : me) {
            draft = ""
            expires = false
            note = "Posted. Everyone sees it the next time they open Rep Crew."
            await load()
        } else {
            note = "That didn't go through. Check iCloud in Settings and try again."
        }
        sending = false
    }

    /// "Posted Oct 25, 11:40 AM · Expires Nov 1, 9:00 AM", or "… · Expired Nov 1, 9:00 AM".
    private func status(_ message: CrewMessage, _ body: MustReadBody) -> String {
        var text = "Posted " + message.sentAt.formatted(date: .abbreviated, time: .shortened)
        if let end = body.expiresAt {
            text += (body.isExpired ? " · Expired " : " · Expires ") + end.formatted(date: .abbreviated, time: .shortened)
        }
        return text
    }

    private func delete(_ message: CrewMessage) async {
        if await CrewCloud.shared.removeMessage(message) {
            await load()
        } else {
            note = "That didn't go through. Check iCloud in Settings and try again."
        }
    }
}
