//
//  UserList.swift
//  Rep Crew
//
//  Coach Mode → User List: the sysop's view of everyone. His words, 2026-10-24: "the crew directory is
//  for crew level viewing the sysop user list is where i can see all user data whether or not its marked
//  private, coach god mode" · "yes build it".
//
//  REM: everyone = anyone with a Profile, an application or an access record in the shared space.
//  Coaches-only contact info opens here because this phone's key is in the seal (ContactSeal); the
//  application opens the same way. Editing level, title and flags stays head-coach only (MemberAccessSection).
//

import CloudKit
import SwiftUI

extension CrewCloud {
    /// Every member iCloud knows about, sorted by level (highest first), then name.
    func allUsers() async -> [CrewUser] {
        await connect()
        var ids = Set<String>()
        let profiles = CKQuery(recordType: "Profile", predicate: NSPredicate(value: true))
        if let (results, _) = try? await db.records(matching: profiles, resultsLimit: 400) {
            for record in results.compactMap({ try? $0.1.get() }) {
                let name = record.recordID.recordName
                if name.hasPrefix("profile.") { ids.insert(String(name.dropFirst("profile.".count))) }
            }
        }
        let accessQuery = CKQuery(recordType: "MemberAccess", predicate: NSPredicate(value: true))
        if let (results, _) = try? await db.records(matching: accessQuery, resultsLimit: 400) {
            for record in results.compactMap({ try? $0.1.get() }) { if let id = record["memberID"] as? String { ids.insert(id) } }
        }
        let applications = GodMode.isOn ? await self.applications() : []
        ids.formUnion(applications.map(\.id))
        var users: [CrewUser] = []
        for id in ids {
            var profile: CrewProfile?
            if case .found(let found) = await fetchProfile(id) { profile = found }
            users.append(CrewUser(id: id, profile: profile, access: await memberAccess(id),
                                  application: applications.first { $0.id == id }))
        }
        return users.sorted { ($0.access.level, $1.name) > ($1.access.level, $0.name) }
    }
}

struct UserListView: View {
    @State private var users: [CrewUser] = []
    @State private var loaded = false
    @State private var messaging: ProfileTarget?
    @State private var opening: String?

    var body: some View {
        List {
            if !loaded { ProgressView() }
            ForEach(users) { user in card(user) }
        }
        .navigationTitle("User List")
        .sheet(item: $messaging) { InboxComposeView(target: $0) }
        .navigationDestination(item: $opening) { id in
            if let user = users.first(where: { $0.id == id }) { UserAccountView(user: user) }
        }
        .refreshable { users = await CrewCloud.shared.allUsers() }
        .task {
            users = await CrewCloud.shared.allUsers()
            loaded = true
        }
    }

    // REM: his word, 2026-10-25: "in the list editor it should show user cards with a contact button the
    // contact button could be either the crew members preferred contact or the users inbox". Same card shape
    // as the Crew Directory: the top opens their account; under it one full-width button. Their preferred
    // way when it's filled in (coaches see Coaches-only fields too), else their Rep Crew Inbox.
    private func card(_ user: CrewUser) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // .borderless here and .borderedProminent below give one List row two tap targets, as in the
            // Crew Directory; a NavigationLink would make the whole row open the account.
            Button { opening = user.id } label: {
                HStack(spacing: 12) {
                    ProfilePhoto(image: user.profile?.photo, size: 56, seed: user.id)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.name).font(AppFont.bodyBold)
                        Text(summary(user)).font(AppFont.body).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(AppFont.body).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .tint(.primary)
            .accessibilityHint("Opens their account")
            if let profile = user.profile, let method = ContactMethod.preferred(profile), let url = method.link(in: profile) {
                Link(destination: url) {
                    Label(method.title, systemImage: method.systemImage)
                        .font(AppFont.bodyBold)
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
            } else if user.id != CrewCloud.shared.myID {
                Button { messaging = ProfileTarget(id: user.id, name: user.name) } label: {
                    Label("Message Their Inbox", systemImage: "tray.and.arrow.down.fill")
                        .font(AppFont.bodyBold)
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 6)
        .contextMenu { AccessLevelMenu(memberID: user.id, name: user.name) }
    }

    private func summary(_ user: CrewUser) -> String {
        let range = CrewCloud.shared.accessTable.band(for: user.access.level)?.name ?? "No range"
        var parts = ["Level \(user.access.level) · \(range)"]
        if !user.access.title.isEmpty { parts.append(user.access.title) }
        if !user.access.flags.isEmpty { parts.append("Flags \(user.access.flags)") }
        return parts.joined(separator: " · ")
    }
}

/// Write to one person's Rep Crew Inbox — for someone with no preferred contact.
struct InboxComposeView: View {
    @Environment(\.dismiss) private var dismiss
    let target: ProfileTarget
    @AppStorage(CrewSettings.name) private var myName = ""
    @State private var draft = ""
    @State private var sending = false
    @State private var failed = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Message to \(target.name)", text: $draft, axis: .vertical)
                        .font(AppFont.body).lineLimit(3...10)
                        .focused($focused)
                } footer: {
                    Text("Goes to their Rep Crew Inbox, and as a notification if they allow it.").font(AppFont.body)
                }
                if failed {
                    Text("That didn't go through. Check iCloud in Settings and try again.").font(AppFont.body)
                }
            }
            .navigationTitle("Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.font(AppFont.bodyBold)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { Task { await send() } }
                        .font(AppFont.bodyBold)
                        .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        failed = false
        let me = myName.trimmingCharacters(in: .whitespaces)
        if await CrewCloud.shared.send(text, crewID: CrewMessage.direct(to: target.id), kind: .direct, to: target.id,
                                       senderName: me.isEmpty ? "A crew member" : me) {
            dismiss()
        } else {
            failed = true
        }
        sending = false
    }
}
