//
//  Library.swift
//  Rep Crew
//
//  The Library: every public challenge ever made, newest first, each one ready to Start Again.
//  His word, 2026-10-26: "i want to add a library that houses all past challenges ever mde with a coach
//  being able to delete from the library" · "yes build it".
//
//  REM: it replaces Home's "Past challenges" list, which showed only the 30 newest that had ended.
//  REM: private challenges stay out. A crew that made its challenge private shouldn't find it listed for
//  strangers.
//  REM: a coach's Remove HIDES a challenge from the Library; it never deletes it. The CrewChallenge record and
//  every member's reps stay. Hiding is a LibraryHidden record, name = libraryHidden.<crewID>, honored only when
//  a coach or he wrote it (the same trust rule as Ban in Moderation.swift). To put one back, delete its
//  LibraryHidden record in the CloudKit Console.
//  REM: hidden records are fetched by record name, not by query, so no new index is needed in Production.
//

import CloudKit
import SwiftUI

extension CrewCloud {
    /// Every public challenge, newest first, minus the ones a coach removed from the Library.
    func libraryChallenges() async -> [CrewListing] {
        await connect()
        guard myID != nil else { return [] }
        // endsAt is already queryable and sortable (pastChallenges used it); distantPast matches every challenge.
        let query = CKQuery(recordType: "CrewChallenge", predicate: NSPredicate(format: "endsAt >= %@", Date.distantPast as NSDate))
        query.sortDescriptors = [NSSortDescriptor(key: "endsAt", ascending: false)]
        var records: [CKRecord] = []
        guard var (results, cursor) = try? await db.records(matching: query, resultsLimit: 200) else { return [] }
        records += results.compactMap { try? $0.1.get() }
        while let next = cursor, let (more, nextCursor) = try? await db.records(continuingMatchFrom: next, resultsLimit: 200) {
            records += more.compactMap { try? $0.1.get() }
            (results, cursor) = (more, nextCursor)
        }
        let listings = records.compactMap { record -> CrewListing? in
            guard record["isPublic"] as? Int != 0, let invite = Self.invite(from: record), let info = invite.challenge else { return nil }
            return CrewListing(info: info, leaderID: invite.fromID ?? "", leaderName: invite.from)
        }
        let hidden = await libraryHidden(listings.map(\.id))
        return listings.filter { !hidden.contains($0.id) }
    }

    /// The crew IDs a coach or he removed from the Library.
    private func libraryHidden(_ crewIDs: [String]) async -> Set<String> {
        var hidden: Set<String> = []
        let ids = crewIDs.map { CKRecord.ID(recordName: "libraryHidden.\($0)") }
        for start in stride(from: 0, to: ids.count, by: 200) {
            let chunk = Array(ids[start..<min(start + 200, ids.count)])
            guard let found = try? await db.records(for: chunk) else { continue }
            for case let (_, .success(record)) in found {
                guard let writer = writer(of: record), coaches[writer] != nil || GodMode.ids.contains(writer),
                      let crewID = record["crewID"] as? String else { continue }
                hidden.insert(crewID)
            }
        }
        return hidden
    }

    /// A coach removes a challenge from the Library for everyone. The challenge itself is untouched.
    func hideFromLibrary(_ crewID: String) async -> Bool {
        guard GodMode.isOn else { return false }
        let record = CKRecord(recordType: "LibraryHidden", recordID: CKRecord.ID(recordName: "libraryHidden.\(crewID)"))
        record["crewID"] = crewID
        record["hiddenAt"] = Date.now
        do {
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            return true
        } catch {
            status = "Couldn't remove it from the Library: \(error.localizedDescription)"
            return false
        }
    }
}

struct LibraryView: View {
    @State private var listings: [CrewListing] = []
    @State private var hasLoaded = false
    @State private var again: Invite.ChallengeInfo?
    @State private var removing: CrewListing?
    @State private var note: String?
    private var cloud = CrewCloud.shared

    var body: some View {
        List {
            if let note {
                Text(note).font(AppFont.body).foregroundStyle(.secondary)
            }
            if !hasLoaded {
                ProgressView().frame(maxWidth: .infinity)
            } else if listings.isEmpty {
                Text("No challenges in the Library yet.").font(AppFont.body).foregroundStyle(.secondary)
            }
            ForEach(listings) { listing in
                row(listing)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if GodMode.isOn {
                            Button("Remove", role: .destructive) { removing = listing }
                        }
                    }
            }
        }
        .navigationTitle("Library")
        .crewNavGlyphs()
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: Binding(get: { again.map(LibraryAgain.init) }, set: { again = $0?.info })) { NewChallengeView(again: $0.info) }
        .confirmationDialog("Remove \(removing?.info.title ?? "this challenge") from the Library?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Remove from Library", role: .destructive) {
                guard let listing = removing else { return }
                Task {
                    if await cloud.hideFromLibrary(listing.id) {
                        listings.removeAll { $0.id == listing.id }
                        note = nil
                    } else {
                        note = cloud.status
                    }
                }
            }
        } message: {
            Text("It disappears from the Library for everyone. The challenge and everyone's reps stay.")
        }
    }

    @ViewBuilder
    private func row(_ listing: CrewListing) -> some View {
        let label = VStack(alignment: .leading, spacing: 6) {
            Text(listing.info.title).font(AppFont.bodyBold).foregroundStyle(.primary)
            Text("\(listing.leaderName) · \(listing.info.days) days").font(AppFont.body).foregroundStyle(.secondary)
            Text(listing.info.goals.map(\.name).joined(separator: ", ")).font(AppFont.body).foregroundStyle(.secondary)
            if cloud.can(.start) {
                Text("Start Again").font(AppFont.bodyBold).foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 4)
        if cloud.can(.start) {
            Button { again = listing.info } label: { label }
        } else {
            label
        }
    }

    private func load() async {
        listings = await cloud.libraryChallenges()
        hasLoaded = true
    }
}

private struct LibraryAgain: Identifiable {
    let info: Invite.ChallengeInfo
    var id: String { info.crewID + info.title }
}
