//
//  LeaderboardWidget.swift
//  Rep Crew Widget
//
//  The Home Screen leaderboard. His asks, 2026-10-29: "show the leaderboard for like an option so you can
//  choose which one to see" · "can widgets have swipe probably to show each checked boxed leaderboards" ·
//  "i guess smart stacks are what im thinking about for swiping".
//
//  REM: you check leaderboards when you edit the widget; the arrow steps through them. Stack several widgets
//  in a Smart Stack to swipe between them instead. Each row says what that person has to go today, the
//  same words as the app's board (Leaderboard.swift), ordered by today's reps with no place labels — his
//  rule: "i would imply the ranking and not be explicit."
//  iPhone decides how often a widget refreshes (about every 15–30 minutes), so other people's numbers
//  can lag; yours is right as soon as the app saves it.
//

import AppIntents
import CloudKit
import SwiftUI
import WidgetKit

@main
struct RepCrewWidgets: WidgetBundle {
    var body: some Widget { LeaderboardWidget() }
}

struct LeaderboardWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetBoardStore.kind, intent: PickBoardsIntent.self, provider: BoardProvider()) {
            BoardWidgetView(entry: $0)
        }
        .configurationDisplayName("Leaderboard")
        .description("Today's crew board and what everyone has to go. Choose which leaderboards it shows.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Choosing leaderboards

struct BoardEntity: AppEntity {
    var id: String
    var title: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Leaderboard"
    static var defaultQuery = BoardQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct BoardQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [BoardEntity] {
        all().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [BoardEntity] { all() }
    func defaultResult() async -> BoardEntity? { all().first }

    /// The challenges running today, as the app last saved them.
    private func all() -> [BoardEntity] {
        WidgetBoardStore.load().map { BoardEntity(id: $0.id, title: $0.title) }
    }
}

struct PickBoardsIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Leaderboards"
    static var description = IntentDescription("Check the leaderboards this widget shows. The arrow steps through them.")

    @Parameter(title: "Leaderboards")
    var boards: [BoardEntity]?
}

/// The arrow: shows the next checked leaderboard.
struct NextBoardIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Leaderboard"
    static var isDiscoverable = false

    @Parameter(title: "Checked")
    var checked: [String]

    init() { checked = [] }
    init(checked: [String]) { self.checked = checked }

    func perform() async throws -> some IntentResult {
        WidgetBoardStore.setIndex(WidgetBoardStore.index(for: checked) + 1, for: checked)
        return .result()
    }
}

// MARK: - Timeline

struct BoardEntry: TimelineEntry {
    let date: Date
    var board: WidgetBoard?
    var rows: [WidgetBoard.Row] = []
    /// The checked leaderboards' IDs, for the arrow; one or none hides it.
    var checked: [String] = []
}

extension WidgetBoard.Row: Identifiable {}

