//
//  JoinView.swift
//  Rep Crew
//
//  Shown when a join link opens the app. Accepting adds the challenge to this phone, saves
//  the sender's TestFlight link (so this person can invite others), and adds the sender to
//  your crew.
//

import SwiftUI
import SwiftData

struct JoinView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var challenges: [Challenge]
    @Query private var crew: [CrewMember]

    @AppStorage(CrewSettings.testFlight) private var testFlight = ""
    @AppStorage(CrewSettings.crewNumber) private var crewNumber = 0
    @AppStorage(CrewSettings.hasJoined) private var hasJoined = false
    @AppStorage(CrewSettings.name) private var name = ""
    @AppStorage(CrewSettings.declined) private var declined = ""

    let invite: Invite

    private var alreadyHave: Bool {
        guard let id = invite.challenge?.crewID else { return false }
        return challenges.contains { $0.crewID == id }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(invite.from) invited you").font(AppFont.title)
                        if let challenge = invite.challenge {
                            Text(challenge.title).font(AppFont.heading)
                            ForEach(challenge.goals, id: \.name) { goal in
                                Text("\(goal.name): \(goal.target) a day").font(AppFont.body)
                            }
                            Text("\(challenge.days) days, starting \(startText(challenge))").font(AppFont.body)
                        } else {
                            Text("Join their crew on Rep Crew.").font(AppFont.body)
                        }
                    }
                    .padding(.vertical, 6)
                }

                if alreadyHave {
                    Section {
                        Text("You've already joined this challenge.").font(AppFont.body)
                    }
                }
            }
            .navigationTitle("Invitation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Decline") { decline() }.font(AppFont.body)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Accept") { accept() }.font(AppFont.bodyBold)
                }
            }
        }
    }

    private func decline() {
        if let crewID = invite.challenge?.crewID {
            declined += crewID + "\n"
            CrewCloud.shared.dismissPending(crewID)
        }
        dismiss()
    }

    private func startText(_ challenge: Invite.ChallengeInfo) -> String {
        Invite.date(fromDay: challenge.startDay)?.formatted(date: .abbreviated, time: .omitted) ?? challenge.startDay
    }

    private func accept() {
        // The hot potato: the sender's TestFlight link becomes this person's, so they can invite too.
        if testFlight.isEmpty, Invite.isTestFlightLink(invite.testFlight) {
            testFlight = invite.testFlight
        }
        if !hasJoined {
            crewNumber = invite.crewNumber + 1
            hasJoined = true
        }
        if let known = crew.first(where: { $0.name == invite.from && $0.crewNumber == invite.crewNumber }) {
            if known.cloudID.isEmpty, let id = invite.fromID { known.cloudID = id }
        } else {
            context.insert(CrewMember(name: invite.from, crewNumber: invite.crewNumber, cloudID: invite.fromID ?? ""))
        }
        // Tell the leader's phone, so they get a check box for you next time.
        if let leaderID = invite.fromID {
            let crewID = invite.challenge?.crewID ?? "crew"
            let me = name.trimmingCharacters(in: .whitespaces)
            let number = crewNumber
            Task { await CrewCloud.shared.join(crewID: crewID, leaderID: leaderID, name: me.isEmpty ? "A crew member" : me, crewNumber: number) }
        }
        if let info = invite.challenge, !alreadyHave {
            let start = Invite.date(fromDay: info.startDay) ?? .now
            let challenge = Challenge(title: info.title, startDate: start, days: info.days)
            challenge.crewID = info.crewID
            challenge.leaderID = invite.fromID ?? ""
            context.insert(challenge)
            for (index, goal) in info.goals.enumerated() {
                let exercise = ExerciseGoal(name: goal.name, dailyTarget: goal.target, order: index)
                exercise.challenge = challenge
                context.insert(exercise)
            }
        }
        try? context.save()
        dismiss()
    }
}
