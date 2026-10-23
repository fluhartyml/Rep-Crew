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
    @State private var setGoal: ExerciseGoal?
    @State private var confirmingDelete = false
    /// The leader removed you; your own reps stay, the crew parts go.
    @State private var removed = false
    /// People asking to join, when you lead this challenge.
    @State private var joinRequests: [JoinRequest] = []

    @AppStorage(CrewSettings.name) private var name = ""
    @AppStorage(CrewSettings.testFlight) private var testFlight = ""
    @AppStorage(CrewSettings.crewNumber) private var crewNumber = 0

    var body: some View {
        List {
            Section { summary }

            if challenge.isActive {
                Section {
                    ForEach(challenge.sortedGoals) { goal in
                        GoalRow(goal: goal, onCustom: { customGoal = goal }, onStartSet: { setGoal = goal })
                    }
                } header: {
                    Text("Today").font(AppFont.bodyBold).textCase(nil)
                }
            }

            if removed {
                Section {
                    Text("The leader removed you from this challenge. Your own reps are still here.").font(AppFont.body)
                }
            } else {
                JoinRequestsSection(challenge: challenge, requests: $joinRequests)

                LeaderboardSection(challenge: challenge)

                PhotoBoardSection(crewID: challenge.crewID, leaderID: challenge.leaderID, canAdd: true)
            }

            Section {
                ForEach(challenge.allDays, id: \.self) { day in
                    DayRow(challenge: challenge, day: day)
                }
            } header: {
                Text("Every day").font(AppFont.bodyBold).textCase(nil)
            }

            if !removed { CrewMessagesSection(challenge: challenge) }

            Section {
                // REM: One share, not two (his word 10-22: "its a duplicate share sheet"). Progress first,
                // the join link under it, so whoever gets it can tap in.
                ShareLink(item: shareText) {
                    Label("Share Challenge", systemImage: "square.and.arrow.up").font(AppFont.bodyBold)
                }
            }
        }
        .navigationTitle(challenge.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Label("Delete Challenge", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(AppFont.bodyBold)
                }
                .accessibilityLabel("More")
            }
        }
        .crewNavGlyphs()
        .sheet(item: $customGoal) { goal in CustomRepsView(goal: goal) }
        .sheet(item: $setGoal) { goal in SetTimerView(goal: goal) }
        .onAppear { assignCrewID() }
        .task(id: challenge.crewID) { joinRequests = await JoinRequestsSection.load(challenge) }
        .task(id: challenge.crewID) {
            guard !challenge.leaderID.isEmpty, let me = CrewCloud.shared.myID else { return }
            removed = await CrewCloud.shared.banned(crewID: challenge.crewID, leaderID: challenge.leaderID).contains(me)
        }
        .confirmationDialog("Delete \(challenge.title)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Challenge and All Its Reps", role: .destructive) {
                context.delete(challenge)
                try? context.save()
                dismiss()
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    /// This challenge as an invite. His word: Share Challenge is one button that always works,
    /// so the join link uses the built-in TestFlight link and "A crew member" when Settings is blank.
    private var challengeInvite: Invite? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !challenge.crewID.isEmpty else { return nil }
        return Invite(from: trimmed.isEmpty ? "A crew member" : trimmed, crewNumber: crewNumber, testFlight: Invite.testFlightLink(testFlight),
                      challenge: Invite.ChallengeInfo(challenge), fromID: CrewCloud.shared.myID)
    }

    /// Every copy of a shared challenge carries the same crew ID, so joining twice doesn't duplicate it.
    private func assignCrewID() {
        if challenge.crewID.isEmpty { challenge.crewID = UUID().uuidString }
    }

    /// Today's results, then the join link when there is one.
    private var shareText: String {
        guard let invite = challengeInvite else { return crewReport }
        return crewReport + "\n\n" + invite.message(isPublic: challenge.isPublic)
    }

    /// Today's results as plain text, ready for a group message.
    private var crewReport: String {
        var lines = [challenge.title]
        if let day = challenge.dayNumber() {
            lines[0] += " — Day \(day) of \(challenge.days)"
            for goal in challenge.sortedGoals {
                let done = goal.total(on: .now)
                let mark = done >= goal.dailyTarget ? " ✅" : ""
                lines.append("\(goal.name): \(done)/\(goal.dailyTarget)\(mark)")
            }
        }
        lines.append("\(challenge.completedDays) of \(challenge.days) days completed")
        return lines.joined(separator: "\n")
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
    let onStartSet: () -> Void

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
            // Undo sits on the "to go" line so the add buttons get the full width.
            HStack {
                Text(left == 0 ? "Goal met" : "\(left) to go")
                    .font(AppFont.bodyBold)
                    .foregroundStyle(left == 0 ? .green : .primary)
                Spacer()
                Button { undo() } label: {
                    Image(systemName: "arrow.uturn.backward").font(AppFont.bodyBold)
                }
                .buttonStyle(.bordered)
                .disabled(goal.lastEntry(on: .now) == nil)
                .accessibilityLabel("Undo last entry")
            }
            // +5, +10, Other, then the whole daily goal in one tap (Michael's layout).
            HStack(spacing: 10) {
                ForEach([5, 10], id: \.self) { amount in
                    addButton(amount)
                }
                Button("Other") { onCustom() }
                    .font(AppFont.bodyBold)
                    .buttonStyle(.bordered)
                    .lineLimit(1)
                    .fixedSize()
                addButton(goal.dailyTarget)
                Spacer(minLength: 0)
            }
            // Times a set and saves it to Health as a workout (SetTimer.swift).
            Button { onStartSet() } label: {
                Label("Start Set", systemImage: "timer").font(AppFont.bodyBold)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 8)
    }

    private func addButton(_ amount: Int) -> some View {
        Button("+\(amount)") { log(amount) }
            .font(AppFont.bodyBold)
            .buttonStyle(.bordered)
            .lineLimit(1)
            .fixedSize()
    }

    private func log(_ count: Int) {
        let entry = RepEntry(count: count)
        entry.goal = goal
        context.insert(entry)
        try? context.save()
    }

    private func undo() {
        if let last = goal.lastEntry(on: .now) { context.delete(last); try? context.save() }
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
                        try? context.save()
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
