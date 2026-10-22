//
//  ChallengeDetailView.swift
//  Rep Crew
//
//  Today's goals with what's left, quick buttons to log reps, and a day-by-day record.
//

import SwiftUI
import SwiftData

struct ChallengeDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let challenge: Challenge

    @State private var customGoal: ExerciseGoal?
    @State private var confirmingDelete = false

    var body: some View {
        List {
            Section { summary }

            if challenge.isActive {
                Section {
                    ForEach(challenge.sortedGoals) { goal in
                        GoalRow(goal: goal, onCustom: { customGoal = goal })
                    }
                } header: {
                    Text("Today").font(AppFont.bodyBold).textCase(nil)
                }
            }

            Section {
                ForEach(challenge.allDays, id: \.self) { day in
                    DayRow(challenge: challenge, day: day)
                }
            } header: {
                Text("Every day").font(AppFont.bodyBold).textCase(nil)
            }

            Section {
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Text("Delete Challenge").font(AppFont.bodyBold)
                }
            }
        }
        .navigationTitle(challenge.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $customGoal) { goal in CustomRepsView(goal: goal) }
        .confirmationDialog("Delete \(challenge.title)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Challenge and All Its Reps", role: .destructive) {
                context.delete(challenge)
                dismiss()
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    @ViewBuilder
    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let day = challenge.dayNumber() {
                Text("Day \(day) of \(challenge.days)").font(AppFont.title)
                if challenge.isComplete(on: .now) {
                    Label("Today's challenge complete", systemImage: "checkmark.seal.fill")
                        .font(AppFont.bodyBold)
                        .foregroundStyle(.green)
                }
            } else if !challenge.hasStarted {
                Text("Starts \(challenge.startDate.formatted(date: .complete, time: .omitted))").font(AppFont.heading)
            } else {
                Text("Finished").font(AppFont.title)
            }
            Text("\(challenge.completedDays) of \(challenge.days) days completed").font(AppFont.body)
        }
        .padding(.vertical, 6)
    }
}

private struct GoalRow: View {
    @Environment(\.modelContext) private var context
    let goal: ExerciseGoal
    let onCustom: () -> Void

    var body: some View {
        let done = goal.total(on: .now)
        let left = goal.remaining(on: .now)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(goal.name).font(AppFont.heading)
                Spacer()
                Text("\(done) / \(goal.dailyTarget)").font(AppFont.bigNumber).monospacedDigit()
            }
            ProgressView(value: Double(min(done, goal.dailyTarget)), total: Double(goal.dailyTarget))
                .tint(left == 0 ? .green : .accentColor)
            Text(left == 0 ? "Goal met" : "\(left) to go")
                .font(AppFont.bodyBold)
                .foregroundStyle(left == 0 ? .green : .primary)
            HStack(spacing: 10) {
                ForEach([1, 5, 10], id: \.self) { amount in
                    Button("+\(amount)") { log(amount) }
                        .font(AppFont.bodyBold)
                        .buttonStyle(.bordered)
                }
                Button("Other") { onCustom() }
                    .font(AppFont.bodyBold)
                    .buttonStyle(.bordered)
                Spacer()
                Button { undo() } label: {
                    Image(systemName: "arrow.uturn.backward").font(AppFont.bodyBold)
                }
                .buttonStyle(.bordered)
                .disabled(goal.lastEntry(on: .now) == nil)
                .accessibilityLabel("Undo last entry")
            }
        }
        .padding(.vertical, 8)
    }

    private func log(_ count: Int) {
        let entry = RepEntry(count: count)
        entry.goal = goal
        context.insert(entry)
    }

    private func undo() {
        if let last = goal.lastEntry(on: .now) { context.delete(last) }
    }
}

private struct DayRow: View {
    let challenge: Challenge
    let day: Date

    var body: some View {
        let isToday = Calendar.current.isDateInToday(day)
        let isFuture = day > Calendar.current.startOfDay(for: .now)
        let complete = challenge.isComplete(on: day)
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(isToday ? "Today" : day.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(AppFont.bodyBold)
                if !isFuture {
                    Text(challenge.sortedGoals.map { "\($0.name) \($0.total(on: day))" }.joined(separator: " · "))
                        .font(AppFont.body)
                }
            }
            Spacer()
            Image(systemName: complete ? "checkmark.circle.fill" : (isFuture || isToday ? "circle" : "xmark.circle"))
                .font(AppFont.heading)
                .foregroundStyle(complete ? .green : (isFuture || isToday ? .secondary : .red))
                .accessibilityLabel(complete ? "Completed" : (isFuture ? "Coming up" : (isToday ? "In progress" : "Missed")))
        }
        .padding(.vertical, 2)
    }
}

private struct CustomRepsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let goal: ExerciseGoal

    @State private var count = 20
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Reps", value: $count, format: .number)
                        .keyboardType(.numberPad)
                        .font(AppFont.bigNumber)
                        .focused($focused)
                } header: {
                    Text("How many \(goal.name.lowercased())?").font(AppFont.bodyBold).textCase(nil)
                } footer: {
                    Text("\(goal.remaining(on: .now)) to go today.").font(AppFont.body)
                }
            }
            .navigationTitle("Log Reps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.font(AppFont.body)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        let entry = RepEntry(count: count)
                        entry.goal = goal
                        context.insert(entry)
                        dismiss()
                    }
                    .font(AppFont.bodyBold)
                    .disabled(count <= 0)
                }
            }
            .onAppear {
                count = max(goal.remaining(on: .now), 1)
                focused = true
            }
        }
        .presentationDetents([.medium])
    }
}
