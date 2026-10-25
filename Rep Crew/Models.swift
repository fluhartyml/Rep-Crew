//
//  Models.swift
//  Rep Crew
//
//  A challenge is a set of daily rep goals that runs for a fixed number of days.
//  Reps are logged as entries through the day and counted against today's goal.
//

import Foundation
import SwiftData

// REM: Every stored value has a default and every to-many relationship is optional. That is what
// SwiftData needs to keep this store in the person's own iCloud (private database), so deleting the
// app or changing phones doesn't lose their challenges (his word 2026-10-24: "if a pier deleted
// their app it doesnt effect the rest of the crew"). Build 12 synced without these and opened empty.
@Model
final class Challenge {
    var title: String = ""
    var startDate: Date = Date.now
    var days: Int = 1
    var createdAt: Date = Date.now
    /// Shared by everyone's copy of the same challenge; set when it is first sent as an invite.
    var crewID: String = ""
    /// The crew leader's iCloud ID. Empty on the phone of whoever started the challenge.
    var leaderID: String = ""
    /// Public challenges are listed for everyone with the app; private ones only reach the crew you check.
    var isPublic: Bool = true
    /// Rebuilt from the crew's shared space (CrewRestore.swift) rather than made on a phone of yours.
    /// When your own iCloud copy arrives too, it wins and this one is removed.
    var restoredFromCrew: Bool = false
    /// The challenge day it was rebuilt on, and the reps the crew's board already had for you that
    /// day. Until you pass them, this phone doesn't post a lower number over them.
    var restoredDay: Int = 0
    var restoredRepsToday: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \ExerciseGoal.challenge)
    var goals: [ExerciseGoal]? = []
    /// The goals, never nil. The stored names stay the same so an existing store keeps its data.
    var allGoals: [ExerciseGoal] { goals ?? [] }

    init(title: String, startDate: Date, days: Int) {
        self.title = title
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.days = days
        self.createdAt = .now
    }

    var sortedGoals: [ExerciseGoal] { allGoals.sorted { $0.order < $1.order } }

    /// The last day of the challenge, at midnight.
    var lastDay: Date {
        Calendar.current.date(byAdding: .day, value: days - 1, to: startDate) ?? startDate
    }

    /// 1-based day number for `date`, or nil if the date falls outside the challenge.
    func dayNumber(on date: Date = .now) -> Int? {
        let day = Calendar.current.startOfDay(for: date)
        guard let offset = Calendar.current.dateComponents([.day], from: startDate, to: day).day,
              offset >= 0, offset < days else { return nil }
        return offset + 1
    }

    var hasStarted: Bool { Calendar.current.startOfDay(for: .now) >= startDate }
    /// The crew leader or a coach closed it before its last day (ChallengeClose.swift).
    var isClosed: Bool { ChallengeClosure.isClosed(crewID) }
    var isFinished: Bool { isClosed || Calendar.current.startOfDay(for: .now) > lastDay }
    var isActive: Bool { !isClosed && dayNumber() != nil }

    /// Every goal met on `date`.
    func isComplete(on date: Date) -> Bool {
        !allGoals.isEmpty && allGoals.allSatisfy { $0.isMet(on: date) }
    }

    /// Days from the start through today (or the last day) where every goal was met.
    var completedDays: Int {
        let cal = Calendar.current
        let end = min(cal.startOfDay(for: .now), lastDay)
        guard end >= startDate else { return 0 }
        var count = 0
        var day = startDate
        while day <= end {
            if isComplete(on: day) { count += 1 }
            day = cal.date(byAdding: .day, value: 1, to: day) ?? end.addingTimeInterval(86_400)
        }
        return count
    }

    /// The last time you logged reps on any of its exercises.
    var lastLogged: Date? { allGoals.flatMap(\.allEntries).map(\.loggedAt).max() }

    /// "Oct 25 – Nov 7", so a new challenge and an old one look different on the list.
    var dateRange: String { Challenge.dateRange(from: startDate, to: lastDay) }

    static func dateRange(from start: Date, to end: Date) -> String {
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return "\(start.formatted(style)) – \(end.formatted(style))"
    }

    /// "active 2 hours ago", or "no reps yet".
    static func activityText(_ date: Date?) -> String {
        guard let date else { return "no reps yet" }
        return "active \(date.formatted(.relative(presentation: .named)))"
    }

    /// Each day of the challenge, first to last.
    var allDays: [Date] {
        (0..<days).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: startDate) }
    }
}

@Model
final class ExerciseGoal {
    var name: String = ""
    var dailyTarget: Int = 0
    var order: Int = 0
    var challenge: Challenge?

    @Relationship(deleteRule: .cascade, inverse: \RepEntry.goal)
    var entries: [RepEntry]? = []
    var allEntries: [RepEntry] { entries ?? [] }

    /// Health workouts paired with this exercise on Match Health Workouts (HealthMatch.swift).
    @Relationship(deleteRule: .cascade, inverse: \HealthMatch.goal)
    var healthMatches: [HealthMatch]? = []
    var allHealthMatches: [HealthMatch] { healthMatches ?? [] }

    init(name: String, dailyTarget: Int, order: Int) {
        self.name = name
        self.dailyTarget = dailyTarget
        self.order = order
    }

    func total(on date: Date) -> Int {
        let cal = Calendar.current
        return allEntries.filter { cal.isDate($0.loggedAt, inSameDayAs: date) }.reduce(0) { $0 + $1.count }
    }

    func remaining(on date: Date) -> Int { max(dailyTarget - total(on: date), 0) }
    /// Reps reached the target, or a Health workout paired as "Checks off the day" was recorded that day.
    func isMet(on date: Date) -> Bool { total(on: date) >= dailyTarget || checkedByHealth(on: date) }

    /// The most recent entry logged on `date`, for undo.
    func lastEntry(on date: Date) -> RepEntry? {
        let cal = Calendar.current
        return allEntries.filter { cal.isDate($0.loggedAt, inSameDayAs: date) }.max { $0.loggedAt < $1.loggedAt }
    }
}

@Model
final class RepEntry {
    var count: Int = 0
    var loggedAt: Date = Date.now
    /// When a timed set started (Start Set or Start Routine). Nil for reps added with the + buttons,
    /// and for sets timed before build 92; their time is read back from Health (DailyStats.swift).
    var startedAt: Date? = nil
    var goal: ExerciseGoal?

    init(count: Int, loggedAt: Date = .now) {
        self.count = count
        self.loggedAt = loggedAt
    }
}

/// Someone you have done a challenge with: whoever's invite you joined, and whoever joined yours.
@Model
final class CrewMember {
    var name: String = ""
    var crewNumber: Int = 0
    var addedAt: Date = Date.now
    /// Their iCloud ID. With it, they get a check box when you start a new challenge.
    var cloudID: String = ""

    init(name: String, crewNumber: Int, cloudID: String = "") {
        self.name = name
        self.crewNumber = crewNumber
        self.addedAt = .now
        self.cloudID = cloudID
    }
}

/// Bodyweight exercises offered when building a challenge. Any name can be typed instead.
enum ExercisePreset {
    static let names = ["Push-ups", "Pull-ups", "Air squats", "Sit-ups", "Jumping jacks", "Burpees", "Lunges", "Plank (seconds)"]
}
