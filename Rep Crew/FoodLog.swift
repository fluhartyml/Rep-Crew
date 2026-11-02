//
//  FoodLog.swift
//  Rep Crew
//
//  The "I didn't eat…" box and today's list of what you skipped.
//  REM: Smitty's idea, by his word 2026-11-01: "i didn't eat. . . " challenge · "can it have an input box to log what you
//  didnt eat?" · "everytime you log 'i didnt eat something' you can log what you didnt eat with optional calori count
//  where it totals at the end of the day so you can race to cut junkfood calories" · "yes build the calorie race".
//  REM: on a Calories skipped exercise the entry's count IS the calories, so the day's total, the goal and the crew's
//  leaderboard all count calories with nothing new on the shared board. Calories are optional: left blank, the food is
//  still listed with 0 calories. On a Skips exercise each entry counts 1. The food's name is RepEntry.note, which
//  stays in your own iCloud; the crew sees only the totals.

import SwiftData
import SwiftUI

/// "What didn't you eat?" with optional calories. Hands back (count, food) when you tap Log It.
struct FoodLogSheet: View {
    let unit: ExerciseUnit
    let onSave: (Int, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var food = ""
    @State private var calories = ""
    @FocusState private var focused: Bool

    private var trimmed: String { food.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var calorieCount: Int? { calories.isEmpty ? 0 : Int(calories.filter(\.isNumber)) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Dessert, a soda, fries…", text: $food)
                        .font(AppFont.heading)
                        .focused($focused)
                        .submitLabel(.next)
                } header: {
                    Text("I didn't eat…").font(AppFont.bodyBold).textCase(nil)
                }
                if unit == .calories {
                    Section {
                        TextField("Calories", text: $calories)
                            .font(AppFont.heading)
                            .keyboardType(.numberPad)
                    } header: {
                        Text("Calories (optional)").font(AppFont.bodyBold).textCase(nil)
                    } footer: {
                        Text("The calories you skipped count toward today's total and the crew's race. Leave it blank and the food is still listed.")
                            .font(AppFont.body)
                    }
                }
            }
            .navigationTitle("I Didn't Eat…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.font(AppFont.body)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log It") {
                        onSave(unit == .calories ? (calorieCount ?? 0) : 1, trimmed)
                        dismiss()
                    }
                    .font(AppFont.bodyBold)
                    .disabled(trimmed.isEmpty || calorieCount == nil)
                }
            }
            .onAppear { focused = true }
        }
    }
}

/// Today's skipped foods on one exercise, newest first, with the day's total.
struct FoodTodayList: View {
    let goal: ExerciseGoal

    var body: some View {
        let today = goal.allEntries
            .filter { Calendar.current.isDateInToday($0.loggedAt) }
            .sorted { $0.loggedAt > $1.loggedAt }
        if !today.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(today) { entry in
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.note.isEmpty ? "Something" : entry.note).font(AppFont.body)
                        Spacer()
                        if goal.unit == .calories {
                            Text(entry.count > 0 ? "\(entry.count.formatted()) cal" : "—")
                                .font(AppFont.body).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Today: \(goal.unit.label(goal.total(on: .now)))")
                    .font(AppFont.bodyBold)
            }
        }
    }
}

extension ExerciseGoal {
    /// Logs one "I didn't eat…" entry: count (calories, or 1 for a skip) and the food.
    func logFood(count: Int, food: String, in context: ModelContext) {
        let entry = RepEntry(count: count)
        entry.note = food
        entry.goal = self
        context.insert(entry)
        try? context.save()
    }
}
