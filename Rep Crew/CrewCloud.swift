//
//  CrewCloud.swift
//  Rep Crew
//
//  The crew's shared space in iCloud (CloudKit public database, container
//  iCloud.com.accountability.dailyrepcrew). Two record types:
//
//    CrewChallenge  name = crewID. Written by the leader: the challenge plus the IDs of the
//                   crew members checked off for it. A checked member's phone finds it and
//                   offers Accept / Decline.
//    Membership     name = crewID.memberID. Written by whoever joins, so the leader's phone
//                   learns who is in the crew and can offer them a check box next time.
//
//  Development builds use CloudKit's Development environment. TestFlight uses Production,
//  so the schema has to be deployed to Production in the CloudKit Console before upload.
//  REM: the schema is written down in CloudKit-Schema.ckdb (repo root) and imported in the
//  Console, not left to first use: CrewChallenge saves failed BAD_REQUEST, so it never existed.
//

import CloudKit
import Foundation
import Observation

@MainActor @Observable
final class CrewCloud {
    static let shared = CrewCloud()

    private let container = CKContainer(identifier: "iCloud.com.accountability.dailyrepcrew")
    var db: CKDatabase { container.publicCloudDatabase }

    /// This person's iCloud user record name; nil until iCloud answers.
    private(set) var myID: String?
    /// What Settings shows about the connection, in plain words.
    var status = "Checking iCloud…"
    /// Challenges a leader checked you off for that you haven't accepted or declined.
    private(set) var pending: [Invite] = []
    /// People he made coaches, by iCloud ID → name (GodMode.swift). Loaded on connect.
    var coaches: [String: String] = [:]
    /// Coaches' public keys for Coaches-only contact info (ContactSeal.swift). Loaded on connect.
    var coachKeys: [String: Data] = [:]
    /// Set when a coach taps a "joined the crew" notification; Home opens New Crew Members.
    var openNewMembers = false
    /// This phone's member's level, flags and title (Access.swift). Loaded on connect.
    var myAccess = MemberAccess(level: 0, flags: "", title: "")

    func connect() async {
        if myID != nil { return }
        do {
            guard try await container.accountStatus() == .available else {
                status = "Not signed in to iCloud. Sign in from the iPhone Settings app to share with your crew."
                return
            }
            myID = try await container.userRecordID().recordName
            // Kept so the developer can read his own ID off his phone for god mode (GodMode.swift).
            UserDefaults.standard.set(myID, forKey: "myCloudID")
            await loadCoaches()
            await loadCoachKeys()
            await loadCrewName()
            await loadAccess()
            status = "Connected to iCloud"
        } catch {
            status = "iCloud problem: \(error.localizedDescription)"
        }
    }

    // MARK: Leader

    /// Puts the challenge in the shared space with the checked members' IDs.
    func publish(_ info: Invite.ChallengeInfo, leaderName: String, leaderNumber: Int, testFlight: String, memberIDs: [String], isPublic: Bool) async {
        await connect()
        guard let myID else { return }
        let record = CKRecord(recordType: "CrewChallenge", recordID: CKRecord.ID(recordName: info.crewID))
        record["title"] = info.title
        record["startDay"] = info.startDay
        record["days"] = info.days
        record["goals"] = String(data: (try? JSONEncoder().encode(info.goals)) ?? Data(), encoding: .utf8)
        record["leaderID"] = myID
        record["leaderName"] = leaderName
        record["leaderNumber"] = leaderNumber
        record["testFlight"] = testFlight
        record["memberIDs"] = memberIDs
        record["endsAt"] = Self.endsAt(info)
        record["isPublic"] = isPublic ? 1 : 0
        do {
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            // REM: clear only this challenge's own old error. Resetting to "Connected" on any success
            // hid other challenges' failures (2026-10-23: every CrewChallenge save was BAD_REQUEST).
            if status.hasPrefix("Couldn't share \(info.title):") { status = "Connected to iCloud" }
            await refreshMyAccess()   // starting a challenge is level 55 (Access.swift)
        } catch {
            status = "Couldn't share \(info.title): \(error.localizedDescription)"
        }
    }

