//
//  Routine.swift
//  Rep Crew
//
//  Start Routine: the challenge's exercises one after another, each a timed set that asks how many.
//  His word, 2026-10-25, from Hanna's PST Daily (200 sit-ups, 200 push-ups, 45 pull-ups a day):
//  "1 set of situps 1 set of pushups 1 set of pullups each set would have the exercise timer that asks
//  for how many were done so they could record indivitual chunks of a set within a routine".
//
//  REM: no new data. Each set is a RepEntry on its exercise, the same as Start Set, so a set of 150
//  sit-ups leaves 50 to go and the day counts only when every exercise is met. After each set you pick
//  Another Set of the same exercise or move on, so a day can be 199 push-ups and then 50 more.
//

import SwiftData
import SwiftUI

struct RoutineView: View {
    @Environment(\.dismiss) private var dismiss
    let challenge: Challenge

    @State private var index = 0
    /// Bumped for each new set, so the timer panel starts fresh.
    @State private var setNumber = 0
    /// A set was just saved; choose Another Set or the next exercise.
    @State private var between = false
    @State private var timing = true
    @State private var started = false

    private var goals: [ExerciseGoal] { challenge.sortedGoals }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if goals.indices.contains(index) {
                    Text("Exercise \(index + 1) of \(goals.count)").font(AppFont.body).foregroundStyle(.secondary)
                    if between {
                        afterSet(goals[index])
                    } else {
                        SetTimerPanel(goal: goals[index], continueTitle: "Continue", timing: $timing) { between = true }
                            .id(setNumber)
                    }
                }
            }
            .padding(.top)
            .navigationTitle(challenge.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(between ? "End Routine" : "Cancel") { dismiss() }.font(AppFont.bodyBold)
                }
            }
        }
        .interactiveDismissDisabled(timing && !between)
        .onAppear {
            guard !started else { return }
            started = true
            // Start at the first exercise not met yet today.
            index = goals.firstIndex { $0.remaining(on: .now) > 0 } ?? 0
        }
    }

    @ViewBuilder
    private func afterSet(_ goal: ExerciseGoal) -> some View {
        let done = goal.total(on: .now)
        let left = goal.remaining(on: .now)
        VStack(spacing: 20) {
            Text(goal.name).font(AppFont.heading)
            Text("\(goal.unit.amount(done)) / \(goal.unit.label(goal.dailyTarget))").font(AppFont.bigNumber).monospacedDigit()
            Text(left == 0 ? "Goal met" : "\(goal.unit.label(left)) to go").font(AppFont.bodyBold)
                .foregroundStyle(left == 0 ? .green : .primary)
            if let next = nextIndex {
                Button { move(to: next) } label: {
                    Text("Next: \(goals[next].name)").font(AppFont.bodyBold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button { dismiss() } label: {
                    Text("Finish Routine").font(AppFont.bodyBold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            Button { move(to: index) } label: {
                Text("Another Set of \(goal.name)").font(AppFont.bodyBold).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding()
    }

    /// The next exercise in order, or nil after the last one.
    private var nextIndex: Int? { index + 1 < goals.count ? index + 1 : nil }

    private func move(to newIndex: Int) {
        index = newIndex
        setNumber += 1
        timing = true
        between = false
    }
}
