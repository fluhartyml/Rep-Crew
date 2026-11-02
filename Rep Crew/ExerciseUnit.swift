//
//  ExerciseUnit.swift
//  Rep Crew
//
//  What one count of an exercise is: reps, steps, minutes, miles, laps or skips.
//  REM: SKIPS — Smitty's idea, by his word 2026-11-01: the "i didn't eat. . . " challenge, "it can be infinite in
//  possibilities for i didnt eat" · "yes build the i didn't eat challenge". One skip = one time you passed on
//  something. Each thing is its own exercise named "I didn't eat …", so a challenge can hold as many as you add.
//  Uses the existing unitName field: no new CloudKit field, nothing to deploy. Older builds read "skips" as reps.
//  REM: OUNCES — Smitty's water challenge (his word 2026-11-01: "yes build the water challenge"; from the call:
//  "drink 8 ounces of water", counted from the Health app). +8 a glass, +16 a bottle; From Health brings in
//  today's water from Health (only what someone logs there; the Watch doesn't measure water).
//  REM: CALORIES SKIPPED — his word 2026-11-01: "log what you didnt eat with optional calori count where it totals at the
//  end of the day so you can race to cut junkfood calories" · "yes build the calorie race". The count IS the calories,
//  so the goal, the day's total and the crew's leaderboard race in calories. "I didn't eat…" items use it.
//  His ask, 2026-10-25, after "what is a rep in this set? is it steps?" → a unit picked per exercise,
//  and "or laps if they[re] on a track or in a pool for a swim challenge".
//
//  REM: every count in the app stays a whole number (RepEntry.count, the crew board's "reps" field), so
//  miles are kept in TENTHS: 2.5 miles is stored as 25. Only this file turns a count into words or back,
//  so nothing else needs to know. An exercise saved before units existed has none and reads as reps.
//  Steps and miles are filled in from Health after Finish Set (HealthSets.measured), minutes from the
//  set's own clock; laps and reps are typed, as before.
//

import HealthKit

enum ExerciseUnit: String, CaseIterable, Identifiable, Codable {
    case reps, steps, minutes, miles, laps, skips, calories, ounces

    var id: String { rawValue }

    /// The stored value: an empty or unknown one is reps, so older exercises keep working.
    init(stored: String?) { self = ExerciseUnit(rawValue: stored ?? "") ?? .reps }

    var title: String { self == .calories ? "Calories skipped" : rawValue.capitalized }

    /// Stored counts per one shown unit.
    var scale: Int { self == .miles ? 10 : 1 }

    /// The number alone: "4,200", "2.5".
    func amount(_ count: Int) -> String {
        guard scale > 1 else { return count.formatted() }
        return (Double(count) / Double(scale)).formatted(.number.precision(.fractionLength(0...1)))
    }

    /// The number with its unit: "4,200 steps", "1 lap", "2.5 miles".
    func label(_ count: Int) -> String {
        let one = count == scale
        let word: String = switch self {
        case .reps: one ? "rep" : "reps"
        case .steps: one ? "step" : "steps"
        case .minutes: one ? "minute" : "minutes"
        case .miles: one ? "mile" : "miles"
        case .laps: one ? "lap" : "laps"
        case .skips: one ? "skip" : "skips"
        case .calories: one ? "calorie skipped" : "calories skipped"
        case .ounces: one ? "ounce" : "ounces"
        }
        return "\(amount(count)) \(word)"
    }

    /// A typed number back to a stored count; nil when it isn't one. Miles take a decimal.
    func count(from text: String) -> Int? {
        let cleaned = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value > 0 else { return nil }
        let count = Int((value * Double(scale)).rounded())
        return count > 0 ? count : nil
    }

    /// The goal in words for invites and messages: "100 push-ups", "10,000 steps of walking".
    func goalText(_ target: Int, name: String) -> String {
        switch self {
        case .reps: "\(target.formatted()) \(name.lowercased())"
        case .skips, .calories: "\(name) (\(label(target)) a day)"
        default: "\(label(target)) of \(name.lowercased())"
        }
    }

