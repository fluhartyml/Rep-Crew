//
//  ContentView.swift
//  Rep Crew
//
//  The list of challenges: running now, starting later, and finished.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Challenge.startDate, order: .reverse) private var challenges: [Challenge]

    @State private var showingNew = false
    @State private var showingAbout = false

    private var active: [Challenge] { challenges.filter(\.isActive) }
    private var upcoming: [Challenge] { challenges.filter { !$0.hasStarted } }
    private var finished: [Challenge] { challenges.filter(\.isFinished) }

    var body: some View {
        NavigationStack {
            Group {
                if challenges.isEmpty {
                    emptyState
                } else {
                    List {
                        section("Today", active)
                        section("Starting soon", upcoming)
                        section("Finished", finished)
                    }
                }
            }
            .navigationTitle("Rep Crew")
            .navigationDestination(for: Challenge.self) { ChallengeDetailView(challenge: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingAbout = true } label: {
                        Image(systemName: "info.circle").font(AppFont.heading)
                    }
                    .accessibilityLabel("About Rep Crew")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNew = true } label: {
                        Image(systemName: "plus.circle.fill").font(AppFont.heading)
                    }
                    .accessibilityLabel("New challenge")
                }
            }
            .sheet(isPresented: $showingNew) { NewChallengeView() }
            .sheet(isPresented: $showingAbout) { AboutView() }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [Challenge]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { challenge in
                    NavigationLink(value: challenge) { ChallengeRow(challenge: challenge) }
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(items[index]) }
                }
            } header: {
                Text(title).font(AppFont.bodyBold).textCase(nil)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.strengthtraining.functional")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("No challenges yet").font(AppFont.title)
            Text("Set a daily goal, like 100 push-ups a day for 14 days, then log your reps as you go.")
                .font(AppFont.body)
                .multilineTextAlignment(.center)
            Button { showingNew = true } label: {
                Text("Start a challenge").font(AppFont.bodyBold).padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
    }
}

struct ChallengeRow: View {
    let challenge: Challenge

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(challenge.title).font(AppFont.bodyBold)
                Spacer()
                if challenge.isActive && challenge.isComplete(on: .now) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(AppFont.heading)
                        .foregroundStyle(.green)
                        .accessibilityLabel("Done for today")
                }
            }
            Text(status).font(AppFont.body)
        }
        .padding(.vertical, 4)
    }

    private var status: String {
        if let day = challenge.dayNumber() {
            return "Day \(day) of \(challenge.days)"
        } else if !challenge.hasStarted {
            return "Starts \(challenge.startDate.formatted(date: .abbreviated, time: .omitted))"
        } else {
            return "\(challenge.completedDays) of \(challenge.days) days completed"
        }
    }
}

#Preview {
    ContentView().modelContainer(for: [Challenge.self, ExerciseGoal.self, RepEntry.self], inMemory: true)
}