struct BoardProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BoardEntry {
        let me = WidgetBoard.Row(id: "me", name: "You", reps: 60, complete: false)
        let board = WidgetBoard(id: "sample", title: "100 Push-ups a Day", startDate: .now, days: 30, unit: "reps",
                                dailyTotal: 100, me: me)
        return BoardEntry(date: .now, board: board,
                          rows: [.init(id: "a", name: "Crew member", reps: 100, complete: true), me])
    }

    func snapshot(for configuration: PickBoardsIntent, in context: Context) async -> BoardEntry {
        await entry(for: configuration, fetch: !context.isPreview)
    }

    func timeline(for configuration: PickBoardsIntent, in context: Context) async -> Timeline<BoardEntry> {
        let entry = await entry(for: configuration, fetch: true)
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60)))
    }

    private func entry(for configuration: PickBoardsIntent, fetch: Bool) async -> BoardEntry {
        let all = WidgetBoardStore.load().filter { $0.dayNumber() != nil }
        // Nothing checked yet shows the first board, so a new widget isn't blank.
        var boards = (configuration.boards ?? []).compactMap { picked in all.first { $0.id == picked.id } }
        if boards.isEmpty { boards = Array(all.prefix(1)) }
        guard !boards.isEmpty else { return BoardEntry(date: .now) }
        let checked = boards.map(\.id)
        let board = boards[WidgetBoardStore.index(for: checked) % boards.count]
        return BoardEntry(date: .now, board: board, rows: await rows(for: board, fetch: fetch), checked: checked)
    }

    /// The app's last copy of the board, freshened from the crew's iCloud space, with your row from the app.
    private func rows(for board: WidgetBoard, fetch: Bool) async -> [WidgetBoard.Row] {
        guard let day = board.dayNumber() else { return [] }
        var byID: [String: WidgetBoard.Row] = [:]
        for row in board.others {
            // A board saved on an earlier day keeps its people, at zero.
            byID[row.id] = board.othersDay == day ? row : .init(id: row.id, name: row.name, reps: 0, complete: false)
        }
        if fetch {
            let db = CKContainer(identifier: "iCloud.com.accountability.dailyrepcrew").publicCloudDatabase
            let query = CKQuery(recordType: "Progress",
                                predicate: NSPredicate(format: "crewID == %@ AND dayNumber == %d", board.id, day))
            if let (results, _) = try? await db.records(matching: query, desiredKeys: ["memberID", "name", "reps", "complete"]) {
                for record in results.compactMap({ try? $0.1.get() }) {
                    guard let id = record["memberID"] as? String else { continue }
                    var row = byID[id] ?? .init(id: id, name: "Crew member", reps: 0, complete: false)
                    if let name = record["name"] as? String, !name.isEmpty { row.name = name }
                    row.reps = record["reps"] as? Int ?? 0
                    row.complete = (record["complete"] as? Int ?? 0) == 1
                    byID[id] = row
                }
            }
        }
        byID[board.me.id] = nil
        let me = board.meDay == day ? board.me : .init(id: board.me.id, name: "You", reps: 0, complete: false)
        return (byID.values.filter { !board.hidden.contains($0.id) } + [me])
            .sorted { $0.reps != $1.reps ? $0.reps > $1.reps : $0.name < $1.name }
    }
}

// MARK: - Views

struct BoardWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BoardEntry

    private static let regular = Font.system(size: 18)
    private static let bold = Font.system(size: 18, weight: .semibold)

    var body: some View {
        Group {
            if let board = entry.board {
                content(board)
            } else {
                Text("Join a challenge in Rep Crew to see its leaderboard here.").font(Self.regular)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func content(_ board: WidgetBoard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(board.title).font(Self.bold).lineLimit(1)
                Spacer(minLength: 0)
                if entry.checked.count > 1 {
                    Button(intent: NextBoardIntent(checked: entry.checked)) {
                        Image(systemName: "chevron.right.circle.fill").font(.system(size: 24))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Next leaderboard")
                }
            }
            ForEach(entry.rows.prefix(limit)) { row in
                if family == .systemSmall {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.name).font(row.id == board.me.id ? Self.bold : Self.regular).lineLimit(1)
                        Text(toGo(row, board)).font(Self.regular).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.9)
                    }
                } else {
                    HStack {
                        Text(row.name).font(row.id == board.me.id ? Self.bold : Self.regular).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(toGo(row, board)).font(Self.regular).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var limit: Int {
        switch family {
        case .systemSmall: 2
        case .systemLarge: 8
        default: 3
        }
    }

    /// "30 reps to go", "Goal met", or today's reps when the exercises count in different units.
    private func toGo(_ row: WidgetBoard.Row, _ board: WidgetBoard) -> String {
        if row.complete { return "Goal met" }
        guard let target = board.dailyTotal, target > 0 else { return label(row.reps, board.unit) }
        let left = target - row.reps
        return left > 0 ? "\(label(left, board.unit)) to go" : "Not done yet"
    }

    /// As ExerciseUnit.label in the app: miles are stored in tenths.
    private func label(_ count: Int, _ unit: String) -> String {
        let word = unit.isEmpty ? "reps" : unit
        let scale = word == "miles" ? 10 : 1
        let amount = scale > 1 ? (Double(count) / Double(scale)).formatted(.number.precision(.fractionLength(0...1))) : count.formatted()
        return "\(amount) \(count == scale ? String(word.dropLast()) : word)"
    }
}
