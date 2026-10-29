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

import Foundation

struct WidgetBoard: Codable, Identifiable, Equatable {
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

enum WidgetBoardStore {
    static let appGroup = "group.com.accountability.dailyrepcrew"
    static let kind = "RepCrewLeaderboard"
    private static let key = "widgetBoards"

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

    /// Which of the checked boards a widget is showing; keyed by the checked set, so two widgets with
    /// different boxes checked step on their own.
    static func index(for checked: [String]) -> Int { defaults?.integer(forKey: "widgetIndex." + checked.joined(separator: ",")) ?? 0 }
    static func setIndex(_ index: Int, for checked: [String]) { defaults?.set(index, forKey: "widgetIndex." + checked.joined(separator: ",")) }
}
