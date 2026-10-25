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

    var body: some View {
        List {
            if !loaded { ProgressView() }
            ForEach(users) { user in
                NavigationLink {
                    UserAccountView(user: user)
                } label: {
                    HStack(spacing: 12) {
                        ProfilePhoto(image: user.profile?.photo, size: 44, seed: user.id)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.name).font(AppFont.bodyBold)
                            Text(summary(user)).font(AppFont.body).foregroundStyle(.secondary)
                        }
                    }
                }
                .contextMenu { AccessLevelMenu(memberID: user.id, name: user.name) }
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
