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

    private struct Draft: Identifiable {
        let id = UUID()
        var name: String
        var target: Int
    }

    @State private var title = ""
    @State private var days = 14
    @State private var startDate = Date.now
    @State private var drafts: [Draft] = [Draft(name: "Push-ups", target: 100)]

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
                    ForEach($drafts) { $draft in
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Exercise", text: $draft.name).font(AppFont.bodyBold)
                            Stepper(value: $draft.target, in: 1...10_000, step: stepSize(for: draft.target)) {
                                Text("\(draft.target) a day").font(AppFont.body)
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
                    header("Daily goals")
                } footer: {
                    Text("Swipe left on an exercise to remove it.").font(AppFont.body)
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

    private func header(_ text: String) -> some View {
        Text(text).font(AppFont.bodyBold).textCase(nil)
    }

    /// Small goals step by 1, bigger ones by 5 or 10, so reaching 100 doesn't take 100 taps.
    private func stepSize(for target: Int) -> Int {
        target < 20 ? 1 : (target < 100 ? 5 : 10)
    }

    private func save() {
        let challenge = Challenge(title: trimmedTitle, startDate: startDate, days: days)
        context.insert(challenge)
        for (index, draft) in validDrafts.enumerated() {
            let goal = ExerciseGoal(name: draft.name.trimmingCharacters(in: .whitespaces), dailyTarget: draft.target, order: index)
            goal.challenge = challenge
            context.insert(goal)
        }
        dismiss()
    }
}

#Preview {
    NewChallengeView().modelContainer(for: [Challenge.self, ExerciseGoal.self, RepEntry.self], inMemory: true)
}
