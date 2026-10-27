//
//  TVShare.swift
//  Rep Crew
//
//  What this phone keeps in your own iCloud for the Apple TV board (Rep Crew TV/).
//  His design, 2026-10-27: the TV shows announcements, then "your weekly routine in a flat list", then the
//  challenge boards. His word, same day: "the apple tv follows the iphones view as" · "use cloud kit
//  persistant data across devices".
//
//  One record in the PRIVATE database (only your own devices can read it):
//    PersonalBoard  name = "mine"; week (JSON of TVWeekEntry), viewAsLevel (absent = yourself), viewAsName.
//  REM: your week stays yours ("Yours alone; never shared", Models.swift → weekdays). The private database
//  keeps that true: the crew's public space never sees it.
//  REM: the TV decodes the same JSON with its own copy of TVWeekEntry (Rep Crew TV/TVCloud.swift). Change
//  the fields in both places or the TV's week goes blank.
//

import CloudKit
import Foundation

/// One challenge on your week, as the TV reads it.
struct TVWeekEntry: Codable, Equatable {
    var crewID: String
    var title: String
    /// Calendar weekdays, 1 = Sunday. Empty = not on your week, so it counts every day.
    var weekdays: [Int]
    /// "100 push-ups and 50 squats".
    var goals: String
}

extension CrewCloud {
    private var personalDB: CKDatabase { CKContainer(identifier: "iCloud.com.accountability.dailyrepcrew").privateCloudDatabase }
    private static let personalID = CKRecord.ID(recordName: "mine")

    /// Your week for the TV: every challenge not yet finished, with the weekdays it's on.
    func saveWeek(_ challenges: [Challenge]) async {
        let entries = challenges.filter { !$0.isFinished }.map { challenge in
            TVWeekEntry(crewID: challenge.crewID, title: challenge.title,
                        weekdays: challenge.scheduledWeekdays.sorted(),
                        goals: challenge.allGoals.sorted { $0.order < $1.order }
                            .map { $0.unit.goalText($0.dailyTarget, name: $0.name) }
                            .joined(separator: " and "))
        }
        guard let json = try? JSONEncoder().encode(entries) else { return }
        await savePersonal { $0["week"] = String(data: json, encoding: .utf8) }
    }

    /// View Home As, kept across devices and launches until he ends it from the bar on Home.
    func saveViewAs(_ level: Int?) async {
        let name = level.flatMap { accessTable.band(for: $0)?.name }
        await savePersonal { record in
            record["viewAsLevel"] = level
            record["viewAsName"] = name
        }
    }

    /// The View Home As level saved from any of his devices; nil = himself, or iCloud didn't answer.
    func loadViewAs() async -> Int? {
        guard let record = try? await personalDB.record(for: Self.personalID) else { return nil }
        return record["viewAsLevel"] as? Int
    }

    /// Fetch-then-save so the week and View Home As never overwrite each other.
    private func savePersonal(_ change: (CKRecord) -> Void) async {
        guard (try? await CKContainer(identifier: "iCloud.com.accountability.dailyrepcrew").accountStatus()) == .available else { return }
        let record = (try? await personalDB.record(for: Self.personalID)) ?? CKRecord(recordType: "PersonalBoard", recordID: Self.personalID)
        change(record)
        _ = try? await personalDB.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
    }
}
