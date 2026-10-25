//
//  WatchSet.swift
//  Rep Crew Watch
//
//  Today's goals, then a live strength workout for one set. Finish → enter reps with the
//  Digital Crown → the workout is saved to Health with the Watch's own time and calories,
//  and the reps go to the iPhone.
//

import HealthKit
import SwiftUI

struct GoalListView: View {
    private var link = PhoneLink.shared

    var body: some View {
        NavigationStack {
            List {
                if link.goals.isEmpty {
                    Text("Open Rep Crew on your iPhone to bring today's goals here.").font(WatchFont.body)
                }
                ForEach(link.goals) { goal in
                    NavigationLink(value: goal) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.name).font(WatchFont.bodyBold)
                            Text("\(goal.done) / \(goal.target) · \(goal.challenge)").font(WatchFont.body)
                                .foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
            .navigationTitle("Rep Crew")
            .navigationDestination(for: WatchGoal.self) { SetView(goal: $0) }
        }
        .onAppear { link.start() }
    }
}

@MainActor @Observable
final class SetSession: NSObject, HKLiveWorkoutBuilderDelegate, HKWorkoutSessionDelegate {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private(set) var start: Date?
    private(set) var end: Date?
    private(set) var calories: Double = 0
    var problem: String?

    func begin() async {
        let energy = HKQuantityType(.activeEnergyBurned)
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType(), energy], read: [energy])
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .traditionalStrengthTraining
            configuration.locationType = .indoor
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            builder.delegate = self
            session.delegate = self
            self.session = session
            self.builder = builder
            let now = Date.now
            session.startActivity(with: now)
            try await builder.beginCollection(at: now)
            start = now
        } catch {
            problem = "Health didn't start the set. Allow Rep Crew in the Health app on your iPhone."
        }
    }

    func finish() {
        guard let session else { return }
        end = .now
        session.end()
    }

    /// Saves the workout to Health. Reps travel separately, to the iPhone.
    func save() async -> Bool {
        guard let builder, let end else { return false }
        do {
            try await builder.endCollection(at: end)
            return try await builder.finishWorkout() != nil
        } catch {
            return false
        }
    }

    func discard() {
        session?.end()
        builder?.discardWorkout()
    }

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let kcal = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
        Task { @MainActor in self.calories = kcal }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {}
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.problem = "The set stopped: \(error.localizedDescription)" }
    }
}

struct SetView: View {
    @Environment(\.dismiss) private var dismiss
    let goal: WatchGoal

    @State private var set = SetSession()
    @State private var reps = 0.0
    @State private var saving = false
    @State private var note: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(goal.name).font(WatchFont.bodyBold)
                if let start = set.start, set.end == nil {
                    TimelineView(.periodic(from: start, by: 1)) { context in
                        Text(Self.duration(context.date.timeIntervalSince(start))).font(WatchFont.bigNumber).monospacedDigit()
                    }
                    Text("\(Int(set.calories)) cal").font(WatchFont.body)
                    Button("Finish Set") {
                        // REM: Watch feedback he passed on, 2026-10-25: "instead of having the Reps set at Max when
                        // you finish a set, it should probably start at 0". Crown up from 0; Save stays off until 1.
                        reps = 0
                        set.finish()
                    }
                    .tint(.green)
                } else if set.end != nil {
                    Text("\(Int(reps))").font(WatchFont.bigNumber).monospacedDigit()
                        .focusable()
                        .digitalCrownRotation($reps, from: 0, through: 1000, by: 1, sensitivity: .medium)
                    Text("reps — turn the crown").font(WatchFont.body)
                    Button("Save Set") { Task { await save() } }
                        .disabled(saving || reps < 1)
                        .tint(.green)
                } else if let problem = set.problem {
                    Text(problem).font(WatchFont.body)
                } else {
                    ProgressView()
                }
                if let note { Text(note).font(WatchFont.body) }
            }
        }
        .task { await set.begin() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { set.discard(); dismiss() }
            }
        }
    }

    private func save() async {
        guard let end = set.end else { return }
        saving = true
        let count = Int(reps)
        PhoneLink.shared.send(goalID: goal.id, reps: count, at: end)
        if await set.save() {
            dismiss()
        } else {
            note = "Reps sent to your iPhone. The set wasn't saved to Health."
        }
        saving = false
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
