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

struct CrewUser: Identifiable {
    let id: String
    var profile: CrewProfile?
    var access: MemberAccess
    var application: ApplicationEntry?

    var name: String {
        let saved = profile?.name.trimmingCharacters(in: .whitespaces) ?? ""
        if !saved.isEmpty { return saved }
        return application?.name ?? "A crew member"
    }
}

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

    var body: some View {
        List {
            if !loaded { ProgressView() }
            ForEach(users) { user in
                NavigationLink {
                    UserDetailView(user: user)
                } label: {
                    HStack(spacing: 12) {
                        ProfilePhoto(image: user.profile?.photo, size: 44, seed: user.id)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.name).font(AppFont.bodyBold)
                            Text(summary(user)).font(AppFont.body).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("User List")
        .refreshable { users = await CrewCloud.shared.allUsers() }
        .task {
            users = await CrewCloud.shared.allUsers()
            loaded = true
        }
    }

    private func summary(_ user: CrewUser) -> String {
        let range = CrewCloud.shared.accessTable.band(for: user.access.level)?.name ?? "No range"
        var parts = ["Level \(user.access.level) · \(range)"]
        if !user.access.title.isEmpty { parts.append(user.access.title) }
        if !user.access.flags.isEmpty { parts.append("Flags \(user.access.flags)") }
        return parts.joined(separator: " · ")
    }
}

private struct UserDetailView: View {
    let user: CrewUser

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    ProfilePhoto(image: user.profile?.photo, size: 120, seed: user.id)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
            MemberAccessSection(memberID: user.id)
            Section {
                field("Phone", user.profile?.phone, privately: user.profile?.privateFields.contains("phone") ?? false)
                field("Email", user.profile?.email, privately: user.profile?.privateFields.contains("email") ?? false)
                field("FaceTime", user.profile?.facetime, privately: user.profile?.privateFields.contains("facetime") ?? false)
            } header: {
                Text("Contact").font(AppFont.bodyBold).textCase(nil)
            }
            Section {
                if let answers = user.application?.answers {
                    field("Email given to the coach", answers.email, privately: true)
                    field("Why they joined", answers.why, privately: true)
                    field("Fitness goals", answers.goals, privately: true)
                    field("Ideas for getting started", answers.suggestions, privately: true)
                } else {
                    Text(user.application == nil ? "No application sent." : "Their application wasn't sealed to your phone's key.")
                        .font(AppFont.body).foregroundStyle(.secondary)
                }
            } header: {
                Text("Application").font(AppFont.bodyBold).textCase(nil)
            }
            Section {
                Text(user.id).font(AppFont.body).foregroundStyle(.secondary).textSelection(.enabled)
            } header: {
                Text("iCloud ID").font(AppFont.bodyBold).textCase(nil)
            }
        }
        .navigationTitle(user.name)
    }

    private func field(_ title: String, _ value: String?, privately: Bool) -> some View {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return VStack(alignment: .leading, spacing: 4) {
            Text(title + (privately && !text.isEmpty ? " · Coaches only" : "")).font(AppFont.bodyBold)
            Text(text.isEmpty ? "Not given" : text)
                .font(AppFont.body)
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}
