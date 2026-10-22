//
//  Models.swift
//  Rep Crew
//
//  A challenge is a set of daily rep goals that runs for a fixed number of days.
//  Reps are logged as entries through the day and counted against today's goal.
//

import Foundation
import SwiftData

@Model
final class Challenge {
    var title: String
    var startDate: Date
    var days: Int
    var createdAt: Date
    /// Shared by everyone's copy of the same challenge; set when it is first sent as an invite.
    var crewID: String = ""
    /// The crew leader's iCloud ID. Empty on the phone of whoever started the challenge.
    var leaderID: String = ""

    @Relationship(deleteRule: .cascade, inverse: \ExerciseGoal.challenge)
    var goals: [ExerciseGoal] = []

    init(title: String, startDate: Date, days: Int) {
        self.title = title
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.days = days
        self.createdAt = .now
    }

    var sortedGoals: [ExerciseGoal] { goals.sorted { $0.order < $1.order } }

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
    var isFinished: Bool { Calendar.current.startOfDay(for: .now) > lastDay }
    var isActive: Bool { dayNumber() != nil }

    /// Every goal met on `date`.
    func isComplete(on date: Date) -> Bool {
        !goals.isEmpty && goals.allSatisfy { $0.isMet(on: date) }
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

    /// Each day of the challenge, first to last.
    var allDays: [Date] {
        (0..<days).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: startDate) }
    }
}

@Model
final class ExerciseGoal {
    var name: String
    var dailyTarget: Int
    var order: Int
    var challenge: Challenge?

    @Relationship(deleteRule: .cascade, inverse: \RepEntry.goal)
    var entries: [RepEntry] = []

    init(name: String, dailyTarget: Int, order: Int) {
        self.name = name
        self.dailyTarget = dailyTarget
        self.order = order
    }

    func total(on date: Date) -> Int {
        let cal = Calendar.current
        return entries.filter { cal.isDate($0.loggedAt, inSameDayAs: date) }.reduce(0) { $0 + $1.count }
    }

    func remaining(on date: Date) -> Int { max(dailyTarget - total(on: date), 0) }
    func isMet(on date: Date) -> Bool { total(on: date) >= dailyTarget }

    /// The most recent entry logged on `date`, for undo.
    func lastEntry(on date: Date) -> RepEntry? {
        let cal = Calendar.current
        return entries.filter { cal.isDate($0.loggedAt, inSameDayAs: date) }.max { $0.loggedAt < $1.loggedAt }
    }
}

@Model
final class RepEntry {
    var count: Int
    var loggedAt: Date
    var goal: ExerciseGoal?

    init(count: Int, loggedAt: Date = .now) {
        self.count = count
        self.loggedAt = loggedAt
    }
}

/// Someone you have done a challenge with: whoever's invite you joined, and whoever joined yours.
@Model
final class CrewMember {
    var name: String
    var crewNumber: Int
    var addedAt: Date
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
