//
//  MyWeek.swift
//  Rep Crew
//
//  My Week: seven sheets, Sunday to Saturday, that you swipe between. On each one you pick which of your
//  challenges you do that day, and each shows as a card.
//  Smitty's ask on the FaceTime, 2026-10-26: "a weekly schedule like Monday Tuesday Wednesday Thursday Friday
//  and then you can click which day you do … I don't think people need to do the same exercise every day."
//  His design, same day: "sunday monday tuesday wednesday thursday friday saturday sheets all swipable on each
//  weekday sheet you get to pick from some sort of picker then the challenges you chose for the weekday get a
//  challenge card" · "a generic week with no dates" · "yes build it".
//
//  REM: a generic week, no dates. Each challenge already has its own start and end; the week says only which
//  weekdays it belongs to (Challenge.weekdays, Models.swift). It is personal: your week never changes the
//  leader's challenge or anyone else's.
//  REM: his streak rule (Leaderboard.swift → streak): a challenge's streak skips the days it isn't on and breaks
//  on a day it is on that you missed. A challenge that isn't on your week at all counts every day, as before.
//  REM: a day with no cards is a rest day only when every challenge is on your week somewhere; otherwise the
//  challenges not on your week still count that day, and the sheet says so.
//  REM: the weekday strip at the top is there because a swipe that starts on a card could be read as a card
//  gesture; tapping a day always works. Cards are removed with their own button, not a row swipe, for the same
//  reason.
//

import SwiftData
import SwiftUI

struct MyWeekView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Challenge.startDate) private var challenges: [Challenge]
    /// Calendar weekday shown, 1 = Sunday. Opens on today.
    @State private var weekday = Calendar.current.component(.weekday, from: .now)
    @State private var picking: Int?

    /// Challenges you can put on your week: running or about to start.
    private var current: [Challenge] { challenges.filter { !$0.isFinished } }
    private var unplanned: [Challenge] { current.filter { $0.scheduledWeekdays.isEmpty } }

    var body: some View {
        VStack(spacing: 0) {
            dayStrip
            TabView(selection: $weekday) {
                ForEach(1...7, id: \.self) { day in
                    sheet(day).tag(day)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle("My Week")
        .crewNavGlyphs()
        .sheet(item: Binding(get: { picking.map(PickDay.init) }, set: { picking = $0?.day })) { pick in
            PickChallengesView(weekday: pick.day, challenges: current)
        }
    }

    private var dayStrip: some View {
        HStack(spacing: 4) {
            ForEach(1...7, id: \.self) { day in
                let isToday = day == Calendar.current.component(.weekday, from: .now)
                Button { withAnimation { weekday = day } } label: {
                    Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                        .font(isToday ? AppFont.bodyBold : AppFont.body)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(day == weekday ? Color.accentColor.opacity(0.2) : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1] + (isToday ? ", today" : ""))
                .accessibilityAddTraits(day == weekday ? .isSelected : [])
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func sheet(_ day: Int) -> some View {
        let cards = current.filter { $0.scheduledWeekdays.contains(day) }
        let name = Calendar.current.weekdaySymbols[day - 1]
        return List {
            Section {
                if cards.isEmpty {
                    if unplanned.isEmpty {
                        Label("Rest day", systemImage: "moon.zzz.fill").font(AppFont.bodyBold)
                    } else {
                        Text("Nothing picked for \(name). Challenges that aren't on your week still count every day.")
                            .font(AppFont.body).foregroundStyle(.secondary)
                    }
                }
                ForEach(cards) { challenge in
                    card(challenge, day: day)
                }
                Button { picking = day } label: {
                    Label("Add Challenges", systemImage: "plus.circle.fill").font(AppFont.bodyBold)
                }
                .disabled(current.isEmpty)
            } header: {
                Text(name).font(AppFont.heading).textCase(nil)
            } footer: {
                if current.isEmpty {
                    Text("Start or join a challenge first.").font(AppFont.body)
                }
            }
        }
    }

    private func card(_ challenge: Challenge, day: Int) -> some View {
        HStack(alignment: .top) {
            NavigationLink(value: challenge) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(challenge.title).font(AppFont.bodyBold)
                    Text(challenge.sortedGoals.map { "\($0.name) \($0.dailyTarget)" }.joined(separator: " · "))
                        .font(AppFont.body).foregroundStyle(.secondary)
                    Text(challenge.dateRange).font(AppFont.body).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Button {
                challenge.setScheduled(false, weekday: day)
                try? context.save()
            } label: {
                Image(systemName: "minus.circle.fill").font(AppFont.heading).foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Take \(challenge.title) off \(Calendar.current.weekdaySymbols[day - 1])")
        }
    }
}

/// The picker: check the challenges you do on this weekday.
private struct PickChallengesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let weekday: Int
    let challenges: [Challenge]

    var body: some View {
        NavigationStack {
            List(challenges) { challenge in
                let isOn = challenge.scheduledWeekdays.contains(weekday)
                Button {
                    challenge.setScheduled(!isOn, weekday: weekday)
                    try? context.save()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(challenge.title).font(AppFont.bodyBold).foregroundStyle(.primary)
                            Text(challenge.sortedGoals.map(\.name).joined(separator: ", "))
                                .font(AppFont.body).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .font(AppFont.heading).foregroundStyle(isOn ? Color.accentColor : .secondary)
                    }
                }
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
            .navigationTitle(Calendar.current.weekdaySymbols[weekday - 1])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(AppFont.bodyBold)
                }
            }
        }
    }
}

private struct PickDay: Identifiable {
    let day: Int
    var id: Int { day }
}
