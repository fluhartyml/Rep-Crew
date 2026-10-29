//
//  HomeChallenges.swift
//  Rep Crew
//
//  Your challenges, first thing on Home. His word, 2026-10-29: the app opens on the home page "and it should
//  promote your challenges" · "promote was make them more obvious" · "yes code it". Smitty's idea of opening
//  on the Lobby was set aside the same night: Home is the front door.
//
//  REM: one card per active challenge, the ones with reps still to go today first. The card's top row opens
//  the challenge; each exercise gets its own row with today's count, what's left, and + buttons, so a tap
//  never has to choose between the link and a button (two buttons in one row both fire — PhotoBoard REM).
//  A + tap posts to the crew's board the same way the challenge screen does (LeaderboardSection.post).
//

import SwiftData
import SwiftUI

struct HomeChallengesSection: View {
    let challenges: [Challenge]

    /// Not done today first, so what still needs doing is on top.
    private var ordered: [Challenge] {
        challenges.filter(\.isActive).sorted { a, b in
            let aDone = a.isComplete(on: .now), bDone = b.isComplete(on: .now)
            return aDone == bDone ? a.startDate > b.startDate : !aDone
        }
    }

    var body: some View {
        if !ordered.isEmpty {
            Section {
                Text("Your Challenges").font(AppFont.title)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4))
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(ordered) { HomeChallengeCard(challenge: $0) }
        }
    }
}

private struct HomeChallengeCard: View {
    let challenge: Challenge
    @AppStorage(CrewSettings.name) private var name = ""

    var body: some View {
        let done = challenge.isComplete(on: .now)
        Section {
            NavigationLink(value: challenge) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(challenge.title).font(AppFont.heading)
                        Spacer()
                        DaySeal(challenge: challenge, day: .now)
                    }
                    Text(summary(done: done)).font(AppFont.bodyBold)
                        .foregroundStyle(done ? .green : .primary)
                    if let day = challenge.dayNumber() {
                        Text("Day \(day) of \(challenge.days)" + (challenge.streak > 0 ? " · 🔥 \(challenge.streak)" : ""))
                            .font(AppFont.body).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
            ForEach(challenge.sortedGoals) { HomeGoalRow(goal: $0) }
        }
        // Your reps reach the crew's board from Home too.
        .task(id: challenge.dayNumber().map { LeaderboardSection.postKey(challenge, day: $0) } ?? "") {
            guard let day = challenge.dayNumber(), !challenge.crewID.isEmpty else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await LeaderboardSection.post(challenge, day: day, name: name)
        }
    }

    /// "50 reps to go", or "Goal met". Mixed units have no total, the same as the leaderboard.
    private func summary(done: Bool) -> String {
        if done { return "Goal met today" }
        guard let total = challenge.dailyTotal else { return "Not done yet" }
        let left = max(total - challenge.repsToday, 0)
        return "\(challenge.sharedUnit.label(left)) to go today"
    }
}

private struct HomeGoalRow: View {
    let goal: ExerciseGoal
    @Environment(\.modelContext) private var context

    var body: some View {
        let done = goal.total(on: .now)
        let left = goal.remaining(on: .now)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(goal.name).font(AppFont.bodyBold)
                Spacer()
                Text("\(goal.unit.amount(done)) / \(goal.unit.amount(goal.dailyTarget))")
                    .font(AppFont.bodyBold).monospacedDigit()
            }
            ProgressView(value: Double(min(done, goal.dailyTarget)), total: Double(max(goal.dailyTarget, 1)))
                .tint(left == 0 ? .green : .accentColor)
            HStack(spacing: 10) {
                ForEach(goal.unit.quickAdds, id: \.self) { amount in
                    Button("+\(goal.unit.amount(amount))") { log(amount) }
                        .font(AppFont.bodyBold)
                        .buttonStyle(.bordered)
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityLabel("Add \(goal.unit.label(amount)) of \(goal.name)")
                }
                Spacer(minLength: 0)
                Text(left == 0 ? "Done" : "\(goal.unit.label(left)) to go")
                    .font(AppFont.body).foregroundStyle(left == 0 ? .green : .secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func log(_ count: Int) {
        let entry = RepEntry(count: count)
        entry.goal = goal
        context.insert(entry)
        try? context.save()
    }
}
