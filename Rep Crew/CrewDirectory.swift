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

    /// The link that starts it straight away — the same links the profile's buttons use.
    func link(in profile: CrewProfile) -> URL? {
        switch self {
        case .call: return ProfileView.url("tel:", ProfileView.dialable(profile.phone))
        case .text: return ProfileView.url("sms:", ProfileView.dialable(profile.phone))
        case .email: return ProfileView.url("mailto:", profile.email.trimmingCharacters(in: .whitespaces))
        case .facetime: return ProfileView.url("facetime:", ProfileView.handle(profile.facetime))
        case .facetimeAudio: return ProfileView.url("facetime-audio:", ProfileView.handle(profile.facetime))
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
    /// Everyone in these challenges but you, once each, by name — after him.
    /// His word, 2026-10-23: "I should be user number one 'head coach'". He heads every directory,
    /// his own included, whether or not he's in your challenges.
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
        let heads = GodMode.ids.filter { !Blocklist.ids.contains($0) }
        let others = people.filter { !heads.contains($0.key) }.map { ProfileTarget(id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return heads.sorted().map { ProfileTarget(id: $0, name: people[$0] ?? "Head Coach") } + others
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
            // REM: His word, 2026-10-23: "the contacts arnt cards they are one list". A Section per person is
            // REM: what makes each one its own rounded card in an inset-grouped List.
            ForEach(people) { person in Section { row(person) } }
        }
        .navigationTitle("Crew Directory")
        .navigationBarTitleDisplayMode(.inline)
        .crewNavGlyphs()
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $profileOf) { ProfileView(target: $0) }
    }

    // REM: His ask, 2026-10-23: "on the directory ... it has greyed out facetime video.... that should
    // REM: be a link without having to open the contact should the contact card be larger so that can be
    // REM: a button and not be truncated?" — and "its not only facetime because i chose facetime as my
    // REM: prefered contact method". So the card is taller: photo and name on top open the profile; under
    // REM: them, one full-width button for THAT person's own preferred way, which starts it straight away.
    // REM: The address isn't shown on the card, so nothing gets cut off. No preference → no button.
    private func row(_ person: ProfileTarget) -> some View {
        let profile = profiles[person.id]
        let saved = profile?.name.trimmingCharacters(in: .whitespaces) ?? ""
        return VStack(alignment: .leading, spacing: 12) {
            Button { profileOf = person } label: {
                HStack(spacing: 14) {
                    ProfilePhoto(image: profile?.photo, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(saved.isEmpty ? person.name : saved).font(AppFont.bodyBold)
                        if GodMode.ids.contains(person.id) {
                            Label(person.id == CrewCloud.shared.myID ? "You · Head Coach" : "Head Coach", systemImage: "star.fill")
                                .font(AppFont.body).foregroundStyle(.tint)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(AppFont.body).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .tint(.primary)
            .accessibilityHint("Opens their profile")
            // REM: .borderless on the name and .borderedProminent here are what let one List row hold two
            // REM: separate tap targets; with the default style the whole row fires the first button.
            if let profile, let method = ContactMethod.preferred(profile), let url = method.link(in: profile) {
                Link(destination: url) {
                    Label(method.title, systemImage: method.systemImage)
                        .font(AppFont.bodyBold)
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 6)
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
