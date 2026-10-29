//
//  WidgetBoard.swift
//  Rep Crew (app and widget)
//
//  What the Home Screen widget knows about your leaderboards. His ask, 2026-10-29: "show the leaderboard
//  for like an option so you can choose which one to see" · "can widgets have swipe probably to show each
//  checked boxed leaderboards". A widget can't be swiped, so an arrow button steps through the ones checked.
//
//  REM: the app writes this into the shared app group every time your reps or a board change; the widget
//  reads it, then asks the crew's iCloud space for anyone's newer reps. Your own row always comes from the
//  app, so it's right the moment you log. Blocked people and anyone disqualified never show on it.
//  This file is in both targets (the "Rep Crew Shared" folder); keep it free of anything app-only.
//
//  REM: THE + BUTTONS. His asks, 2026-10-29: "can the widget update the users challenges?" · "it needs the
//  other too" (the leaderboard) · "can the widget tell the iphone app?" · "yes do both code it" (the + buttons
//  and a tap that opens the challenge). A tap is saved here as a Tap; the widget adds it to your row and sends
//  your new total to the crew's board right away, then nudges the app (a Darwin notification). The app adds
//  every waiting Tap to the challenge as a normal rep entry the next moment it runs, and removes it here.
//  Your challenges stay where they are, in the app's own iCloud-synced store: the same hand-off the Watch
//  already uses (WatchBridge.swift), so nothing about where his data lives had to move.
//

import Foundation

struct WidgetBoard: Codable, Identifiable, Equatable {
    /// One exercise, for the + buttons and to tell when the day's goal is met.
    struct Goal: Codable, Equatable {
        var order: Int
        var name: String
        var target: Int
        /// Logged today when the app saved this.
        var today: Int
        /// What one tap adds, and its button: "+10 push-ups".
        var quickAdd: Int
        var quickLabel: String
    }

    struct Row: Codable, Equatable {
        var id: String
        var name: String
        var reps: Int
        var complete: Bool
    }

    /// The challenge's crew ID.
    var id: String
    var title: String
    var startDate: Date
    var days: Int
    /// ExerciseUnit's raw value; reps when the exercises differ.
    var unit: String
    /// Today's goal across every exercise; nil when the exercises count in different units.
    var dailyTotal: Int?
    /// Your row, from this phone, and the challenge day it was written on.
    var me: Row
    var meDay: Int = 0
    var meStreak: Int = 0
    var goals: [Goal] = []
    /// Everyone else, as the app last loaded them, and the challenge day that was.
    var others: [Row] = []
    var othersDay: Int = 0
    /// People you blocked, and people disqualified from this challenge: never on the widget, even if
    /// iCloud has their reps.
    var blocked: Set<String> = []
    var disqualified: Set<String> = []
    var hidden: Set<String> { blocked.union(disqualified) }

    /// 1-based challenge day today, or nil outside it.
    func dayNumber(on date: Date = .now) -> Int? {
        let cal = Calendar.current
        guard let offset = cal.dateComponents([.day], from: cal.startOfDay(for: startDate), to: cal.startOfDay(for: date)).day,
              offset >= 0, offset < days else { return nil }
        return offset + 1
    }
}

/// A + tap on the widget, waiting for the app to add it.
struct WidgetTap: Codable, Identifiable, Equatable {
    var id = UUID()
    var crewID: String
    var goalOrder: Int
    var goalName: String
    var count: Int
    var at = Date.now
}

extension WidgetBoard {
    /// Taps waiting for the app, today's only.
    func pendingToday(_ taps: [WidgetTap]) -> [WidgetTap] {
        taps.filter { $0.crewID == id && Calendar.current.isDateInToday($0.at) }
    }

    /// Your row and goals with waiting taps added, as of today.
    func withTaps(_ taps: [WidgetTap]) -> (me: Row, goals: [Goal]) {
        let today = dayNumber()
        let fresh = meDay == today
        let pending = pendingToday(taps)
        let goals = self.goals.map { goal in
            var goal = goal
            if !fresh { goal.today = 0 }
            goal.today += pending.filter { $0.goalOrder == goal.order }.reduce(0) { $0 + $1.count }
            return goal
        }
        var me = fresh ? self.me : Row(id: self.me.id, name: "You", reps: 0, complete: false)
        me.reps += pending.reduce(0) { $0 + $1.count }
        if !goals.isEmpty && goals.allSatisfy({ $0.today >= $0.target }) { me.complete = true }
        return (me, goals)
    }
}

enum WidgetBoardStore {
    static let appGroup = "group.com.accountability.dailyrepcrew"
    static let kind = "RepCrewLeaderboard"
    private static let key = "widgetBoards"
    private static let tapsKey = "widgetTaps"
    /// Posted (Darwin, so it crosses processes) after a + tap, for the app if it's running.
    static let tapNotification = "com.accountability.dailyrepcrew.widgetTap"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func load() -> [WidgetBoard] {
        guard let data = defaults?.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([WidgetBoard].self, from: data)) ?? []
    }

    /// True when it changed, so the caller knows to refresh the widgets.
    @discardableResult
    static func save(_ boards: [WidgetBoard]) -> Bool {
        guard boards != load(), let data = try? JSONEncoder().encode(boards) else { return false }
        defaults?.set(data, forKey: key)
        return true
    }

    /// Your crew name, for a board row the widget starts before the app has saved one today.
    static var myName: String {
        get { defaults?.string(forKey: "myName") ?? "A crew member" }
        set { defaults?.set(newValue, forKey: "myName") }
    }

    static func taps() -> [WidgetTap] {
        guard let data = defaults?.data(forKey: tapsKey) else { return [] }
        return (try? JSONDecoder().decode([WidgetTap].self, from: data)) ?? []
    }

    static func addTap(_ tap: WidgetTap) {
        writeTaps(taps() + [tap])
    }

    static func removeTaps(_ ids: Set<UUID>) {
        writeTaps(taps().filter { !ids.contains($0.id) })
    }

    private static func writeTaps(_ taps: [WidgetTap]) {
        if let data = try? JSONEncoder().encode(taps) { defaults?.set(data, forKey: tapsKey) }
    }

    /// Which of the checked boards a widget is showing; keyed by the checked set, so two widgets with
    /// different boxes checked step on their own.
    static func index(for checked: [String]) -> Int { defaults?.integer(forKey: "widgetIndex." + checked.joined(separator: ",")) ?? 0 }
    static func setIndex(_ index: Int, for checked: [String]) { defaults?.set(index, forKey: "widgetIndex." + checked.joined(separator: ",")) }
}
