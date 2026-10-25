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
                            Text("\(goal.amount(goal.done)) / \(goal.amount(goal.target)) \(goal.unit) · \(goal.challenge)").font(WatchFont.body)
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
    /// Steps or distance the Watch counted during the set, for a steps or miles goal.
    private(set) var steps: Double = 0
    private(set) var miles: Double = 0
    var problem: String?

    /// The Health workout type for an exercise, by its name. Anything not named here stays strength training.
    /// REM: tester feedback he passed on, 2026-10-25: "When I did a walk (I clicked start set in the Rep Crew app) it
    /// logged it in my fitness app as Traditional Strength Training." Names are free text, so match words in them.
    private static func activityType(for exercise: String) -> HKWorkoutActivityType {
        let name = exercise.lowercased()
        let kinds: [(words: [String], type: HKWorkoutActivityType)] = [
            (["walk", "steps"], .walking), (["run", "jog", "sprint"], .running), (["hike"], .hiking),
            (["swim"], .swimming), (["bike", "cycl", "spin"], .cycling), (["rowing", "erg"], .rowing),
            (["yoga"], .yoga), (["jump rope", "skip"], .jumpRope), (["stair", "step up"], .stairClimbing),
            (["stretch", "mobility"], .flexibility), (["dance"], .cardioDance),
        ]
        // Whole words by their start ("walking" matches walk; "bent-over rows" is NOT rowing), phrases as written.
        let words = name.split { !$0.isLetter }.map(String.init)
        func has(_ key: String) -> Bool { key.contains(" ") ? name.contains(key) : words.contains { $0.hasPrefix(key) } }
        return kinds.first { $0.words.contains(where: has) }?.type ?? .traditionalStrengthTraining
    }

    func begin(exercise: String) async {
        let energy = HKQuantityType(.activeEnergyBurned)
        do {
            let counted: Set<HKObjectType> = [HKQuantityType(.stepCount), HKQuantityType(.distanceWalkingRunning),
                                              HKQuantityType(.distanceCycling), HKQuantityType(.distanceSwimming)]
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType(), energy], read: counted.union([energy]))
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = Self.activityType(for: exercise)
            configuration.locationType = [.walking, .running, .hiking, .cycling].contains(configuration.activityType) ? .outdoor : .indoor
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
        let steps = workoutBuilder.statistics(for: HKQuantityType(.stepCount))?.sumQuantity()?.doubleValue(for: .count()) ?? 0
        let miles = [HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling), HKQuantityType(.distanceSwimming)]
            .compactMap { workoutBuilder.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .mile()) }.max() ?? 0
        Task { @MainActor in
            self.calories = kcal
            self.steps = steps
            self.miles = miles
        }
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
                        // Units (his ask, same day): minutes from the set's clock, steps and miles from what the Watch
                        // counted; reps and laps still start at 0. The crown changes any of them.
                        switch goal.unit {
                        case "minutes": reps = Double(max(Int((Date.now.timeIntervalSince(start) / 60).rounded()), 1))
                        case "steps": reps = set.steps.rounded()
                        case "miles": reps = (set.miles * Double(goal.scale)).rounded()
                        default: reps = 0
                        }
                        set.finish()
                    }
                    .tint(.green)
                } else if set.end != nil {
                    Text(goal.amount(Int(reps))).font(WatchFont.bigNumber).monospacedDigit()
                        .focusable()
                        .digitalCrownRotation($reps, from: 0, through: goal.unit == "steps" ? 100_000 : 1000,
                                              by: goal.unit == "steps" ? 100 : 1, sensitivity: .medium)
                    Text("\(goal.unit) — turn the crown").font(WatchFont.body)
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
        .task { await set.begin(exercise: goal.name) }
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
