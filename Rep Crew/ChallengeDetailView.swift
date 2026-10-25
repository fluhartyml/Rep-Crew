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
    @State private var confirmingClose = false
    @State private var runningRoutine = false
    @State private var closeFailed: String?
    /// Read so this screen redraws the moment a closing arrives (ChallengeClose.swift).
    @AppStorage(CrewSettings.closedChallenges) private var closedChallenges = ""
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

            if let notice = closingNotice {
                Section {
                    Label(notice, systemImage: "lock.fill").font(AppFont.bodyBold)
                }
            }

            if challenge.isActive {
                Section {
                    // Every exercise in order, one timed set at a time (Routine.swift).
                    if challenge.allGoals.count > 1 {
                        Button { runningRoutine = true } label: {
                            Label("Start Routine", systemImage: "list.bullet.clipboard").font(AppFont.bodyBold)
                        }
                    }
                    ForEach(challenge.sortedGoals) { goal in
                        GoalRow(goal: goal, onCustom: { customGoal = goal }, onStartSet: { setGoal = goal })
                    }
                } header: {
                    Text("Today").font(AppFont.bodyBold).textCase(nil)
                }
            }

            if !challenge.isFinished {
                Section {
                    // Pair workouts other apps saved to Health with these exercises (HealthMatch.swift).
                    NavigationLink { HealthMatchView() } label: {
                        Label("Match Health Workouts", systemImage: "heart.text.square").font(AppFont.bodyBold)
                    }
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

            ActivitySection(challenge: challenge)

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
                // REM: his word: "import from apple contacts so they can invite someone to the crew" ·
                // "i want it to be one contact and not all contacts". Same text as Share Challenge,
                // sent to the one phone number or email picked.
                Button { ContactsPresenter.shared.invite(text: shareText) } label: {
                    Label("Invite a Contact", systemImage: "person.crop.circle.badge.plus").font(AppFont.bodyBold)
                }
            }
        }
        .navigationTitle(challenge.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if canClose {
                        Button { confirmingClose = true } label: {
                            Label("Close Challenge", systemImage: "lock")
                        }
                    }
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
        .sheet(isPresented: $runningRoutine) { RoutineView(challenge: challenge) }
        .onAppear { assignCrewID() }
        // Only once something is paired, so opening a challenge never asks for Health access by itself.
        .task { if challenge.countsHealth { await HealthLibrary.shared.refresh() } else { await DailyStats.refreshHealthIfAllowed() } }
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
        .confirmationDialog("Close \(challenge.title)?", isPresented: $confirmingClose, titleVisibility: .visible) {
            Button("Close Challenge for Everyone") { Task { await close() } }
        } message: {
            Text("It ends today for the whole crew and moves to Finished. Everyone's reps stay. This can't be undone.")
        }
        .alert("Couldn't close the challenge", isPresented: Binding(get: { closeFailed != nil }, set: { if !$0 { closeFailed = nil } })) {
            Button("OK") { closeFailed = nil }
        } message: {
            Text(closeFailed ?? "")
        }
    }

    private var closingNotice: String? { _ = closedChallenges; return ChallengeClosure.notice(challenge.crewID) }

    /// His rule: the crew leader closes their own challenge; a coach can close anyone's.
    private var canClose: Bool {
        guard !challenge.crewID.isEmpty, !challenge.isFinished else { return false }
        return challenge.leaderID.isEmpty || challenge.leaderID == CrewCloud.shared.myID || GodMode.isOn
    }

    private func close() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let ok = await CrewCloud.shared.close(crewID: challenge.crewID, leaderID: challenge.leaderID,
                                              senderName: trimmed.isEmpty ? "A crew member" : trimmed)
        if ok {
            closedChallenges = UserDefaults.standard.string(forKey: CrewSettings.closedChallenges) ?? ""
        } else {
            closeFailed = CrewCloud.shared.status.hasPrefix("Couldn't close") ? CrewCloud.shared.status : "Check that you're signed in to iCloud, then try again."
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
            if challenge.isClosed {
                Text("Closed").font(AppFont.title)
            } else if let day = challenge.dayNumber() {
                Text("Day \(day) of \(challenge.days)").font(AppFont.title)
                if challenge.isComplete(on: .now) {
                    Label("Today's challenge complete", systemImage: "checkmark.seal.fill")
                        .font(AppFont.bodyBold)
                        .foregroundStyle(.green)
                }
                if let stats = challenge.statsText(on: .now) {
                    Text("Today: \(stats)").font(AppFont.bodyBold)
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
        let byHealth = left > 0 && goal.checkedByHealth(on: .now)
        let minutes = goal.healthMinutes(on: .now)
        let calories = goal.healthCalories(on: .now)
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
                Text(left == 0 ? "Goal met" : (byHealth ? "Checked off by a Health workout" : "\(left) to go"))
                    .font(AppFont.bodyBold)
                    .foregroundStyle(left == 0 || byHealth ? .green : .primary)
                Spacer()
                Button { undo() } label: {
                    Image(systemName: "arrow.uturn.backward").font(AppFont.bodyBold)
                }
                .buttonStyle(.bordered)
                .disabled(goal.lastEntry(on: .now) == nil)
                .accessibilityLabel("Undo last entry")
            }
            if minutes > 0 || calories > 0 {
                Text("From Health today: " + [minutes > 0 ? "\(minutes) min" : nil, calories > 0 ? "\(calories) cal" : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(AppFont.body)
                    .foregroundStyle(.secondary)
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
                    if let stats = challenge.statsText(on: day) {
                        Text(stats).font(AppFont.body).foregroundStyle(.secondary)
                    }
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
