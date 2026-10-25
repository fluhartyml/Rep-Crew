//
//  DailyStats.swift
//  Rep Crew
//
//  What you did each day, to pull people back every day. His word, 2026-10-25: "to motivate daily
//  participation we need to rework the checkmark seal glyph. it should show you did green checkmark
//  xn of activity per day ... accumulated time of activity per day and maybe some sort of scatterpoint
//  chart showing all activity over time".
//
//  REM: time counts only what was really measured: a timed set (Start Set / Start Routine) and Health
//  workouts paired as Minutes. Reps added with the + buttons have no time and add none. Never invent time.
//  A set timed before build 92 has no start on its RepEntry, so its length comes from the workout it
//  saved to Health (matched by exercise and end time). Health is read only when access was already
//  given, so opening a challenge never asks for it.
//

import Charts
import HealthKit
import SwiftData
import SwiftUI

extension Challenge {
    func entries(on date: Date) -> [RepEntry] {
        let cal = Calendar.current
        return allGoals.flatMap(\.allEntries).filter { cal.isDate($0.loggedAt, inSameDayAs: date) }
    }

    func sets(on date: Date) -> Int { entries(on: date).count }
    func reps(on date: Date) -> Int { entries(on: date).reduce(0) { $0 + $1.count } }

    /// Measured seconds on `date`: timed sets plus Health workouts paired as Minutes.
    func activeSeconds(on date: Date) -> Double {
        entries(on: date).reduce(0) { $0 + ($1.timedSeconds ?? 0) }
            + Double(allGoals.reduce(0) { $0 + $1.healthMinutes(on: date) }) * 60
    }

    /// "3 sets · 445 reps · 12 min", or nil for a day with nothing logged.
    func statsText(on date: Date) -> String? {
        let sets = sets(on: date)
        guard sets > 0 else { return nil }
        var parts = ["\(sets) \(sets == 1 ? "set" : "sets")", "\(reps(on: date).formatted()) reps"]
        let seconds = activeSeconds(on: date)
        if seconds >= 1 { parts.append(DailyStats.duration(seconds)) }
        return parts.joined(separator: " · ")
    }
}

extension RepEntry {
    /// How long the set took, when it was timed.
    var timedSeconds: Double? {
        if let startedAt { return max(loggedAt.timeIntervalSince(startedAt), 0) }
        let name = goal?.name ?? ""
        return HealthLibrary.shared.ownSets.first { $0.exercise == name && abs($0.end.timeIntervalSince(loggedAt)) < 2 }?.seconds
    }
}

enum DailyStats {
    /// "45 sec", "12 min", "1 h 5 min".
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds)
        if total < 60 { return "\(total) sec" }
        let minutes = total / 60
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }

    /// Reads Health only when this app may already save workouts, so it never raises the prompt.
    @MainActor static func refreshHealthIfAllowed() async {
        guard HKHealthStore.isHealthDataAvailable(),
              HealthSets.store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return }
        await HealthLibrary.shared.refresh()
    }
}

/// The reworked seal: green when the day is done, and how many sets you put in.
struct DaySeal: View {
    let challenge: Challenge
    let day: Date

    var body: some View {
        let complete = challenge.isComplete(on: day)
        let sets = challenge.sets(on: day)
        if complete || sets > 0 {
            HStack(spacing: 4) {
                Image(systemName: complete ? "checkmark.seal.fill" : "seal")
                    .foregroundStyle(complete ? .green : .secondary)
                if sets > 0 { Text("×\(sets)").monospacedDigit() }
            }
            .font(AppFont.heading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((complete ? "Done for today, " : "") + "\(sets) \(sets == 1 ? "set" : "sets")")
        }
    }
}

/// Every set of the challenge as a dot: when it was done and how many reps, one color per exercise.
struct ActivitySection: View {
    let challenge: Challenge

    private var points: [(id: PersistentIdentifier, date: Date, reps: Int, exercise: String)] {
        challenge.sortedGoals.flatMap { goal in goal.allEntries.map { ($0.persistentModelID, $0.loggedAt, $0.count, goal.name) } }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        let points = points
        if !points.isEmpty {
            Section {
                Chart(points, id: \.id) { point in
                    PointMark(x: .value("When", point.date), y: .value("Reps", point.reps))
                        .foregroundStyle(by: .value("Exercise", point.exercise))
                        .symbolSize(80)
                }
                .chartXScale(domain: challenge.startDate...(Calendar.current.date(byAdding: .day, value: 1, to: challenge.lastDay) ?? challenge.lastDay))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(challenge.days / 4, 1))) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(AppFont.body)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                        AxisValueLabel().font(AppFont.body)
                    }
                }
                .chartLegend(position: .bottom)
                .frame(height: 240)
                .padding(.vertical, 8)
                .accessibilityLabel("Every set of the challenge, reps by date")
                Text(totals).font(AppFont.body)
            } header: {
                Text("Activity").font(AppFont.bodyBold).textCase(nil)
            }
        }
    }

    /// "All days: 2,340 reps in 31 sets · 1 h 12 min".
    private var totals: String {
        let entries = challenge.allGoals.flatMap(\.allEntries)
        let reps = entries.reduce(0) { $0 + $1.count }
        let seconds = challenge.allDays.reduce(0) { $0 + challenge.activeSeconds(on: $1) }
        var text = "All days: \(reps.formatted()) reps in \(entries.count) \(entries.count == 1 ? "set" : "sets")"
        if seconds >= 1 { text += " · " + DailyStats.duration(seconds) }
        return text
    }
}
