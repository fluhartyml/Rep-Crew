//
//  CrewDirectory.swift
//  Rep Crew
//
//  Everyone in your challenges, in one list. His words, 2026-10-23: "can it show profile picture
//  thumbnails that if you click on their name shows their profile? maybe it displays prefered
//  contact method on the directory list but if you click on the name it opens the profile and with
//  the opened profile you can share to your apple contacts with the contact photo?"
//
//  The people come from the same records the leaderboard reads: each challenge's leader and its
//  Membership records. Banned and blocked people don't show. Save to Contacts (with the photo) is
//  the profile's own button (Profile.swift).
//

import CloudKit
import SwiftData
import SwiftUI

/// A way to reach someone, as they ranked it in Settings → Your profile.
enum ContactMethod: String, CaseIterable, Identifiable {
    case call, text, email, facetime, facetimeAudio
    var id: String { rawValue }

    var title: String {
        switch self {
        case .call: return "Call"
        case .text: return "Text"
        case .email: return "Email"
        case .facetime: return "FaceTime Video"
        case .facetimeAudio: return "FaceTime Audio"
        }
    }

    var systemImage: String {
        switch self {
        case .call: return "phone.fill"
        case .text: return "message.fill"
        case .email: return "envelope.fill"
        case .facetime: return "video.fill"
        case .facetimeAudio: return "phone.circle.fill"
        }
    }

    /// What they typed for this way, or "" when they left it blank.
    func value(in profile: CrewProfile) -> String {
        switch self {
        case .call, .text: return profile.phone.trimmingCharacters(in: .whitespaces)
        case .email: return profile.email.trimmingCharacters(in: .whitespaces)
        case .facetime, .facetimeAudio: return profile.facetime.trimmingCharacters(in: .whitespaces)
        }
    }

    /// Their preferred way, only when they filled in what it needs.
    static func preferred(_ profile: CrewProfile) -> ContactMethod? {
        guard let method = ContactMethod(rawValue: profile.preferred), !method.value(in: profile).isEmpty else { return nil }
        return method
    }
}

// MARK: - iCloud

extension CrewCloud {
    /// Everyone in these challenges but you, once each, by name.
    func directory(crewIDs: [String]) async -> [ProfileTarget] {
        await connect()
        guard let myID else { return [] }
        var people: [String: String] = [:]
        for crewID in Set(crewIDs) where !crewID.isEmpty {
            var found: [String: String] = [:]
            var leaderID: String?
            if let leader = try? await db.record(for: CKRecord.ID(recordName: crewID)),
               let id = leader["leaderID"] as? String {
                leaderID = id
                found[id] = leader["leaderName"] as? String ?? "Crew leader"
            }
            let joined = CKQuery(recordType: "Membership", predicate: NSPredicate(format: "crewID == %@", crewID))
            if let (results, _) = try? await db.records(matching: joined) {
                for record in results.compactMap({ try? $0.1.get() }) {
                    guard let id = record["memberID"] as? String else { continue }
                    found[id] = record["name"] as? String ?? "Crew member"
                }
            }
            let hide = await hidden(crewID: crewID, leaderID: leaderID)
            for (id, name) in found where id != myID && !hide.contains(id) { people[id] = people[id] ?? name }
        }
        return people.map { ProfileTarget(id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - The list

struct CrewDirectoryView: View {
    @Query private var challenges: [Challenge]
    @State private var people: [ProfileTarget] = []
    @State private var profiles: [String: CrewProfile] = [:]
    @State private var loaded = false
    @State private var profileOf: ProfileTarget?

    var body: some View {
        List {
            if loaded && people.isEmpty {
                Text("No one yet. People in your challenges show here.").font(AppFont.body)
            }
            if !loaded {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Loading…").font(AppFont.body)
                }
            }
            ForEach(people) { person in
                Button { profileOf = person } label: { row(person).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens their profile")
            }
        }
        .navigationTitle("Crew Directory")
        .navigationBarTitleDisplayMode(.inline)
        .crewNavGlyphs()
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $profileOf) { ProfileView(target: $0) }
    }

    private func row(_ person: ProfileTarget) -> some View {
        let profile = profiles[person.id]
        let saved = profile?.name.trimmingCharacters(in: .whitespaces) ?? ""
        return HStack(spacing: 14) {
            ProfilePhoto(image: profile?.photo, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(saved.isEmpty ? person.name : saved).font(AppFont.bodyBold)
                if let profile, let method = ContactMethod.preferred(profile) {
                    Label("\(method.title): \(method.value(in: profile))", systemImage: method.systemImage)
                        .font(AppFont.body).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(AppFont.body).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    /// Names first, then each profile as it arrives.
    private func load() async {
        people = await CrewCloud.shared.directory(crewIDs: challenges.map(\.crewID))
        loaded = true
        for person in people {
            if case .found(let profile) = await CrewCloud.shared.fetchProfile(person.id) { profiles[person.id] = profile }
        }
    }
}
