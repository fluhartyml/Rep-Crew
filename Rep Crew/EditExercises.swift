//
//  EditExercises.swift
//  Rep Crew
//
//  The crew leader changes a running challenge's units and daily goals; every member's phone picks it up.
//  His ask, 2026-10-25, on the Walking Challenge ("1 rep a day"): "i need to edit the units from reps to
//  something else think it should be time?" → "yes build it".
//
//  REM: only the leader can save it. The shared CrewChallenge record belongs to whoever started the challenge,
//  and iCloud lets only its creator change it, so a coach's edit could never reach the crew. Members match
//  exercises by their place in the list (names may repeat), and only unit and goal change: reps already logged
//  stay as the numbers they were.
//

import CloudKit
import SwiftData
import SwiftUI

extension CrewCloud {
    /// Leader: writes the new goals to the challenge's shared record. False when iCloud said no.
    func updateGoals(crewID: String, goals: [Invite.Goal]) async -> Bool {
        await connect()
        guard !crewID.isEmpty, let text = String(data: (try? JSONEncoder().encode(goals)) ?? Data(), encoding: .utf8) else { return false }
        do {
            let record = try await db.record(for: CKRecord.ID(recordName: crewID))
            record["goals"] = text
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
            return true
        } catch {
            status = "Couldn't save the new goals: \(error.localizedDescription)"
            return false
        }
    }

    /// Member: the leader's current goals for each challenge you're in, read from the shared records.
    func sharedGoals(crewIDs: [String]) async -> [String: [Invite.Goal]] {
        await connect()
        let ids = crewIDs.filter { !$0.isEmpty }.map { CKRecord.ID(recordName: $0) }
        guard !ids.isEmpty, let results = try? await db.records(for: ids) else { return [:] }
        var found: [String: [Invite.Goal]] = [:]
        for (id, result) in results {
            guard let record = try? result.get(), let text = record["goals"] as? String,
                  let goals = try? JSONDecoder().decode([Invite.Goal].self, from: Data(text.utf8)) else { continue }
            found[id.recordName] = goals
        }
        return found
    }
}

enum GoalSync {
    /// Member copies take the leader's unit and daily goal, exercise by exercise in order. Your own challenges
    /// are the source, so they're left alone.
    @MainActor
    static func run(_ challenges: [Challenge], context: ModelContext) async {
        let joined = challenges.filter { !$0.leaderID.isEmpty && !$0.crewID.isEmpty && !$0.isFinished }
        guard !joined.isEmpty else { return }
        let shared = await CrewCloud.shared.sharedGoals(crewIDs: joined.map(\.crewID))
        var changed = false
        for challenge in joined {
            guard let goals = shared[challenge.crewID] else { continue }
            for (goal, leaders) in zip(challenge.sortedGoals, goals) where goal.name == leaders.name {
                if goal.unit != leaders.exerciseUnit { goal.unit = leaders.exerciseUnit; changed = true }
                if goal.dailyTarget != leaders.target, leaders.target > 0 { goal.dailyTarget = leaders.target; changed = true }
            }
        }
        if changed { try? context.save() }
    }
}

/// Leader only: each exercise's unit and daily goal.
struct EditExercisesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let challenge: Challenge

    private struct Row: Identifiable {
        let id: PersistentIdentifier
        let name: String
        var unit: ExerciseUnit
        var target: Int
    }

    @State private var rows: [Row] = []
    @State private var saving = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                ForEach($rows) { $row in
                    Section {
                        Picker("Counts in", selection: $row.unit) {
                            ForEach(ExerciseUnit.allCases) { unit in
                                Text(unit.title).tag(unit)
                            }
                        }
                        .font(AppFont.body)
                        .onChange(of: row.unit) { row.target = row.unit.startingTarget }
                        Stepper(value: $row.target, in: row.unit.targetRange, step: row.unit.targetStep(at: row.target)) {
                            Text("\(row.unit.label(row.target)) a day").font(AppFont.body)
                        }
                    } header: {
                        Text(row.name).font(AppFont.bodyBold).textCase(nil)
                    }
                }
                Section {
                    if failed {
                        Text("Your phone has the new goals, but the crew didn't get them. Check Settings → iCloud and save again.")
                            .font(AppFont.body)
                    }
                } footer: {
                    Text("Everyone in this challenge gets the new goals. Reps already logged stay as they are.")
                        .font(AppFont.body)
                }
            }
            .navigationTitle("Edit Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.font(AppFont.body)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .font(AppFont.bodyBold)
                        .disabled(saving)
                }
            }
            .onAppear {
                guard rows.isEmpty else { return }
                rows = challenge.sortedGoals.map { Row(id: $0.persistentModelID, name: $0.name, unit: $0.unit, target: $0.dailyTarget) }
            }
        }
    }

    private func save() async {
        saving = true
        for row in rows {
            guard let goal = challenge.allGoals.first(where: { $0.persistentModelID == row.id }) else { continue }
            goal.unit = row.unit
            goal.dailyTarget = row.target
        }
        try? context.save()
        var shared = challenge.crewID.isEmpty
        if !shared { shared = await CrewCloud.shared.updateGoals(crewID: challenge.crewID, goals: Invite.ChallengeInfo(challenge).goals) }
        if shared {
            dismiss()
        } else {
            failed = true
        }
        saving = false
    }
}
