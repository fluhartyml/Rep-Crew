//
//  Approvals.swift
//  Rep Crew
//
//  His words, 2026-10-25: "the crew didnt read it, the head coach read it or one of the coaches did, i want any
//  coach to be able to approve new applicants if i have a toggle that says 'allow coaches to approve new crew
//  applications'" · "yes build it".
//
//  REM: two records in the shared space, each honored only when CloudKit says who wrote it:
//    Welcomed  name = "welcomed.<member ID>". A coach (or him) sent the welcome letter. Shared, so every coach's
//              New Crew Members shows the applicant as processed, not just the phone that sent it.
//    Approval  name = "approved.<member ID>". Raises the member to at least Verified (level 11), so they can
//              join and start challenges. Honored from him always; from another coach only while his
//              "Allow coaches to approve new crew applications" switch (AccessTable.coachesApprove) is on.
//  The switch starts off (Claude's default: approving widens who can raise levels, so he turns it on).
//

import CloudKit
import SwiftUI

extension CrewCloud {
    /// The level an approval gives: the start of "Verified new user".
    static let approvedLevel = 11

    private static func welcomedID(_ memberID: String) -> CKRecord.ID { CKRecord.ID(recordName: "welcomed.\(memberID)") }
    private static func approvalID(_ memberID: String) -> CKRecord.ID { CKRecord.ID(recordName: "approved.\(memberID)") }

    /// Him, or a coach while his switch is on.
    var canApprove: Bool { GodMode.isOwner || (GodMode.isOn && accessTable.coachesApprove == true) }

    private func isCoachOrHim(_ id: String?) -> Bool {
        guard let id else { return false }
        return GodMode.ids.contains(id) || coaches[id] != nil
    }

    private func approvalCounts(_ record: CKRecord) -> Bool {
        guard let by = writer(of: record) else { return false }
        return GodMode.ids.contains(by) || (coaches[by] != nil && accessTable.coachesApprove == true)
    }

    // MARK: Welcomed

    /// Saves that the welcome letter went, for every coach to see.
    func markWelcomed(_ memberID: String) async {
        await connect()
        guard GodMode.isOn else { return }
        let record = (try? await db.record(for: Self.welcomedID(memberID))) ?? CKRecord(recordType: "Welcomed", recordID: Self.welcomedID(memberID))
        record["memberID"] = memberID
        record["welcomedAt"] = Date.now
        _ = try? await db.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
    }

    /// Adds everyone any coach welcomed to this phone's welcomed list (CrewSettings.welcomed), which the screens read.
    func syncWelcomed() async {
        await connect()
        let query = CKQuery(recordType: "Welcomed", predicate: NSPredicate(value: true))
        guard let (results, _) = try? await db.records(matching: query, resultsLimit: 400) else { return }
        let shared = results.compactMap { try? $0.1.get() }
            .filter { isCoachOrHim(writer(of: $0)) }
            .compactMap { $0["memberID"] as? String }
        let defaults = UserDefaults.standard
        let local = (defaults.string(forKey: CrewSettings.welcomed) ?? "").split(separator: "\n").map(String.init)
        let merged = local + shared.filter { !local.contains($0) }
        if merged.count != local.count { defaults.set(merged.joined(separator: "\n"), forKey: CrewSettings.welcomed) }
    }

    // MARK: Approval

    func approve(_ memberID: String) async -> Bool {
        await connect()
        guard canApprove, !GodMode.ids.contains(memberID) else { return false }
        let record = (try? await db.record(for: Self.approvalID(memberID))) ?? CKRecord(recordType: "Approval", recordID: Self.approvalID(memberID))
        record["memberID"] = memberID
        record["approvedAt"] = Date.now
        do {
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
            return true
        } catch {
            status = "Couldn't approve: \(error.localizedDescription)"
            return false
        }
    }

    func isApproved(_ memberID: String) async -> Bool {
        guard let record = try? await db.record(for: Self.approvalID(memberID)) else { return false }
        return approvalCounts(record)
    }

    /// Everyone approved, for New Crew Members.
    func approvedIDs() async -> Set<String> {
        await connect()
        let query = CKQuery(recordType: "Approval", predicate: NSPredicate(value: true))
        guard let (results, _) = try? await db.records(matching: query, resultsLimit: 400) else { return [] }
        return Set(results.compactMap { try? $0.1.get() }.filter(approvalCounts).compactMap { $0["memberID"] as? String })
    }
}

/// On an applicant's account page: Approve, or that they're approved.
struct ApproveSection: View {
    let memberID: String
    @State private var approved: Bool?
    @State private var working = false
    @State private var failed = false
    private var cloud = CrewCloud.shared

    init(memberID: String) { self.memberID = memberID }

    var body: some View {
        Section {
            if approved == true {
                Label("Approved", systemImage: "checkmark.seal.fill").font(AppFont.bodyBold).foregroundStyle(.green)
            } else if cloud.canApprove {
                Button {
                    Task {
                        working = true
                        failed = !(await cloud.approve(memberID))
                        if !failed { approved = true }
                        working = false
                    }
                } label: {
                    Label("Approve", systemImage: "checkmark.seal").font(AppFont.bodyBold)
                }
                .disabled(working || approved == nil)
            } else {
                Text("Only the head coach can approve right now.").font(AppFont.body).foregroundStyle(.secondary)
            }
            if failed {
                Text("That didn't go through. Check Settings → iCloud and try again.").font(AppFont.body)
            }
        } footer: {
            Text("Approving makes them a verified crew member (level \(CrewCloud.approvedLevel)), so they can join and start challenges.")
                .font(AppFont.body)
        }
        .task { approved = await cloud.isApproved(memberID) }
    }
}

/// His switch, at the top of New Crew Members.
struct CoachesApproveToggle: View {
    @State private var on = CrewCloud.shared.accessTable.coachesApprove == true
    @State private var failed = false

    var body: some View {
        if GodMode.isOwner {
            Section {
                Toggle(isOn: $on) {
                    Text("Allow coaches to approve new crew applications").font(AppFont.bodyBold)
                }
                .onChange(of: on) { _, value in
                    Task {
                        var table = CrewCloud.shared.accessTable
                        table.coachesApprove = value
                        failed = !(await CrewCloud.shared.saveAccessTable(table))
                    }
                }
                if failed {
                    Text("That didn't save. Check Settings → iCloud and try again.").font(AppFont.body)
                }
            } footer: {
                Text("Off: only you approve. On: any coach can approve an applicant too.").font(AppFont.body)
            }
        }
    }
}
