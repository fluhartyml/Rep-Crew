//
//  Leaderboard.swift
//  Rep Crew
//
//  Today's crew board. Michael's design, 2026-10-22: "i would insist on a leaderboard",
//  listed in numerical order by TODAY'S reps, starting fresh every morning, with no place
//  labels — "i would imply the ranking and not be explicit." Not the whole-challenge total,
//  because an underdog who is always last would never see a good day pay off.
//
//  Each phone writes one Progress record per challenge day to the crew's iCloud space:
//    Progress  name = crewID.memberID.dayNumber; crewID, memberID, name, dayNumber,
//              reps (today's total across every goal), complete (0/1), streak.
//  Day numbers come from the shared start day, so every phone agrees on "today".
//

import CloudKit
import SwiftUI

struct CrewStanding: Identifiable {
    let id: String
    var name: String
    var reps = 0
    var complete = false
    var streak = 0
}

// MARK: - iCloud

extension CrewCloud {
    /// Saves your total for `dayNumber`. Saving the same name again replaces it.
    func postProgress(crewID: String, dayNumber: Int, name: String, reps: Int, complete: Bool, streak: Int) async {
        await connect()
        guard let myID else { return }
        let record = CKRecord(recordType: "Progress", recordID: CKRecord.ID(recordName: "\(crewID).\(myID).\(dayNumber)"))
        record["crewID"] = crewID
        record["memberID"] = myID
        record["name"] = name
        record["dayNumber"] = dayNumber
        record["reps"] = reps
        record["complete"] = complete ? 1 : 0
        record["streak"] = streak
        do {
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        } catch {
            status = "Couldn't share your reps: \(error.localizedDescription)"
        }
    }

    /// Everyone in the crew with today's reps. Anyone who hasn't logged yet shows 0, and a
    /// streak still counts if they finished yesterday.
    func standings(crewID: String, dayNumber: Int) async -> [CrewStanding] {
        await connect()
        guard myID != nil else { return [] }
        var board: [String: CrewStanding] = [:]

        // Whoever started it, if they shared it through iCloud.
        if let leader = try? await db.record(for: CKRecord.ID(recordName: crewID)),
           let id = leader["leaderID"] as? String {
            board[id] = CrewStanding(id: id, name: leader["leaderName"] as? String ?? "Crew leader")
        }

        // Everyone who joined.
        let joined = CKQuery(recordType: "Membership", predicate: NSPredicate(format: "crewID == %@", crewID))
        if let (results, _) = try? await db.records(matching: joined) {
            for record in results.compactMap({ try? $0.1.get() }) {
                guard let id = record["memberID"] as? String else { continue }
                board[id] = CrewStanding(id: id, name: record["name"] as? String ?? "Crew member")
            }
        }

        // Yesterday's records carry streaks for anyone who hasn't logged today; today's win.
        let days = [dayNumber - 1, dayNumber]
        let progress = CKQuery(recordType: "Progress", predicate: NSPredicate(format: "crewID == %@ AND dayNumber IN %@", crewID, days))
        do {
            let (results, _) = try await db.records(matching: progress)
            let records = results.compactMap { try? $0.1.get() }
                .sorted { ($0["dayNumber"] as? Int ?? 0) < ($1["dayNumber"] as? Int ?? 0) }
            for record in records {
                guard let id = record["memberID"] as? String else { continue }
                var row = board[id] ?? CrewStanding(id: id, name: "Crew member")
                if let name = record["name"] as? String, !name.isEmpty { row.name = name }
                let complete = (record["complete"] as? Int ?? 0) == 1
                if record["dayNumber"] as? Int == dayNumber {
                    row.reps = record["reps"] as? Int ?? 0
                    row.complete = complete
                    row.streak = record["streak"] as? Int ?? 0
                } else if complete {
                    row.streak = record["streak"] as? Int ?? 0
                }
                board[id] = row
            }
        } catch let error as CKError where error.code == .unknownItem {
            // No one has logged yet, so the record type doesn't exist yet.
        } catch {
            status = "Couldn't load the crew board: \(error.localizedDescription)"
        }
        return Array(board.values)
    }
}

// MARK: - On the challenge screen

struct LeaderboardSection: View {
    let challenge: Challenge
    @AppStorage(CrewSettings.name) private var name = ""
    @State private var others: [CrewStanding] = []

    private var myID: String? { CrewCloud.shared.myID }

    /// Your row comes from this phone, so a tap shows up on the board at once.
    private var me: CrewStanding {
        CrewStanding(id: myID ?? "me", name: "You", reps: repsToday,
                     complete: challenge.isComplete(on: .now), streak: streak)
    }

    private var repsToday: Int { challenge.goals.reduce(0) { $0 + $1.total(on: .now) } }

    /// Days in a row with every goal met, through today if it's done, else through yesterday.
    private var streak: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: .now)
        if !challenge.isComplete(on: day) { day = cal.date(byAdding: .day, value: -1, to: day) ?? day }
        var count = 0
        while day >= challenge.startDate, challenge.isComplete(on: day) {
            count += 1
            day = cal.date(byAdding: .day, value: -1, to: day) ?? challenge.startDate.addingTimeInterval(-86_400)
        }
        return count
    }

    /// Highest reps first. Ties go alphabetical so the order doesn't jump around.
    private var rows: [CrewStanding] {
        ([me] + others.filter { $0.id != myID })
            .sorted { $0.reps != $1.reps ? $0.reps > $1.reps : $0.name < $1.name }
    }

    var body: some View {
        if let day = challenge.dayNumber(), !challenge.crewID.isEmpty {
            Group {
                // A board of one is just you; it appears once anyone else is in the crew.
                if !others.filter({ $0.id != myID }).isEmpty {
                    Section {
                        ForEach(rows) { row in
                            StandingRow(row: row, isMe: row.id == me.id)
                        }
                    } header: {
                        let done = rows.filter(\.complete).count
                        Text("Day \(day) of \(challenge.days) · Crew \(done)/\(rows.count) ✓")
                            .font(AppFont.bodyBold).textCase(nil)
                    }
                }
            }
            // Re-runs whenever your reps change; the short wait lets a run of taps land as one save.
            .task(id: "\(day).\(repsToday)") {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                let me = name.trimmingCharacters(in: .whitespaces)
                await CrewCloud.shared.postProgress(crewID: challenge.crewID, dayNumber: day,
                                                    name: me.isEmpty ? "A crew member" : me,
                                                    reps: repsToday, complete: challenge.isComplete(on: .now), streak: streak)
            }
            // Keeps the board current while the screen is open.
            .task(id: "\(challenge.crewID).\(day)") {
                while !Task.isCancelled {
                    others = await CrewCloud.shared.standings(crewID: challenge.crewID, dayNumber: day)
                    try? await Task.sleep(for: .seconds(60))
                }
            }
        }
    }
}

private struct StandingRow: View {
    let row: CrewStanding
    let isMe: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(row.name).font(isMe ? AppFont.bodyBold : AppFont.body).lineLimit(1)
            Spacer()
            Text("\(row.reps) reps").font(AppFont.bodyBold).monospacedDigit()
            if row.streak > 0 {
                Text("🔥 \(row.streak)").font(AppFont.body).monospacedDigit()
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.name), \(row.reps) reps today" + (row.streak > 0 ? ", \(row.streak) day streak" : ""))
    }
}