    /// Makes sure a challenge you started is in the shared space, so the whole crew can see it.
    /// One that's already there keeps its checked members; it only gains an end date if it lacks one.
    func ensurePublished(_ info: Invite.ChallengeInfo, leaderName: String, leaderNumber: Int, testFlight: String, isPublic: Bool) async {
        await connect()
        guard myID != nil else { return }
        do {
            let record = try await db.record(for: CKRecord.ID(recordName: info.crewID))
            let flag = isPublic ? 1 : 0
            guard record["endsAt"] == nil || record["isPublic"] as? Int != flag else { return }
            record["endsAt"] = Self.endsAt(info)
            record["isPublic"] = flag
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
        } catch let error as CKError where error.code == .unknownItem {
            await publish(info, leaderName: leaderName, leaderNumber: leaderNumber, testFlight: testFlight, memberIDs: [], isPublic: isPublic)
        } catch {
            status = "Couldn't share \(info.title): \(error.localizedDescription)"
        }
    }

    /// The moment after a challenge's last day, so finished ones drop off the crew list.
    private static func endsAt(_ info: Invite.ChallengeInfo) -> Date {
        let start = Invite.date(fromDay: info.startDay) ?? .now
        return Calendar.current.date(byAdding: .day, value: info.days, to: start) ?? start
    }

    /// Member: a notification when a leader checks you off on a new challenge.
    /// REM: his "yes add the invite notification" (2026-10-23) — James saw Hannah's invite only on opening the app.
    /// Kept apart from the other subscriptions so one missing type can't sink the others.
    func subscribeToInvites() async {
        await connect()
        guard let myID else { return }
        guard NotificationSettings.isOn(NotificationSettings.invites) else {
            _ = try? await db.modifySubscriptions(saving: [], deleting: [NotificationSettings.invites])
            return
        }
        let subscription = CKQuerySubscription(recordType: "CrewChallenge", predicate: NSPredicate(format: "memberIDs CONTAINS %@", myID),
                                               subscriptionID: "invites", options: [.firesOnRecordCreation])
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true   // wakes the app to raise the icon badge (InboxBadge)
        // A key with no translation is used as the format itself, so the record's own fields fill it in.
        info.titleLocalizationKey = "%1$@ invited you to a challenge"
        info.titleLocalizationArgs = ["leaderName"]
        info.alertLocalizationKey = "%1$@ — open Rep Crew to accept it."
        info.alertLocalizationArgs = ["title"]
        info.soundName = "default"
        subscription.notificationInfo = info
        do {
            _ = try await db.modifySubscriptions(saving: [subscription], deleting: [])
        } catch let error as CKError where error.code == .unknownItem || error.code == .partialFailure {
            // Before any challenge is shared there may be no CrewChallenge type; a later launch picks it up.
        } catch {
            status = "Couldn't turn on invite notifications: \(error.localizedDescription)"
        }
    }

    /// Every challenge anyone on the app is running or about to start. His word, 2026-10-22:
    /// "the crew is the app downloader" — everyone who has the app sees every challenge.
    func crewChallenges() async -> [CrewListing] {
        await connect()
        guard myID != nil else { return [] }
        let query = CKQuery(recordType: "CrewChallenge", predicate: NSPredicate(format: "endsAt > %@", Date.now as NSDate))
        do {
            let (results, _) = try await db.records(matching: query, resultsLimit: 200)
            return results.compactMap { try? $0.1.get() }.compactMap { record in
                // Private challenges stay off the list. Records from before the toggle count as public.
                guard record["isPublic"] as? Int != 0, let invite = Self.invite(from: record), let info = invite.challenge else { return nil }
                return CrewListing(info: info, leaderID: invite.fromID ?? "", leaderName: invite.from)
            }
        } catch let error as CKError where error.code == .unknownItem {
            return []   // No challenge has been shared yet, so the record type doesn't exist yet.
        } catch {
            status = "Couldn't load the crew's challenges: \(error.localizedDescription)"
            return []
        }
    }

