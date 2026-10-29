//
//  WidgetSync.swift
//  Rep Crew
//
//  Keeps the Home Screen widget's copy of your leaderboards (Rep Crew Shared/WidgetBoard.swift) current.
//  Your row is written whenever your reps change; everyone else's whenever a board on screen loads them.
//  The widget is told to redraw only when something actually changed.
//

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
            if let previous = old[challenge.crewID] {
                board.others = previous.others
                board.othersDay = previous.othersDay
                board.disqualified = previous.disqualified
            }
            board.blocked = Blocklist.ids
            return board
        }
        if WidgetBoardStore.save(boards) { WidgetCenter.shared.reloadTimelines(ofKind: WidgetBoardStore.kind) }
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
