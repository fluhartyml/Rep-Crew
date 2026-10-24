//
//  HealthMatch.swift
//  Rep Crew
//
//  Match Health workouts to your Rep Crew exercises. His idea, 2026-10-23: "can they list in two
//  colums colum one is health app data and colum two is crew app data and they match colum a with
//  colum b" — locked the same day ("lock in 022g"), with Health READ of workouts approved.
//
//  Column A = your Health workouts, grouped by workout type + the app that recorded them.
//  Column B = your Rep Crew exercises. You pair them by hand. His word: "colum a is the data
//  source of truth" — Rep Crew counts what Health recorded and never edits, invents or estimates
//  time or calories. How a pairing counts is yours to pick ("if in doubt let the user decide"):
//  Off · Checks off the day · Minutes · Calories.
//
//  Workouts Rep Crew wrote itself (Start Set, the Watch app) are left out so a set isn't counted twice.
//

import HealthKit
import SwiftData
import SwiftUI

// MARK: - The member's choice

/// How matched workouts count toward their Rep Crew exercise.
enum HealthCount: String, CaseIterable, Identifiable {
    case off, checksDay, minutes, calories
    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: "Off"
        case .checksDay: "Checks off the day"
        case .minutes: "Minutes"
        case .calories: "Calories"
        }
    }
}

/// One pairing: Health workouts of one type from one app → one Rep Crew exercise. Kept in SwiftData
/// beside the goal it counts toward, so deleting the challenge deletes its pairings.
@Model
final class HealthMatch {
    /// "<workout type>|<source app's bundle ID>" — the Column A row.
    var workoutKey: String = ""
    var workoutName: String = ""
    var sourceName: String = ""
    var countRaw: String = HealthCount.off.rawValue
    var createdAt: Date = Date.now
    var goal: ExerciseGoal?

    init(workoutKey: String, workoutName: String, sourceName: String, count: HealthCount = .off) {
        self.workoutKey = workoutKey
        self.workoutName = workoutName
        self.sourceName = sourceName
        self.countRaw = count.rawValue
    }

    var count: HealthCount {
        get { HealthCount(rawValue: countRaw) ?? .off }
        set { countRaw = newValue.rawValue }
    }
}

// MARK: - What Health recorded

/// One workout as Health holds it. Seconds and calories are Health's own numbers, untouched.
struct HealthWorkout {
    let key: String
    let name: String
    let sourceName: String
    let start: Date
    let seconds: Double
    let kilocalories: Double
}

/// A Column A row: every workout of one type from one app.
struct HealthGroup: Identifiable {
    let id: String
    let name: String
    let sourceName: String
    let count: Int
    let last: Date
}

@Observable
final class HealthLibrary {
    static let shared = HealthLibrary()

    private(set) var all: [HealthWorkout] = []
    /// Workouts by the day they started, so a day's lookup stays quick on long challenges.
    private var byDay: [Date: [HealthWorkout]] = [:]
    private(set) var hasLoaded = false
    @ObservationIgnored private var lastLoad: Date?

    /// Column A, most recently used first.
    var groups: [HealthGroup] {
        Dictionary(grouping: all, by: \.key).compactMap { key, workouts in
            guard let first = workouts.first else { return nil }
            return HealthGroup(id: key, name: first.name, sourceName: first.sourceName, count: workouts.count,
                               last: workouts.map(\.start).max() ?? first.start)
        }
        .sorted { $0.last > $1.last }
    }

    func workouts(on date: Date) -> [HealthWorkout] {
        byDay[Calendar.current.startOfDay(for: date)] ?? []
    }

    /// Reads the last year of workouts. Asks for Health access the first time (one prompt covers
    /// saving sets and reading workouts). Health never says whether reading was allowed — a "no"
    /// just looks like no workouts — so an empty list explains where to turn it on.
    @MainActor func refresh(force: Bool = false) async {
        if !force, let lastLoad, Date.now.timeIntervalSince(lastLoad) < 30 { return }
        guard HKHealthStore.isHealthDataAvailable() else { hasLoaded = true; return }
        lastLoad = .now
        let store = HealthSets.store
        do {
            try await store.requestAuthorization(toShare: HealthSets.shareTypes, read: HealthSets.readTypes)
            let since = Calendar.current.date(byAdding: .day, value: -366, to: .now) ?? .distantPast
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.workout(HKQuery.predicateForSamples(withStart: since, end: nil))],
                sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)])
            let found = try await descriptor.result(for: store)
            let energy = HKQuantityType(.activeEnergyBurned)
            let workouts = found.filter { !Self.isRepCrews($0) }.map { workout in
                HealthWorkout(key: "\(workout.workoutActivityType.rawValue)|\(workout.sourceRevision.source.bundleIdentifier)",
                              name: workout.workoutActivityType.crewName,
                              sourceName: workout.sourceRevision.source.name,
                              start: workout.startDate,
                              seconds: workout.duration,
                              kilocalories: workout.statistics(for: energy)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
            }
            all = workouts
            byDay = Dictionary(grouping: workouts) { Calendar.current.startOfDay(for: $0.start) }
        } catch {
            // Health said no or isn't set up; leave what was read before.
        }
        hasLoaded = true
    }

    /// Start Set (this app) and the Watch app (bundle ID starts with this one), or anything branded Rep Crew.
    private static func isRepCrews(_ workout: HKWorkout) -> Bool {
        let mine = Bundle.main.bundleIdentifier ?? "com.accountability.dailyrepcrew"
        return workout.sourceRevision.source.bundleIdentifier.hasPrefix(mine)
            || (workout.metadata?[HKMetadataKeyWorkoutBrandName] as? String) == "Rep Crew"
    }
}

