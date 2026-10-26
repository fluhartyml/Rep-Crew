//
//  SetTimer.swift
//  Rep Crew
//
//  "Start Set": time a set, log its reps, and save it to Health as a real workout of its kind
//  (walking for a walk, strength training for push-ups; HealthSets.activityType).
//  His plan, 2026-10-22 ~20:00 — the rings close because real workouts land in Health, and
//  the app never says so: "we would never say 'close your rings' or any trade marks".
//
//  iPhone measures only the set's real start and end, so the workout carries time and no
//  calories. Never invent time or calories. Health access: write workouts, and (since 2026-10-23,
//  his "lock in 022g") read workouts + active energy for the matching screen (HealthMatch.swift).
//

import HealthKit
import SwiftData
import SwiftUI

enum HealthSets {
    static let store = HKHealthStore()
    static let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]
    /// Read for Match Health Workouts only. Asked in the same prompt as saving, so it's one question.
    static let readTypes: Set<HKObjectType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned),
                                               HKQuantityType(.heartRate), HKQuantityType(.stepCount),
                                               HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling),
                                               HKQuantityType(.distanceSwimming)]

    /// The Health workout type for an exercise, by its name. Anything not named here stays strength training.
    /// REM: tester feedback he passed on, 2026-10-25: "When I did a walk (I clicked start set in the Rep Crew app) it
    /// logged it in my fitness app as Traditional Strength Training." Names are free text, so match words in them.
    static func activityType(for exercise: String) -> HKWorkoutActivityType {
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

    /// True when another app's workout (the Apple Watch's Workout app, Strava…) already covers most of this set.
    /// REM: same feedback: "when my dad did it, he was also tracking it on his Apple Watch, so it duplicated the
    /// workout." Then Rep Crew saves no second workout; the reps are still logged. Health hides workouts it
    /// wasn't allowed to read, so with read access off this finds nothing and saves as before.
    static func anotherAppRecorded(start: Date, end: Date) async -> Bool {
        let mine = Bundle.main.bundleIdentifier ?? "com.accountability.dailyrepcrew"
        let window = HKQuery.predicateForSamples(withStart: start.addingTimeInterval(-60), end: end.addingTimeInterval(60))
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(window)], sortDescriptors: [], limit: 20)
        guard let workouts = try? await descriptor.result(for: store) else { return false }
        let length = max(end.timeIntervalSince(start), 1)
        return workouts.contains { workout in
            guard !workout.sourceRevision.source.bundleIdentifier.hasPrefix(mine) else { return false }
            let overlap = min(end, workout.endDate).timeIntervalSince(max(start, workout.startDate))
            return overlap >= length * 0.5
        }
    }

    /// Saves one set as a workout of its kind with its real start and end. False when Health is
    /// unavailable or you said no; your reps are logged either way. True without saving when another
    /// app already recorded it (`anotherAppRecorded`).
    static func save(start: Date, end: Date, exercise: String, reps: Int) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let workout = HKObjectType.workoutType()
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            guard store.authorizationStatus(for: workout) == .sharingAuthorized else { return false }
            if await anotherAppRecorded(start: start, end: end) { return true }
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = activityType(for: exercise)
            let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
            try await builder.beginCollection(at: start)
            try await builder.addMetadata([HKMetadataKeyWorkoutBrandName: "Rep Crew", "Exercise": exercise, "Reps": reps])
            try await builder.endCollection(at: end)
            return try await builder.finishWorkout() != nil
        } catch {
            return false
        }
    }
}

struct SetTimerView: View {
    @Environment(\.dismiss) private var dismiss
    let goal: ExerciseGoal
    /// The clock is running; swiping the sheet away would lose the set.
    @State private var timing = true

    var body: some View {
        NavigationStack {
            SetTimerPanel(goal: goal, continueTitle: "Done", timing: $timing) { dismiss() }
                .navigationTitle("Set")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.font(AppFont.bodyBold)
                    }
                }
        }
        .interactiveDismissDisabled(timing)
    }
}

