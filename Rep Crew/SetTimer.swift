//
//  SetTimer.swift
//  Rep Crew
//
//  "Start Set": time a set, log its reps, and save it to Health as a real strength workout.
//  His plan, 2026-10-22 ~20:00 — the rings close because real workouts land in Health, and
//  the app never says so: "we would never say 'close your rings' or any trade marks".
//
//  iPhone measures only the set's real start and end, so the workout carries time and no
//  calories. Never invent time or calories. Health access is write-only: workouts, nothing read.
//

import HealthKit
import SwiftData
import SwiftUI

enum HealthSets {
    private static let store = HKHealthStore()

    /// Saves one set as a strength workout with its real start and end. False when Health is
    /// unavailable or you said no; your reps are logged either way.
    static func save(start: Date, end: Date, exercise: String, reps: Int) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let workout = HKObjectType.workoutType()
        do {
            try await store.requestAuthorization(toShare: [workout], read: [])
            guard store.authorizationStatus(for: workout) == .sharingAuthorized else { return false }
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .traditionalStrengthTraining
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
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let goal: ExerciseGoal

    @State private var start = Date.now
    @State private var end: Date?
    @State private var reps = ""
    @State private var saving = false
    @State private var healthNote: String?
    /// Reps are in; only Health said no. Saving again would log them twice.
    @State private var logged = false
    @FocusState private var repsFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(goal.name).font(AppFont.heading)
                if let end {
                    Text(Self.duration(end.timeIntervalSince(start))).font(AppFont.bigNumber).monospacedDigit()
                    TextField("Reps in this set", text: $reps)
                        .keyboardType(.numberPad)
                        .font(AppFont.heading)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder)
                        .focused($repsFocused)
                    Button {
                        Task { await save(end: end) }
                    } label: {
                        Text("Save Set").font(AppFont.bodyBold).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(saving || logged || (Int(reps) ?? 0) <= 0)
                    if let healthNote { Text(healthNote).font(AppFont.body).multilineTextAlignment(.center) }
                } else {
                    TimelineView(.periodic(from: start, by: 1)) { context in
                        Text(Self.duration(context.date.timeIntervalSince(start))).font(AppFont.bigNumber).monospacedDigit()
                    }
                    Button {
                        end = .now
                        reps = goal.remaining(on: .now) > 0 ? "\(goal.remaining(on: .now))" : ""
                        repsFocused = true
                    } label: {
                        Text("Finish Set").font(AppFont.bodyBold).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(logged ? "Done" : "Cancel") { dismiss() }.font(AppFont.bodyBold)
                }
            }
        }
        .interactiveDismissDisabled(end == nil)
    }

    private func save(end: Date) async {
        guard let count = Int(reps), count > 0 else { return }
        saving = true
        let entry = RepEntry(count: count, loggedAt: end)
        entry.goal = goal
        context.insert(entry)
        try? context.save()
        if await HealthSets.save(start: start, end: end, exercise: goal.name, reps: count) {
            dismiss()
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
