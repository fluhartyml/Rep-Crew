//
//  TVBoardView.swift
//  Rep Crew TV
//
//  Three stages, his design 2026-10-27:
//    "the announcements then your weekly routine in a flat list then the challenge leader boards. i think there
//    could be a press center button pause between the announcements the weekly routines and then the challenges"
//    · boards: "left and right navigations i would like treating swipe left and swipe right"
//    · announcements: "it should show the last announcement if any and 'no new announcements' so the user knows
//      theres no error like 'this page left blank'".
//
//  REM: read-only. Nothing here logs reps or sends a message. Menu steps back a stage; on the first stage it
//  leaves the app, as tvOS expects.
//  REM: tvOS text is 29 pt minimum (house rule), set as sizes, never .body/.caption.
//

import SwiftUI

private enum TVFont {
    static let title = Font.system(size: 64, weight: .bold)
    static let heading = Font.system(size: 44, weight: .semibold)
    static let body = Font.system(size: 38)
    static let small = Font.system(size: 29)
}

struct TVBoardView: View {
    private enum Stage { case announcements, week, boards }

    @State private var cloud = TVCloud.shared
    @State private var stage = Stage.announcements
    @State private var boardIndex = 0
    @State private var standings: [TVStanding] = []
    /// The new announcements as they were when the board opened, so pressing on marks exactly those seen.
    @State private var shownNew: [TVAnnouncement]?
    @FocusState private var focused: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            if let name = cloud.viewAsName {
                Label("Viewing as \(name), from your iPhone", systemImage: "eye")
                    .font(TVFont.small).foregroundStyle(.orange)
            }
            Group {
                if let problem = cloud.problem {
                    message(problem, icon: "icloud.slash")
                } else if !cloud.loaded {
                    ProgressView("Loading your crew…").font(TVFont.body)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch stage {
                    case .announcements: announcementsStage
                    case .week: weekStage
                    case .boards: boardsStage
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .padding(.horizontal, 90)
        .padding(.vertical, 60)
        .contentShape(Rectangle())
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onTapGesture { pressCenter() }
        .onMoveCommand { direction in
            guard stage == .boards, !cloud.challenges.isEmpty else { return }
            let count = cloud.challenges.count
            switch direction {
            case .left: boardIndex = (boardIndex - 1 + count) % count
            case .right: boardIndex = (boardIndex + 1) % count
            default: break
            }
        }
        .onExitCommand(perform: stage == .announcements ? nil : { stepBack() })
        .task(id: scenePhase) {
            // Stays on screen like a scoreboard: everything refreshes every minute while the app is open.
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await cloud.refresh()
                if shownNew == nil { shownNew = Array(newAnnouncements.prefix(4)) }
                boardIndex = min(boardIndex, max(cloud.challenges.count - 1, 0))
                await loadBoard()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .task(id: boardKey) { standings = []; await loadBoard() }
    }

    // MARK: Stages

    private var newAnnouncements: [TVAnnouncement] {
        let seen = TVSeen.ids
        return cloud.announcements.filter { !seen.contains($0.id) }
    }

    @ViewBuilder private var announcementsStage: some View {
        VStack(alignment: .leading, spacing: 36) {
            Label("Announcements", systemImage: "megaphone.fill").font(TVFont.title)
            let fresh = shownNew ?? []
            if fresh.isEmpty {
                Text("No new announcements").font(TVFont.heading)
                if let last = cloud.announcements.first {
                    Text("The last one:").font(TVFont.small).foregroundStyle(.secondary)
                    announcement(last)
                } else {
                    Text("Your crews haven't posted one yet.").font(TVFont.body).foregroundStyle(.secondary)
                }
            } else {
                ForEach(fresh) { announcement($0) }
                let more = newAnnouncements.count - fresh.count
                if more > 0 {
                    Text("\(more) more new in the Inbox on your iPhone.").font(TVFont.small).foregroundStyle(.secondary)
                }
            }
            Spacer()
            hint("Press the center of the remote for your week")
        }
    }

    private func announcement(_ item: TVAnnouncement) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(item.senderName) · \(item.crewTitle) · \(item.sentAt.formatted(.relative(presentation: .named)))")
                .font(TVFont.small).foregroundStyle(.secondary)
            Text(item.text).font(TVFont.body).lineLimit(3)
        }
    }

    @ViewBuilder private var weekStage: some View {
        VStack(alignment: .leading, spacing: 28) {
            Label("Your Week", systemImage: "calendar").font(TVFont.title)
            if let week = cloud.week {
                if week.isEmpty {
                    Text("No challenges on your week.").font(TVFont.body)
                } else {
                    weekList(week)
                }
            } else {
                Text("Your week hasn't reached this Apple TV yet. Open Rep Crew on your iPhone to send it.")
                    .font(TVFont.body).foregroundStyle(.secondary)
            }
            Spacer()
            hint("Press the center of the remote for the challenge boards")
        }
    }

    /// Sunday to Saturday, one line each. A challenge not on your week counts every day, so it gets its own line.
    @ViewBuilder private func weekList(_ week: [TVWeekEntry]) -> some View {
        let everyDay = week.filter(\.weekdays.isEmpty)
        let today = Calendar.current.component(.weekday, from: .now)
        VStack(alignment: .leading, spacing: 14) {
            if !everyDay.isEmpty {
                weekRow("Every day", names: everyDay.map(\.title), isToday: false)
            }
            ForEach(1...7, id: \.self) { day in
                let names = week.filter { $0.weekdays.contains(day) }.map(\.title)
                weekRow(Calendar.current.weekdaySymbols[day - 1],
                        names: names.isEmpty && everyDay.isEmpty ? ["Rest day"] : names, isToday: day == today)
            }
        }
    }

    private func weekRow(_ day: String, names: [String], isToday: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 30) {
            Text(isToday ? "\(day) · today" : day).font(TVFont.body.weight(isToday ? .bold : .regular))
                .frame(width: 420, alignment: .leading)
            Text(names.isEmpty ? "—" : names.joined(separator: ", ")).font(TVFont.body)
                .foregroundStyle(names == ["Rest day"] ? .secondary : .primary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 20)
        .background(isToday ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder private var boardsStage: some View {
        if cloud.challenges.isEmpty {
            message("No challenges are on today.", icon: "figure.strengthtraining.traditional")
        } else {
            let challenge = cloud.challenges[min(boardIndex, cloud.challenges.count - 1)]
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    Text(challenge.title).font(TVFont.title).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer()
                    if let day = challenge.dayNumber {
                        Text("Day \(day) of \(challenge.days)").font(TVFont.heading)
                    }
                }
                Text("\(challenge.goals) a day · \(challenge.dateRange)").font(TVFont.small).foregroundStyle(.secondary)
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(standings) { standingRow($0) }
                }
                Spacer()
                if cloud.challenges.count > 1 {
                    HStack(spacing: 18) {
                        Image(systemName: "chevron.left")
                        Text("\(boardIndex + 1) of \(cloud.challenges.count)")
                        Image(systemName: "chevron.right")
                    }
                    .font(TVFont.small).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// No place numbers — his word, "i would imply the ranking and not be explicit".
    private func standingRow(_ row: TVStanding) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 28) {
            Image(systemName: row.complete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(row.complete ? .green : .secondary)
            Text(row.name).frame(width: 520, alignment: .leading).lineLimit(1)
            if row.disqualified {
                Text("Disqualified").foregroundStyle(.secondary)
            } else {
                Text("\(row.reps.formatted()) reps").frame(width: 300, alignment: .trailing).monospacedDigit()
                Text(row.streak > 0 ? "🔥 \(row.streak)" : "").frame(width: 140, alignment: .leading)
                if row.minutes > 0 || row.calories > 0 {
                    Text("\(row.minutes) min · \(row.calories) cal").font(TVFont.small).foregroundStyle(.secondary)
                }
            }
        }
        .font(TVFont.body)
    }

    // MARK: Pieces

    private func message(_ text: String, icon: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: icon).font(.system(size: 90))
            Text(text).font(TVFont.body).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(TVFont.small).foregroundStyle(.secondary).frame(maxWidth: .infinity)
    }

    private var footer: some View {
        Text("Build \(BuildStamp.number) · \(BuildStamp.commit)").font(TVFont.small).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: Remote

    private func pressCenter() {
        switch stage {
        case .announcements:
            TVSeen.add((shownNew ?? []).map(\.id))
            stage = .week
        case .week:
            stage = .boards
        case .boards:
            break
        }
    }

    private func stepBack() {
        switch stage {
        case .boards: stage = .week
        case .week: stage = .announcements
        case .announcements: break
        }
    }

    private var boardKey: String {
        guard stage == .boards, boardIndex < cloud.challenges.count else { return "" }
        return cloud.challenges[boardIndex].id
    }

    private func loadBoard() async {
        guard stage == .boards, boardIndex < cloud.challenges.count else { return }
        let challenge = cloud.challenges[boardIndex]
        let rows = await cloud.standings(challenge)
        if boardKey == challenge.id { standings = rows }
    }
}

/// Announcements this Apple TV user has already been shown. With Runs as Current User each person on the
/// Apple TV keeps their own.
enum TVSeen {
    private static let key = "seenAnnouncements"
    static var ids: Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
    static func add(_ new: [String]) {
        guard !new.isEmpty else { return }
        // Keeps the newest 500 so the list can't grow forever.
        let all = (UserDefaults.standard.stringArray(forKey: key) ?? []) + new.filter { !ids.contains($0) }
        UserDefaults.standard.set(Array(all.suffix(500)), forKey: key)
    }
}