    /// The quick-add buttons on a goal, before Other.
    var quickAdds: [Int] {
        switch self {
        case .reps, .minutes: [5, 10]
        case .steps: [500, 1000]
        case .miles: [5, 10]   // half a mile, one mile
        case .laps: [1, 5]
        case .skips, .calories: []   // logged through the "I didn't eat…" box, never a blind +
        case .ounces: [8, 16]   // a glass, a bottle
        }
    }

    /// The daily goal's stepper: its range and step at a given goal.
    var targetRange: ClosedRange<Int> { self == .steps ? 100...100_000 : 1...10_000 }
    func targetStep(at target: Int) -> Int {
        switch self {
        case .steps: target < 2000 ? 100 : 500
        case .miles: 1
        // REM: his word 2026-11-01: "or by ten because some calorie smart snacks are 90 or 150" · "yes start at 100 step by 10".
        case .calories: 10
        case .ounces: 8
        default: target < 20 ? 1 : (target < 100 ? 5 : 10)
        }
    }

    /// A fresh exercise's goal in this unit.
    var startingTarget: Int {
        switch self {
        case .reps: 50
        case .steps: 10_000
        case .minutes: 30
        case .miles: 20
        case .laps: 10
        case .skips: 1
        case .calories: 100   // his word 2026-11-01: "yes start at 100" (500 was too large)
        case .ounces: 64   // eight 8-ounce glasses
        }
    }

    /// Counted by tapping, never timed: no Start Set.
    var isTimed: Bool { !logsFood && self != .ounces }
    /// Logged through the "I didn't eat…" box (FoodLog.swift): skips and calories skipped.
    var logsFood: Bool { self == .skips || self == .calories }

    /// Typed with a decimal point.
    var takesDecimal: Bool { scale > 1 }
}

extension ExerciseGoal {
    var unit: ExerciseUnit {
        get { ExerciseUnit(stored: unitName) }
        set { unitName = newValue.rawValue }
    }
}

extension Challenge {
    /// The one unit every exercise shares, for totals across them; reps when they differ.
    var sharedUnit: ExerciseUnit {
        let units = Set(allGoals.map(\.unit))
        return units.count == 1 ? units.first ?? .reps : .reps
    }
}

extension Invite.Goal {
    var exerciseUnit: ExerciseUnit { ExerciseUnit(stored: unit) }
}

extension Invite.ChallengeInfo {
    /// As Challenge.sharedUnit, for a challenge you only see listed.
    var sharedUnit: ExerciseUnit {
        let units = Set(goals.map(\.exerciseUnit))
        return units.count == 1 ? units.first ?? .reps : .reps
    }
}

extension HealthSets {
    /// Steps or distance Health counted between a set's start and end, as a stored count; nil when there's
    /// nothing to read, the unit isn't measured, or you said no. Never a guess.
    static func measured(_ unit: ExerciseUnit, exercise: String, start: Date, end: Date) async -> Int? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let type: HKQuantityType
        let hkUnit: HKUnit
        switch unit {
        case .steps:
            type = HKQuantityType(.stepCount); hkUnit = .count()
        case .miles:
            switch activityType(for: exercise) {
            case .cycling: type = HKQuantityType(.distanceCycling)
            case .swimming: type = HKQuantityType(.distanceSwimming)
            default: type = HKQuantityType(.distanceWalkingRunning)
            }
            hkUnit = .mile()
        default:
            return nil
        }
        try? await store.requestAuthorization(toShare: shareTypes, read: readTypes)
        let window = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: type, predicate: window), options: .cumulativeSum)
        guard let value = try? await descriptor.result(for: store)?.sumQuantity()?.doubleValue(for: hkUnit) else { return nil }
        let count = Int((value * Double(unit.scale)).rounded())
        return count > 0 ? count : nil
    }
}

extension HealthSets {
    /// Today's water in Health, in whole ounces; nil when there's none, Health isn't here, or you said no.
    static func waterToday() async -> Int? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        try? await store.requestAuthorization(toShare: shareTypes, read: readTypes)
        let today = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: .now), end: .now)
        let descriptor = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: HKQuantityType(.dietaryWater), predicate: today),
                                                     options: .cumulativeSum)
        guard let value = try? await descriptor.result(for: store)?.sumQuantity()?.doubleValue(for: .fluidOunceUS()) else { return nil }
        let ounces = Int(value.rounded())
        return ounces > 0 ? ounces : nil
    }
}
