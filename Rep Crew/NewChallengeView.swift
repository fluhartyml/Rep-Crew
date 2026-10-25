//
//  NewChallengeView.swift
//  Rep Crew
//
//  Build a challenge: a name, how many days, when it starts, and the daily goal for each exercise.
//

import SwiftUI
import SwiftData

struct NewChallengeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CrewMember.addedAt) private var crew: [CrewMember]

    @AppStorage(CrewSettings.name) private var name = ""
    @AppStorage(CrewSettings.testFlight) private var testFlight = ""
    @AppStorage(CrewSettings.crewNumber) private var crewNumber = 0

    private struct Draft: Identifiable {
        let id = UUID()
        var name: String
        var target: Int
        var unit: ExerciseUnit = .reps
    }

    @State private var title = ""
    @State private var days = 14
    @State private var startDate = Date.now
    @State private var drafts: [Draft] = [Draft(name: "Push-ups", target: 100)]
    @State private var checked: Set<String> = []
    @State private var isPublic = true
    /// Match Health Workouts' "New Challenge": hands back the new exercise so it can be paired.
    private let onCreate: ((ExerciseGoal) -> Void)?

    /// `workout`: a Health workout's name, from Match Health Workouts, filled in as the challenge and its exercise.
    /// `again`: a past challenge to run again (his word 2026-10-24, "maybe someone wants to revive a past
    /// challenge"). Same title, days and goals; starts today; a new challenge with you as the leader.
    init(fromHealth workout: String? = nil, again: Invite.ChallengeInfo? = nil, onCreate: ((ExerciseGoal) -> Void)? = nil) {
        self.onCreate = onCreate
        if let workout {
            _title = State(initialValue: "\(workout) Challenge")
            _drafts = State(initialValue: [Draft(name: workout, target: 1)])
        }
        if let again {
            _title = State(initialValue: again.title)
            _days = State(initialValue: again.days)
            _drafts = State(initialValue: again.goals.map { Draft(name: $0.name, target: $0.target, unit: $0.exerciseUnit) })
        }
    }

    /// Crew members reachable through iCloud — the ones a check box can actually reach.
    private var reachable: [CrewMember] { crew.filter { !$0.cloudID.isEmpty } }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespaces) }
    private var validDrafts: [Draft] {
        drafts.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.target > 0 }
    }
    private var canSave: Bool { !trimmedTitle.isEmpty && !validDrafts.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, like 14-Day Push-up Challenge", text: $title)
                        .font(AppFont.body)
                } header: { header("Challenge") }

                Section {
                    Stepper(value: $days, in: 1...365) {
                        Text("\(days) \(days == 1 ? "day" : "days")").font(AppFont.body)
                    }
                    DatePicker(selection: $startDate, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date) {
                        Text("Starts").font(AppFont.body)
                    }
                } header: { header("How long") }

                Section {
                    Toggle(isOn: $isPublic) {
                        Text("Public").font(AppFont.body)
                    }
                } header: {
                    header("Who can see it")
                } footer: {
                    Text(isPublic
                         ? "Everyone with Rep Crew sees this challenge and its leaderboard."
                         : "Only the crew you check or invite sees this challenge.")
                        .font(AppFont.body)
                }

                Section {
                    ForEach($drafts) { $draft in
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Exercise", text: $draft.name).font(AppFont.bodyBold)
                            // REM: his ask 2026-10-25: each exercise counts in reps, steps, minutes, miles or laps.
                            Picker("Counts in", selection: $draft.unit) {
                                ForEach(ExerciseUnit.allCases) { unit in
                                    Text(unit.title).tag(unit)
                                }
                            }
                            .font(AppFont.body)
                            .onChange(of: draft.unit) { draft.target = draft.unit.startingTarget }
                            Stepper(value: $draft.target, in: draft.unit.targetRange, step: draft.unit.targetStep(at: draft.target)) {
                                Text("\(draft.unit.label(draft.target)) a day").font(AppFont.body)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { drafts.remove(atOffsets: $0) }

                    Menu {
                        ForEach(ExercisePreset.names.filter { name in !drafts.contains { $0.name == name } }, id: \.self) { name in
                            Button(name) { drafts.append(Draft(name: name, target: 50)) }
                        }
                        Button("Other exercise") { drafts.append(Draft(name: "", target: 50)) }
                    } label: {
                        Label("Add an exercise", systemImage: "plus.circle").font(AppFont.bodyBold)
                    }
                } header: {
                    header("Daily routine")
                } footer: {
                    Text("Swipe left on an exercise to remove it.").font(AppFont.body)
                }

                Section {
                    ForEach(reachable) { member in
                        Button { toggle(member.cloudID) } label: {
                            HStack {
                                Image(systemName: checked.contains(member.cloudID) ? "checkmark.circle.fill" : "circle")
                                    .font(AppFont.heading)
                                Text(member.name).font(AppFont.bodyBold).foregroundStyle(.primary)
                                Spacer()
                                Text("Crew member \(CrewCloud.numberText(member.crewNumber))").font(AppFont.body).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    header("Crew")
                } footer: {
                    Text(reachable.isEmpty
                         ? "No crew yet. After you save, open the challenge and tap Invite to Crew to text or email someone."
                         : "Checked members get this challenge on their phone to accept. To add someone new, save, then tap Invite to Crew on the challenge.")
                        .font(AppFont.body)
                }
            }
            .navigationTitle("New Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.font(AppFont.body)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.font(AppFont.bodyBold).disabled(!canSave)
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if checked.contains(id) { checked.remove(id) } else { checked.insert(id) }
    }

    private func header(_ text: String) -> some View {
        Text(text).font(AppFont.bodyBold).textCase(nil)
    }

    /// Small goals step by 1, bigger ones by 5 or 10, so reaching 100 doesn't take 100 taps.

    private func save() {
        let challenge = Challenge(title: trimmedTitle, startDate: startDate, days: days)
        challenge.isPublic = isPublic
        context.insert(challenge)
        var first: ExerciseGoal?
        for (index, draft) in validDrafts.enumerated() {
            let goal = ExerciseGoal(name: draft.name.trimmingCharacters(in: .whitespaces), dailyTarget: draft.target, order: index)
            goal.unit = draft.unit
            goal.challenge = challenge
            context.insert(goal)
            if first == nil { first = goal }
        }
        if let first { onCreate?(first) }
        // Every challenge goes to the shared space, checked crew or not, so the whole crew sees it.
        do {
            challenge.crewID = UUID().uuidString
            let info = Invite.ChallengeInfo(challenge)
            let leader = name.trimmingCharacters(in: .whitespaces)
            let link = testFlight.trimmingCharacters(in: .whitespaces)
            let members = Array(checked)
            let number = crewNumber
            let open = isPublic
            Task {
                await CrewCloud.shared.publish(info, leaderName: leader.isEmpty ? "Your crew leader" : leader,
                                               leaderNumber: number, testFlight: link, memberIDs: members, isPublic: open)
            }
        }
        try? context.save()
        dismiss()
    }
}

#Preview {
    NewChallengeView().modelContainer(for: [Challenge.self, ExerciseGoal.self, RepEntry.self, CrewMember.self], inMemory: true)
}
