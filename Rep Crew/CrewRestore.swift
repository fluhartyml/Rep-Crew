//
//  CrewRestore.swift
//  Rep Crew
//
//  Brings back challenges a phone lost — the app deleted before its store reached the person's
//  own iCloud — from the crew's shared space: every challenge you lead (CrewChallenge.leaderID)
//  and every one you joined (Membership.memberID), with your days from your Progress records.
//
//  REM: his word 2026-10-24, "icloud is the bridge between piers so if a pier deleted their app it
//  doesnt effect the rest of the crew". The crew's copy is the bridge; this walks back across it.
//  REM: Progress keeps one total per day, not one per exercise. A day is rebuilt only where the
//  split is certain: a one-exercise challenge, or a finished day whose total equals the targets.
//  Any other day is left empty rather than guessed (house rule: never invent data). The crew
//  board still shows those days, because this phone holds back from posting a lower number over
//  today's (Challenge.restoredRepsToday, LeaderboardSection).
//  REM: when the person's own iCloud copy of the same challenge arrives, it is the real record
//  and the rebuilt one is removed (removeRebuiltDuplicates).
//

import CloudKit
import Foundation
import SwiftData

extension CrewCloud {
    /// One of your days as the crew's board has it.
    struct Day {
        var reps: Int
        var complete: Bool
    }

    /// Every challenge you lead or joined, as the shared space has it. Finished ones included.
    func myChallenges() async -> [Invite] {
        await connect()
        guard let myID else { return [] }
        var found: [String: Invite] = [:]
        do {
            let led = CKQuery(recordType: "CrewChallenge", predicate: NSPredicate(format: "leaderID == %@", myID))
            for record in try await db.records(matching: led, resultsLimit: 200).matchResults.compactMap({ try? $0.1.get() }) {
                if let invite = Self.invite(from: record) { found[record.recordID.recordName] = invite }
            }
            let joined = CKQuery(recordType: "Membership", predicate: NSPredicate(format: "memberID == %@", myID))
            let crewIDs = try await db.records(matching: joined, resultsLimit: 200).matchResults
                .compactMap { try? $0.1.get() }.compactMap { $0["crewID"] as? String }
                .filter { found[$0] == nil }
            if !crewIDs.isEmpty {
                let records = try await db.records(for: crewIDs.map { CKRecord.ID(recordName: $0) })
                for (id, result) in records {
                    if let record = try? result.get(), let invite = Self.invite(from: record) { found[id.recordName] = invite }
                }
            }
        } catch let error as CKError where error.code == .unknownItem {
            return []   // Nothing has been shared yet, so the record types don't exist yet.
        } catch {
            status = "Couldn't look for your challenges: \(error.localizedDescription)"
            return []
        }
        return Array(found.values)
    }

    /// Your days in one challenge, by day number.
    func myDays(crewID: String) async -> [Int: Day] {
        await connect()
        guard let myID else { return [:] }
        let query = CKQuery(recordType: "Progress", predicate: NSPredicate(format: "crewID == %@ AND memberID == %@", crewID, myID))
        guard let results = try? await db.records(matching: query, resultsLimit: 400).matchResults else { return [:] }
        var days: [Int: Day] = [:]
        for record in results.compactMap({ try? $0.1.get() }) {
            guard let day = record["dayNumber"] as? Int else { continue }
            days[day] = Day(reps: record["reps"] as? Int ?? 0, complete: (record["complete"] as? Int ?? 0) == 1)
        }
        return days
    }
}

enum CrewRestore {
    /// Rebuilds any challenge of yours that's in the shared space but not on this phone.
    @MainActor
    static func run(context: ModelContext, declined: Set<String>) async {
        removeRebuiltDuplicates(context: context)
        let cloud = CrewCloud.shared
        let here = Set(((try? context.fetch(FetchDescriptor<Challenge>())) ?? []).map(\.crewID).filter { !$0.isEmpty })
        for invite in await cloud.myChallenges() {
            guard let info = invite.challenge, !here.contains(info.crewID), !declined.contains(info.crewID),
                  let start = Invite.date(fromDay: info.startDay) else { continue }
            let challenge = Challenge(title: info.title, startDate: start, days: info.days)
            challenge.crewID = info.crewID
            // Empty leaderID marks your own challenge everywhere else in the app.
            challenge.leaderID = invite.fromID == cloud.myID ? "" : (invite.fromID ?? "")
            challenge.restoredFromCrew = true
            context.insert(challenge)
            var goals: [ExerciseGoal] = []
            for (index, goal) in info.goals.enumerated() {
                let exercise = ExerciseGoal(name: goal.name, dailyTarget: goal.target, order: index)
                exercise.challenge = challenge
                context.insert(exercise)
                goals.append(exercise)
            }
            let days = await cloud.myDays(crewID: info.crewID)
            for (number, day) in days where day.reps > 0 {
                guard let date = Calendar.current.date(byAdding: .day, value: number - 1, to: challenge.startDate),
                      let at = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date) else { continue }
                for (goal, count) in split(day, across: goals) where count > 0 {
                    let entry = RepEntry(count: count, loggedAt: at)
                    entry.goal = goal
                    context.insert(entry)
                }
            }
            if let today = challenge.dayNumber(), let day = days[today] {
                challenge.restoredDay = today
                challenge.restoredRepsToday = day.reps
            }
        }
        try? context.save()
    }

    /// Each exercise's share of a day's total, only where it is certain. Otherwise none.
    static func split(_ day: CrewCloud.Day, across goals: [ExerciseGoal]) -> [(ExerciseGoal, Int)] {
        if goals.count == 1, let goal = goals.first { return [(goal, day.reps)] }
        let targets = goals.reduce(0) { $0 + $1.dailyTarget }
        if day.complete && day.reps == targets { return goals.map { ($0, $0.dailyTarget) } }
        return []
    }

    /// Your own iCloud copy of a challenge wins over one rebuilt from the crew's.
    @MainActor
    static func removeRebuiltDuplicates(context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<Challenge>())) ?? []
        let byCrew = Dictionary(grouping: all.filter { !$0.crewID.isEmpty }, by: \.crewID)
        var removed = false
        for (_, copies) in byCrew where copies.count > 1 {
            let originals = copies.filter { !$0.restoredFromCrew }
            // Two rebuilt copies (two phones rebuilt at once): keep the first.
            let keep = originals.isEmpty ? Array(copies.prefix(1)) : originals
            for copy in copies where !keep.contains(where: { $0 === copy }) {
                context.delete(copy)
                removed = true
            }
        }
        if removed { try? context.save() }
    }
}
