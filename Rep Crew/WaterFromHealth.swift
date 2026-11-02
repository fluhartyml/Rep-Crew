//
//  WaterFromHealth.swift
//  Rep Crew
//
//  REM: Smitty's water challenge (his word 2026-11-01: "yes build the water challenge"). From Health reads today's
//  water from the Health app and logs whatever is new since the last time, so tapping twice never counts it twice.
//  Health has only the water someone logs there, by hand or from an app; the Apple Watch doesn't measure it.
//

import SwiftUI
import SwiftData

struct WaterFromHealthButton: View {
    @Environment(\.modelContext) private var context
    let goal: ExerciseGoal
    @State private var reading = false
    @State private var result: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { Task { await bringIn() } } label: {
                Label("From Health", systemImage: "heart.fill").font(AppFont.bodyBold)
            }
            .buttonStyle(.bordered)
            .disabled(reading)
            if let result {
                Text(result).font(AppFont.body).foregroundStyle(.secondary)
            }
        }
    }

    private func bringIn() async {
        reading = true
        defer { reading = false }
        guard let health = await HealthSets.waterToday() else {
            result = "No water in Health today."
            return
        }
        // Only what Health has beyond what's already logged from Health today.
        let fromHealth = goal.allEntries.filter { Calendar.current.isDateInToday($0.loggedAt) && $0.note == Self.mark }.reduce(0) { $0 + $1.count }
        let new = health - fromHealth
        guard new > 0 else {
            result = "Nothing new in Health. Health has \(ExerciseUnit.ounces.label(health)) today."
            return
        }
        let entry = RepEntry(count: new)
        entry.note = Self.mark
        entry.goal = goal
        context.insert(entry)
        try? context.save()
        result = "Added \(ExerciseUnit.ounces.label(new)) from Health."
    }

    /// Marks an entry that came from Health, so the next read adds only the difference.
    static let mark = "From Health"
}
