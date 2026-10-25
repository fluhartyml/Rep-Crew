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
//

import CloudKit
import SwiftUI

extension CrewSettings {
    /// IDs of the must-read announcements this phone accepted, newline-separated.
    static let mustReadAccepted = "mustReadAccepted"
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
        return await mustReads().filter { !accepted.contains($0.id) && !GodMode.isOwner }
    }

    /// Head coach only.
    func postMustRead(_ text: String, senderName: String) async -> Bool {
        guard GodMode.isOwner else { return false }
        return await send(text, crewID: Self.mustReadBoard, kind: .announcementOneWay, senderName: senderName)
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
                    Text(message.text).font(AppFont.body).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
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

    var body: some View {
        List {
            Section {
                TextField("What everyone must read", text: $draft, axis: .vertical)
                    .font(AppFont.body).lineLimit(4...12)
                Button { Task { await post() } } label: {
                    Label("Post to Everyone", systemImage: "megaphone.fill").font(AppFont.bodyBold)
                }
                .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let note { Text(note).font(AppFont.body) }
            } footer: {
                Text("The next time each crew member opens Rep Crew, it covers the screen until they scroll to the end and tap Accept. Everyone who joins later sees it too, until you delete it.")
                    .font(AppFont.body)
            }
            Section {
                if !loaded {
                    ProgressView()
                } else if posted.isEmpty {
                    Text("None posted.").font(AppFont.body).foregroundStyle(.secondary)
                }
                ForEach(posted.reversed()) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.text).font(AppFont.body).lineLimit(4)
                        Text(message.sentAt.formatted(date: .abbreviated, time: .shortened))
                            .font(AppFont.body).foregroundStyle(.secondary)
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
        if await CrewCloud.shared.postMustRead(text, senderName: me.isEmpty ? "Coach" : me) {
            draft = ""
            note = "Posted. Everyone sees it the next time they open Rep Crew."
            await load()
        } else {
            note = "That didn't go through. Check iCloud in Settings and try again."
        }
        sending = false
    }

    private func delete(_ message: CrewMessage) async {
        if await CrewCloud.shared.removeMessage(message) {
            await load()
        } else {
            note = "That didn't go through. Check iCloud in Settings and try again."
        }
    }
}
