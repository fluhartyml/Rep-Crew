//
//  Linchpin.swift
//  Rep Crew
//
//  The linchpin: the network Legend systems share, in its own container, iCloud.com.legend.linchpin.
//  Rep Crew joins it as a second system, so the network is proven between two different apps.
//  REM: his words, 2026-11-01: "okay this is what we will have to do with smittys app eventually" · "can we add the
//  linchpin to smitty's local testflight app?" · "dont we need the crew app to prove compatibility among two systems?"
//  · "sounds good" (to: Rep Crew lists itself in Legend Affiliates and shows the list, touching none of its own data).
//  REM: Rep Crew's own container (iCloud.com.accountability.dailyrepcrew) is not read or written here. Only one small
//  record goes to the linchpin, and deleting it undoes everything this file does.
//  REM: same record type and fields as Legend's Linchpin.swift (NetworkBoard, kind "board"). Those names are deployed in
//  CloudKit and can't change; on screen it's "system" and "Legend Affiliates" (his word, 2026-11-01: "this is the 20's").
//  REM: only the head coach lists Rep Crew, the way a Legend Sysop lists their system. Only the record's maker can
//  change it, so nobody else can rewrite the entry.

import CloudKit
import Foundation

enum Linchpin {
    static let containerID = "iCloud.com.legend.linchpin"
    private static let container = CKContainer(identifier: containerID)
    private static var hub: CKDatabase { container.publicCloudDatabase }

    /// The line every system on the network sees under Rep Crew's name.
    static let tagline = "Daily rep challenges with your crew."

    /// One system as the network sees it.
    struct Affiliate: Identifiable, Equatable {
        let id: String
        let name: String
        let tagline: String
        let sysopHandle: String
    }

    /// Rep Crew's id on the network: the head coach's iCloud ID in Rep Crew's own container, marked as Rep Crew's.
    static func systemID(headCoach: String) -> String { "board-repcrew-\(headCoach)" }

    /// Every system on the network, by name.
    static func affiliates() async throws -> [Affiliate] {
        let query = CKQuery(recordType: "NetworkBoard", predicate: NSPredicate(format: "kind == %@", "board"))
        let (results, _) = try await hub.records(matching: query, resultsLimit: CKQueryOperation.maximumResults)
        return results.compactMap { id, result -> Affiliate? in
            guard let record = try? result.get() else { return nil }
            return Affiliate(id: id.recordName,
                             name: record["name"] as? String ?? "",
                             tagline: record["tagline"] as? String ?? "",
                             sysopHandle: record["sysopHandle"] as? String ?? "")
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The head coach puts Rep Crew on the network, or brings its entry up to date.
    static func list(headCoach: String, name: String, handle: String) async throws {
        let id = CKRecord.ID(recordName: systemID(headCoach: headCoach))
        let record = (try? await hub.record(for: id)) ?? CKRecord(recordType: "NetworkBoard", recordID: id)
        record["kind"] = "board"
        record["name"] = name
        record["tagline"] = tagline
        record["sysopHandle"] = handle
        _ = try await hub.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
    }

    /// The head coach takes Rep Crew off the network.
    static func unlist(headCoach: String) async throws {
        do {
            _ = try await hub.modifyRecords(saving: [], deleting: [CKRecord.ID(recordName: systemID(headCoach: headCoach))])
        } catch let error as CKError where error.code == .unknownItem {
            return
        }
    }
}