// MARK: - How a goal counts them

extension ExerciseGoal {
    private func healthWorkouts(on date: Date, counting: HealthCount) -> [HealthWorkout] {
        let keys = Set(allHealthMatches.filter { $0.count == counting }.map(\.workoutKey))
        guard !keys.isEmpty else { return [] }
        return HealthLibrary.shared.workouts(on: date).filter { keys.contains($0.key) }
    }

    /// A workout paired as "Checks off the day" was recorded on `date`.
    func checkedByHealth(on date: Date) -> Bool { !healthWorkouts(on: date, counting: .checksDay).isEmpty }

    /// Whole minutes Health recorded on `date` for pairings set to Minutes. Shown, never rounded up.
    func healthMinutes(on date: Date) -> Int {
        Int(healthWorkouts(on: date, counting: .minutes).reduce(0) { $0 + $1.seconds } / 60)
    }

    /// Calories Health recorded on `date` for pairings set to Calories. Zero when the app didn't record any.
    func healthCalories(on date: Date) -> Int {
        Int(healthWorkouts(on: date, counting: .calories).reduce(0) { $0 + $1.kilocalories })
    }
}

extension Challenge {
    var healthMinutesToday: Int { allGoals.reduce(0) { $0 + $1.healthMinutes(on: .now) } }
    var healthCaloriesToday: Int { allGoals.reduce(0) { $0 + $1.healthCalories(on: .now) } }
    /// Any pairing that counts, so screens don't ask for Health access for people who never matched.
    var countsHealth: Bool { allGoals.contains { $0.allHealthMatches.contains { $0.count != .off } } }
}

// MARK: - The matching screen