    /// Everyone who has joined one of your challenges.
    func members() async -> [(id: String, name: String, number: Int)] {
        await connect()
        guard let myID else { return [] }
        let query = CKQuery(recordType: "Membership", predicate: NSPredicate(format: "leaderID == %@", myID))
        do {
            let (results, _) = try await db.records(matching: query)
            return results.compactMap { try? $0.1.get() }.compactMap { record in
                guard let id = record["memberID"] as? String, let name = record["name"] as? String else { return nil }
                return (id, name, record["crewNumber"] as? Int ?? 0)
            }
        } catch let error as CKError where error.code == .unknownItem {
            return []   // No one has joined yet, so the record type doesn't exist yet.
        } catch {
            status = "Couldn't load your crew: \(error.localizedDescription)"
            return []
        }
    }

    // MARK: Member

    /// Challenges you were checked off for, minus ones already on this phone or declined.
    func refreshPending(skipping crewIDs: Set<String>) async {
        await connect()
        guard let myID else { return }
        let query = CKQuery(recordType: "CrewChallenge", predicate: NSPredicate(format: "memberIDs CONTAINS %@", myID))
        do {
            let (results, _) = try await db.records(matching: query)
            pending = results.compactMap { try? $0.1.get() }.compactMap(Self.invite(from:))
                .filter { !crewIDs.contains($0.challenge?.crewID ?? "") }
        } catch let error as CKError where error.code == .unknownItem {
            pending = []   // No challenge has been shared yet, so the record type doesn't exist yet.
        } catch {
            status = "Couldn't check for challenges: \(error.localizedDescription)"
        }
    }

    /// Tells the leader's phone you're in. Called when you accept, however the invite arrived.
    func join(crewID: String, leaderID: String, name: String, crewNumber: Int) async {
        await connect()
        guard let myID, leaderID != myID else { return }
        let record = CKRecord(recordType: "Membership", recordID: CKRecord.ID(recordName: "\(crewID).\(myID)"))
        record["crewID"] = crewID
        record["leaderID"] = leaderID
        record["memberID"] = myID
        record["name"] = name
        record["crewNumber"] = crewNumber
        do {
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            await refreshMyAccess()   // joining a challenge is level 16 (Access.swift)
        } catch {
            status = "Couldn't tell your crew you joined: \(error.localizedDescription)"
        }
        pending.removeAll { $0.challenge?.crewID == crewID }
    }

    func dismissPending(_ crewID: String) {
        pending.removeAll { $0.challenge?.crewID == crewID }
    }

    /// Public challenges that have ended, newest first, for Start Again on Home.
    func pastChallenges() async -> [CrewListing] {
        await connect()
        guard myID != nil else { return [] }
        let query = CKQuery(recordType: "CrewChallenge", predicate: NSPredicate(format: "endsAt <= %@", Date.now as NSDate))
        query.sortDescriptors = [NSSortDescriptor(key: "endsAt", ascending: false)]
        guard let (results, _) = try? await db.records(matching: query, resultsLimit: 30) else { return [] }
        return results.compactMap { try? $0.1.get() }.compactMap { record in
            guard record["isPublic"] as? Int != 0, let invite = Self.invite(from: record), let info = invite.challenge else { return nil }
            return CrewListing(info: info, leaderID: invite.fromID ?? "", leaderName: invite.from)
        }
    }

    /// Also read by CrewRestore.swift.
    static func invite(from record: CKRecord) -> Invite? {
        guard let title = record["title"] as? String,
              let startDay = record["startDay"] as? String,
              let days = record["days"] as? Int,
              let goalsText = record["goals"] as? String,
              let goals = try? JSONDecoder().decode([Invite.Goal].self, from: Data(goalsText.utf8)) else { return nil }
        var invite = Invite(from: record["leaderName"] as? String ?? "Your crew leader",
                            crewNumber: record["leaderNumber"] as? Int ?? 0,
                            testFlight: record["testFlight"] as? String ?? "",
                            challenge: .init(crewID: record.recordID.recordName, title: title, startDay: startDay, days: days, goals: goals))
        invite.fromID = record["leaderID"] as? String
        return invite
    }
}
