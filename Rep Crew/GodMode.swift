//
//  GodMode.swift
//  Rep Crew
//
//  His word, 2026-10-22: "i plan on having 'god mode'" · "my apple id gets god permissions" ·
//  on screen it's "Coach Mode" · "a crew leader … gets moderator permissions for their only
//  challenges. my coach mode is for any challenge and i should be able to grant and ungrant
//  coach permissions to worthy individuals".
//
//  Three levels:
//    Leader  — whoever created a challenge; moderates that challenge only.
//    Coach   — moderates every challenge (Reports, remove photos and messages, ban). He makes
//              someone a coach by writing a CoachGrant (name = coach.<their ID>); deleting it
//              takes it back.
//    Owner   — him (GodMode.ids): a coach who can also grant and revoke coaches.
//
//  Every check uses the iCloud ID CloudKit stamps on a record as its creator — never a field
//  the writer filled in, which anyone could fake.
//

import CloudKit
import SwiftUI

enum GodMode {
    /// His iCloud user IDs for this container. Development ID read off his 16e 2026-10-22 22:3x
    /// (build 43). Production not yet confirmed to match; if Coach Mode is missing on a
    /// TestFlight build, read it there and add it here.
    static let ids: Set<String> = ["_9c345d5e0487de171f04792dc4b88366"]

    /// True when this phone is a coach (or him).
    @MainActor static var isOn: Bool {
        guard let me = CrewCloud.shared.myID else { return false }
        return ids.contains(me) || CrewCloud.shared.coaches[me] != nil
    }

    /// True when this phone is him: the only one who grants and revokes coaches.
    @MainActor static var isOwner: Bool { CrewCloud.shared.myID.map(ids.contains) ?? false }
}

extension CrewCloud {
    /// Who wrote a record, as CloudKit recorded it. On the writer's own phone CloudKit says
    /// "__defaultOwner__" instead of the ID, so that maps back to this phone's ID.
    func writer(of record: CKRecord) -> String? {
        guard let name = record.creatorUserRecordID?.recordName else { return nil }
        return name == CKCurrentUserDefaultName ? myID : name
    }

    /// A removal or ban counts when the challenge's leader, a coach, or he wrote it.
    func isModerator(_ id: String?, leaderID: String?) -> Bool {
        guard let id else { return false }
        return id == leaderID || GodMode.ids.contains(id) || coaches[id] != nil
    }

    /// Coaches are the CoachGrants he wrote. Grants written by anyone else don't count.
    func loadCoaches() async {
        let query = CKQuery(recordType: "CoachGrant", predicate: NSPredicate(value: true))
        guard let (results, _) = try? await db.records(matching: query, resultsLimit: 200) else { return }
        var found: [String: String] = [:]
        for record in results.compactMap({ try? $0.1.get() }) {
            guard let by = writer(of: record), GodMode.ids.contains(by),
                  let id = record["coachID"] as? String else { continue }
            found[id] = record["name"] as? String ?? "Coach"
        }
        coaches = found
    }

    /// Owner only: make someone a coach, or take it back.
    func setCoach(_ id: String, name: String, on: Bool) async -> Bool {
        await connect()
        guard GodMode.isOwner else { return false }
        let recordID = CKRecord.ID(recordName: "coach.\(id)")
        do {
            if on {
                let record = CKRecord(recordType: "CoachGrant", recordID: recordID)
                record["coachID"] = id
                record["name"] = name
                _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            } else {
                _ = try await db.modifyRecords(saving: [], deleting: [recordID])
            }
            await loadCoaches()
            return true
        } catch {
            status = "Couldn't change coaches: \(error.localizedDescription)"
            return false
        }
    }

    struct ReportItem: Identifiable {
        let id: String
        let photoID: String
        let crewID: String
        let senderID: String
        let senderName: String
        let reportedAt: Date
    }

    /// Every report, newest first, minus photos god already removed.
    func reports() async -> [ReportItem] {
        await connect()
        let query = CKQuery(recordType: "Report", predicate: NSPredicate(value: true))
        guard let (results, _) = try? await db.records(matching: query, resultsLimit: 200) else { return [] }
        let removals = CKQuery(recordType: "PhotoRemoval", predicate: NSPredicate(value: true))
        let removed = Set(((try? await db.records(matching: removals, resultsLimit: 400))?.0 ?? [])
            .compactMap { try? $0.1.get() }
            .filter { isModerator(writer(of: $0), leaderID: nil) }
            .compactMap { $0["photoID"] as? String })
        return results.compactMap { try? $0.1.get() }.compactMap { record -> ReportItem? in
            guard let photoID = record["photoID"] as? String, !removed.contains(photoID),
                  let crewID = record["crewID"] as? String, let senderID = record["senderID"] as? String else { return nil }
            return ReportItem(id: record.recordID.recordName, photoID: photoID, crewID: crewID, senderID: senderID,
                              senderName: record["senderName"] as? String ?? "Crew member",
                              reportedAt: record["reportedAt"] as? Date ?? record.creationDate ?? .now)
        }
        .sorted { $0.reportedAt > $1.reportedAt }
    }
}