struct HealthMatchView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Challenge.startDate, order: .reverse) private var challenges: [Challenge]
    @Query(sort: \HealthMatch.createdAt) private var matches: [HealthMatch]
    @State private var library = HealthLibrary.shared
    @State private var newFrom: HealthGroup?

    /// Column B: exercises in challenges that haven't finished.
    private var goals: [ExerciseGoal] { challenges.filter { !$0.isFinished }.flatMap(\.sortedGoals) }

    var body: some View {
        List {
            Section {
                Text("Pair a workout from Health with one of your exercises, then pick how it counts. Rep Crew uses the time and calories Health recorded and never changes them. Your own Rep Crew sets aren't listed, so nothing counts twice.")
                    .font(AppFont.body)
            }

            Section {
                if !library.hasLoaded {
                    HStack { ProgressView(); Text("Reading Health…").font(AppFont.body) }
                } else if library.groups.isEmpty {
                    Text("No workouts from other apps in the last year. If you have some, open Settings, tap Health, then Data Access & Devices, then Daily Rep Crew Accountability, and turn on Workouts and Active Energy under Read.")
                        .font(AppFont.body)
                }
                ForEach(library.groups) { group in
                    MatchRow(group: group, match: matches.first { $0.workoutKey == group.id }, goals: goals,
                             onMatch: { pair(group, with: $0) }, onUnmatch: unmatch, onNew: { newFrom = group })
                }
            } header: {
                HStack {
                    Text("From Health")
                    Spacer()
                    Text("Rep Crew")
                }
                .font(AppFont.bodyBold).textCase(nil)
            } footer: {
                Text("Checks off the day: one matched workout completes that exercise for the day. Minutes or Calories: the day's total shows under your name on the leaderboard, which still ranks by reps. Off: matched, but not counted.")
                    .font(AppFont.body)
            }

            Section {
                if goals.isEmpty {
                    Text("No running or upcoming challenges yet.").font(AppFont.body)
                }
                ForEach(goals) { goal in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(goal.name).font(AppFont.bodyBold)
                        Text(goal.challenge?.title ?? "").font(AppFont.body).foregroundStyle(.secondary)
                        Text(goal.allHealthMatches.isEmpty
                             ? "No Health workouts matched"
                             : goal.allHealthMatches.map { "\($0.workoutName) from \($0.sourceName): \($0.count.label)" }.joined(separator: "\n"))
                            .font(AppFont.body)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Your Rep Crew exercises").font(AppFont.bodyBold).textCase(nil)
            }
        }
        .navigationTitle("Match Health Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .task { await library.refresh(force: true) }
        .refreshable { await library.refresh(force: true) }
        .sheet(item: $newFrom) { group in
            NewChallengeView(fromHealth: group.name) { goal in pair(group, with: goal) }
        }
    }

    /// One goal per Column A row; matching it again moves it. A new pairing starts Off — the member picks.
    private func pair(_ group: HealthGroup, with goal: ExerciseGoal) {
        if let existing = matches.first(where: { $0.workoutKey == group.id }) {
            existing.goal = goal
        } else {
            let match = HealthMatch(workoutKey: group.id, workoutName: group.name, sourceName: group.sourceName)
            context.insert(match)
            match.goal = goal
        }
        try? context.save()
    }

    private func unmatch(_ match: HealthMatch) {
        context.delete(match)
        try? context.save()
    }
}

/// Column A on the left, its Rep Crew exercise on the right, and how it counts under them.
private struct MatchRow: View {
    let group: HealthGroup
    let match: HealthMatch?
    let goals: [ExerciseGoal]
    let onMatch: (ExerciseGoal) -> Void
    let onUnmatch: (HealthMatch) -> Void
    let onNew: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name).font(AppFont.bodyBold)
                    Text(group.sourceName).font(AppFont.body).foregroundStyle(.secondary)
                    Text("\(group.count) \(group.count == 1 ? "workout" : "workouts")").font(AppFont.body).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right").font(AppFont.body).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Menu {
                    ForEach(goals) { goal in
                        Button("\(goal.name) · \(goal.challenge?.title ?? "")") { onMatch(goal) }
                    }
                    Button { onNew() } label: { Label("New Challenge", systemImage: "plus.circle") }
                    if let match {
                        Button(role: .destructive) { onUnmatch(match) } label: { Label("Unmatch", systemImage: "xmark.circle") }
                    }
                } label: {
                    Text(match?.goal?.name ?? "Match…")
                        .font(AppFont.bodyBold)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityLabel(match?.goal.map { "Matched to \($0.name). Change" } ?? "Match \(group.name) to an exercise")
            }
            if let match {
                Menu {
                    ForEach(HealthCount.allCases) { option in
                        Button { match.count = option; try? match.modelContext?.save() } label: {
                            if match.count == option { Label(option.label, systemImage: "checkmark") } else { Text(option.label) }
                        }
                    }
                } label: {
                    Text("Counts: \(match.count.label)").font(AppFont.bodyBold)
                }
            } else {
                // His word: "if the crew app doesnt have a workout that matches health apps column a
                // crew app can create a new crew challenge as needed".
                Button { onNew() } label: {
                    Label("New Challenge from \(group.name)", systemImage: "plus.circle").font(AppFont.bodyBold)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Workout names

extension HKWorkoutActivityType {
    /// Plain names for Column A. Health has no name API; uncommon types fall back to "Other workout".
    var crewName: String {
        switch self {
        case .running: "Running"
        case .walking: "Walking"
        case .hiking: "Hiking"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .rowing: "Rowing"
        case .elliptical: "Elliptical"
        case .stairClimbing: "Stair climbing"
        case .stairs: "Stairs"
        case .yoga: "Yoga"
        case .pilates: "Pilates"
        case .dance: "Dance"
        case .boxing: "Boxing"
        case .kickboxing: "Kickboxing"
        case .martialArts: "Martial arts"
        case .traditionalStrengthTraining: "Strength training"
        case .functionalStrengthTraining: "Functional strength training"
        case .highIntensityIntervalTraining: "Interval training"
        case .crossTraining: "Cross training"
        case .coreTraining: "Core training"
        case .flexibility: "Flexibility"
        case .cooldown: "Cooldown"
        case .mixedCardio: "Mixed cardio"
        case .jumpRope: "Jump rope"
        case .gymnastics: "Gymnastics"
        case .climbing: "Climbing"
        case .tennis: "Tennis"
        case .basketball: "Basketball"
        case .soccer: "Soccer"
        case .golf: "Golf"
        case .wheelchairRunPace: "Wheelchair, run pace"
        case .wheelchairWalkPace: "Wheelchair, walk pace"
        case .handCycling: "Hand cycling"
        case .other: "Other workout"
        default: "Other workout"
        }
    }
}