/// One timed set: the clock runs, Finish Set asks how many, Save Set logs them and saves the workout.
/// Shared by Start Set and Start Routine (Routine.swift).
struct SetTimerPanel: View {
    @Environment(\.modelContext) private var context
    let goal: ExerciseGoal
    /// The button shown when Health said no, to move on anyway.
    let continueTitle: String
    @Binding var timing: Bool
    /// The reps are logged.
    let onSaved: () -> Void

    @State private var start = Date.now
    @State private var end: Date?
    @State private var reps = ""
    @State private var saving = false
    @State private var healthNote: String?
    /// Reps are in; only Health said no. Saving again would log them twice.
    @State private var logged = false
    @FocusState private var repsFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Text(goal.name).font(AppFont.heading)
            if let end {
                Text(Self.duration(end.timeIntervalSince(start))).font(AppFont.bigNumber).monospacedDigit()
                TextField("\(goal.unit.title) in this set", text: $reps)
                    .keyboardType(goal.unit.takesDecimal ? .decimalPad : .numberPad)
                    .font(AppFont.heading)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                    .focused($repsFocused)
                    // Typing over the starting 0 replaces it: "0" then "2" reads 2, not 02.
                    .onChange(of: reps) { _, text in
                        if text.count > 1, text.hasPrefix("0"), !text.hasPrefix("0.") { reps = String(text.dropFirst()) }
                    }
                Button {
                    Task { await save(end: end) }
                } label: {
                    Text("Save Set").font(AppFont.bodyBold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(saving || logged || goal.unit.count(from: reps) == nil)
                if let healthNote {
                    Text(healthNote).font(AppFont.body).multilineTextAlignment(.center)
                    Button { onSaved() } label: {
                        Text(continueTitle).font(AppFont.bodyBold).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                TimelineView(.periodic(from: start, by: 1)) { context in
                    Text(Self.duration(context.date.timeIntervalSince(start))).font(AppFont.bigNumber).monospacedDigit()
                }
                Button {
                    let finished = Date.now
                    end = finished
                    timing = false
                    // REM: his ask 2026-10-25 (units): minutes come from this set's clock, steps and miles from
                    // what Health counted during it; reps and laps start at 0, like the Watch (his word, 2026-10-26:
                    // "yes start at 0 to match the watch"). Save Set stays off until it's above 0.
                    // Any of them can be changed before Save Set. Nothing measured → the field is left to type.
                    switch goal.unit {
                    case .minutes:
                        reps = "\(max(Int((finished.timeIntervalSince(start) / 60).rounded()), 1))"
                    case .steps, .miles:
                        reps = ""
                        let unit = goal.unit, name = goal.name, from = start
                        Task {
                            if let measured = await HealthSets.measured(unit, exercise: name, start: from, end: finished), reps.isEmpty {
                                reps = unit.amount(measured).replacingOccurrences(of: ",", with: "")
                            }
                        }
                    case .reps, .laps:
                        reps = "0"
                    }
                    repsFocused = true
                } label: {
                    Text("Finish Set").font(AppFont.bodyBold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding()
    }

    private func save(end: Date) async {
        guard let count = goal.unit.count(from: reps) else { return }
        saving = true
        let entry = RepEntry(count: count, loggedAt: end)
        entry.startedAt = start
        entry.goal = goal
        context.insert(entry)
        try? context.save()
        if await HealthSets.save(start: start, end: end, exercise: goal.name, reps: count) {
            onSaved()
        } else {
            // REM: shakedown bug 4 (2026-10-23). The Health prompt did show; the tester said no, and iOS
            // never asks twice. So name the exact place to turn it back on.
            healthNote = "Your reps are logged. To save sets to Health too, open Settings, tap Health, then Data Access & Devices, then Daily Rep Crew Accountability, and turn on Workouts."
            logged = true
            saving = false
        }
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
