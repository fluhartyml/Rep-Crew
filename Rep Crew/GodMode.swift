//
//  GodMode.swift
//  Rep Crew
//
//  His word, 2026-10-22: "i plan on having 'god mode'" · "my apple id gets god permissions".
//  The developer's moderation over every challenge: every report in one list, and the
//  leader's powers — remove a photo, ban someone — on any challenge.
//
//  Who is god: the iCloud user IDs below. A god removal or ban is honored on every phone the
//  same way a leader's is (Moderation.swift, PhotoBoard.swift, CrewMessages.swift check
//  `isModerator`). An iCloud user ID can't be faked in a record: CloudKit stamps the writer.
//

import CloudKit
import SwiftUI

enum GodMode {
    /// His iCloud user IDs for this container — Development (Xcode installs) and Production
    /// (TestFlight / App Store) — read off his 16e, not typed from memory.
    /// Development ID read off his 16e 2026-10-22 22:3x (build 43). Production not yet confirmed
    /// to match; if god mode is missing on a TestFlight build, read it there and add it here.
    static let ids: Set<String> = ["_9c345d5e0487de171f04792dc4b88366"]

    /// True when this phone is signed in as him.
    @MainActor static var isOn: Bool { CrewCloud.shared.myID.map(ids.contains) ?? false }
}

extension CrewCloud {
    /// A removal or ban counts when the challenge's leader or god wrote it.
    func isModerator(_ id: String?, leaderID: String?) -> Bool {
        guard let id else { return false }
        return id == leaderID || GodMode.ids.contains(id)
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
            .filter { GodMode.ids.contains($0["removedBy"] as? String ?? "") }
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
    var body: some View {
        if GodMode.isOn {
            Section {
                NavigationLink {
                    GodModeView()
                } label: {
                    Label("Reports", systemImage: "bolt.shield.fill").font(AppFont.bodyBold)
                }
            } header: {
                Text("God Mode").font(AppFont.bodyBold).textCase(nil)
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