// MARK: - Settings → God Mode

struct GodModeSection: View {
    let isOn: Bool

    var body: some View {
        if isOn {
            Section {
                NavigationLink {
                    GodModeView()
                } label: {
                    Label("Reports", systemImage: "bolt.shield.fill").font(AppFont.bodyBold)
                }
                if GodMode.isOwner {
                    NavigationLink {
                        CoachesView()
                    } label: {
                        Label("Coaches", systemImage: "person.2.badge.gearshape.fill").font(AppFont.bodyBold)
                    }
                }
            } header: {
                // REM: His word 2026-10-22: call it "Coach Mode" on screen. The code keeps GodMode.
                Text("Coach Mode").font(AppFont.bodyBold).textCase(nil)
            }
        }
    }
}

private struct GodModeView: View {
    @State private var reports: [CrewCloud.ReportItem] = []
    @State private var loaded = false
    @State private var viewing: CrewCloud.ReportItem?
    @State private var full: UIImage?
    @State private var failed = false

    var body: some View {
        List {
            if loaded && reports.isEmpty {
                Text("No open reports.").font(AppFont.body)
            }
            ForEach(reports) { report in
                Button { viewing = report } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Photo from \(report.senderName)").font(AppFont.bodyBold).foregroundStyle(.primary)
                        Text(report.reportedAt.formatted(date: .abbreviated, time: .shortened)).font(AppFont.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if failed {
                Text("That didn't go through. Check iCloud in Settings and try again.").font(AppFont.body)
            }
        }
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $viewing) { report in
            NavigationStack {
                VStack(spacing: 16) {
                    if let full {
                        Image(uiImage: full).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        ProgressView()
                    }
                    Text("From \(report.senderName)").font(AppFont.body)
                    Button(role: .destructive) { Task { await act(report, ban: false) } } label: {
                        Text("Remove Photo").font(AppFont.bodyBold).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button(role: .destructive) { Task { await act(report, ban: true) } } label: {
                        Text("Remove Photo and Ban \(report.senderName)").font(AppFont.bodyBold).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer(minLength: 0)
                }
                .padding()
                .navigationTitle("Report")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { viewing = nil }.font(AppFont.bodyBold)
                    }
                }
                .task { full = await CrewCloud.shared.fullPhoto(report.photoID) }
            }
        }
    }

    private func load() async {
        reports = await CrewCloud.shared.reports()
        loaded = true
    }

    /// God acts like the challenge's leader: a PhotoRemoval, and for a ban a CrewBan.
    private func act(_ report: CrewCloud.ReportItem, ban: Bool) async {
        let photo = CrewPhoto(id: report.photoID, crewID: report.crewID, senderID: report.senderID,
                              senderName: report.senderName, takenAt: report.reportedAt, thumb: nil)
        var done = await CrewCloud.shared.removePhoto(photo)
        if ban { done = await CrewCloud.shared.ban(crewID: report.crewID, memberID: report.senderID, name: report.senderName) && done }
        failed = !done
        viewing = nil
        full = nil
        await load()
    }
}

/// His coaches, each with Remove. New coaches come from a leaderboard row's long-press → Make Coach.
private struct CoachesView: View {
    private var cloud = CrewCloud.shared
    @State private var failed = false

    var body: some View {
        List {
            Section {
                if cloud.coaches.isEmpty {
                    Text("No coaches yet.").font(AppFont.body)
                }
                ForEach(cloud.coaches.sorted { $0.value < $1.value }, id: \.key) { coach in
                    HStack {
                        Text(coach.value).font(AppFont.bodyBold)
                        Spacer()
                        Button("Remove") {
                            Task { failed = !(await cloud.setCoach(coach.key, name: coach.value, on: false)) }
                        }
                        .buttonStyle(.bordered).font(AppFont.body)
                    }
                }
                if failed {
                    Text("That didn't go through. Check iCloud in Settings and try again.").font(AppFont.body)
                }
            } footer: {
                Text("Coaches can moderate every challenge. To add one, long-press their name on any leaderboard and tap Make Coach.")
                    .font(AppFont.body)
            }
        }
        .navigationTitle("Coaches")
        .navigationBarTitleDisplayMode(.inline)
        .task { await cloud.loadCoaches() }
    }
}
