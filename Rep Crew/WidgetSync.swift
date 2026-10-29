//
//  WidgetSync.swift
//  Rep Crew
//
//  Keeps the Home Screen widget's copy of your leaderboards (Rep Crew Shared/WidgetBoard.swift) current.
//  Your row is written whenever your reps change; everyone else's whenever a board on screen loads them.
//  The widget is told to redraw only when something actually changed.
//

import SwiftData
import SwiftUI
import WidgetKit

enum WidgetSync {
    /// Every challenge running today, with your row from this phone.
    @MainActor
    static func save(_ challenges: [Challenge]) {
        let old = Dictionary(WidgetBoardStore.load().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let myID = CrewCloud.shared.myID ?? "me"
        let boards = challenges.filter { $0.isActive && !$0.crewID.isEmpty }.map { challenge in
            var board = WidgetBoard(id: challenge.crewID, title: challenge.title, startDate: challenge.startDate,
                                    days: challenge.days, unit: challenge.sharedUnit.rawValue, dailyTotal: challenge.dailyTotal,
                                    me: .init(id: myID, name: "You", reps: challenge.repsToday,
                                              complete: challenge.isComplete(on: .now)))
            board.meDay = challenge.dayNumber() ?? 0
            board.meStreak = challenge.streak
            board.goals = challenge.sortedGoals.map { goal in
                let add = goal.unit.quickAdds.last ?? 10
                return .init(order: goal.order, name: goal.name, target: goal.dailyTarget, today: goal.total(on: .now),
                             quickAdd: add,
                             quickLabel: "+" + (goal.unit == .reps ? "\(add) \(goal.name.lowercased())" : goal.unit.label(add)))
            }
            if let previous = old[challenge.crewID] {
                board.others = previous.others
                board.othersDay = previous.othersDay
                board.disqualified = previous.disqualified
            }
            board.blocked = Blocklist.ids
            return board
        }
        let name = (UserDefaults.standard.string(forKey: CrewSettings.name) ?? "").trimmingCharacters(in: .whitespaces)
        WidgetBoardStore.myName = name.isEmpty ? "A crew member" : name
        if WidgetBoardStore.save(boards) { WidgetCenter.shared.reloadTimelines(ofKind: WidgetBoardStore.kind) }
    }

    /// Adds every + tap waiting from the widget to its challenge, as an ordinary rep entry, then clears it.
    /// A tap whose challenge is gone from this phone is dropped after a week.
    @MainActor
    static func applyTaps(_ challenges: [Challenge], context: ModelContext) {
        let taps = WidgetBoardStore.taps()
        guard !taps.isEmpty else { return }
        var done: Set<UUID> = []
        for tap in taps {
            let goals = challenges.first { $0.crewID == tap.crewID }?.sortedGoals ?? []
            guard let goal = goals.first(where: { $0.order == tap.goalOrder && $0.name == tap.goalName })
                    ?? goals.first(where: { $0.order == tap.goalOrder }) else {
                if tap.at < .now.addingTimeInterval(-7 * 86_400) { done.insert(tap.id) }
                continue
            }
            let entry = RepEntry(count: tap.count, loggedAt: tap.at)
            entry.goal = goal
            context.insert(entry)
            done.insert(tap.id)
        }
        guard !done.isEmpty else { return }
        try? context.save()
        WidgetBoardStore.removeTaps(done)
        save(challenges)
    }

    /// The widget's nudge after a + tap reaches the app as `widgetTapped`, if it's running.
    static func listen() {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in
            DispatchQueue.main.async { NotificationCenter.default.post(name: .widgetTapped, object: nil) }
        }, WidgetBoardStore.tapNotification as CFString, nil, .deliverImmediately)
    }

    /// A board just loaded from iCloud (BoardBlock): everyone's reps for `day`.
    @MainActor
    static func saveOthers(crewID: String, day: Int, standings: [CrewStanding]) {
        var boards = WidgetBoardStore.load()
        guard let i = boards.firstIndex(where: { $0.id == crewID }) else { return }
        let myID = boards[i].me.id
        boards[i].others = standings.filter { !$0.disqualified && $0.id != myID }
            .map { .init(id: $0.id, name: $0.name, reps: $0.reps, complete: $0.complete) }
        boards[i].othersDay = day
        boards[i].disqualified = Set(standings.filter(\.disqualified).map(\.id))
        if WidgetBoardStore.save(boards) { WidgetCenter.shared.reloadTimelines(ofKind: WidgetBoardStore.kind) }
    }
}

extension Notification.Name {
    static let widgetTapped = Notification.Name("widgetTapped")
}
