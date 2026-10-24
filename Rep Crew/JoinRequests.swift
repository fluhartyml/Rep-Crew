//
//  JoinRequests.swift
//  Rep Crew
//
//  Ask to Join. His word, 2026-10-22: the crew sees all of the challenges and can "click a
//  button to request the crew leader of the challenge the crew member is looking at to request
//  to tap in and join" — and a challenge of one is "a personal goal … others may want to join
//  in the one persons challenge, it would cause viral participation".
//
//  One record type in the crew's iCloud space:
//    JoinRequest  name = join.<crewID>.<requesterID>; crewID, leaderID, requesterID, name,
//                 crewNumber, title, requestedAt.
//  The leader's phone gets a notification for each new request. Approve puts the person on
//  the challenge's memberIDs, so the existing Invitations list on their Home offers Accept,
//  and sends them a "You're in" message, which notifies them. Decline puts them on the
//  challenge's declinedIDs. Only the leader can change the challenge record, so both answers
//  live there and every phone reads the same thing.
//

import CloudKit
import SwiftUI

struct JoinRequest: Identifiable {
    let id: String
    let crewID: String
    let requesterID: String
    let name: String
    let requestedAt: Date?
}

/// Where you stand on someone else's challenge.
enum JoinStanding {
    case loading, canAsk, asked, approved, declined, banned
}

// MARK: - iCloud

extension CrewCloud {
    /// Sends the leader your request. Asking twice replaces the first one.
    func askToJoin(_ listing: CrewListing, name: String, crewNumber: Int) async -> Bool {
        await connect()
        guard let myID else { return false }
        let record = CKRecord(recordType: "JoinRequest", recordID: CKRecord.ID(recordName: "join.\(listing.id).\(myID)"))
        record["crewID"] = listing.id
        record["leaderID"] = listing.leaderID
        record["requesterID"] = myID
        record["name"] = name
        record["crewNumber"] = crewNumber
        record["title"] = listing.info.title
        record["requestedAt"] = Date.now
        do {
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            return true
        } catch {
            status = "Couldn't send your request: \(error.localizedDescription)"
            return false
        }
    }

    /// Your standing on someone else's challenge.
    func joinStanding(crewID: String, leaderID: String) async -> JoinStanding {
        await connect()
        guard let myID else { return .canAsk }
        if await banned(crewID: crewID, leaderID: leaderID).contains(myID) { return .banned }
        if let challenge = try? await db.record(for: CKRecord.ID(recordName: crewID)) {
            if (challenge["memberIDs"] as? [String] ?? []).contains(myID) { return .approved }
            if (challenge["declinedIDs"] as? [String] ?? []).contains(myID) { return .declined }
        }
        if (try? await db.record(for: CKRecord.ID(recordName: "join.\(crewID).\(myID)"))) != nil { return .asked }
        return .canAsk
    }

    /// Leader: requests on your challenge that haven't been answered yet.
    func joinRequests(crewID: String) async -> [JoinRequest] {
        await connect()
        guard myID != nil else { return [] }
        let query = CKQuery(recordType: "JoinRequest", predicate: NSPredicate(format: "crewID == %@", crewID))
        let records: [CKRecord]
        do {
            let (results, _) = try await db.records(matching: query)
            records = results.compactMap { try? $0.1.get() }
        } catch let error as CKError where error.code == .unknownItem {
            return []   // No one has asked yet, so the record type doesn't exist yet.
        } catch {
            status = "Couldn't load join requests: \(error.localizedDescription)"
            return []
        }
        var answered: Set<String> = []
        if let challenge = try? await db.record(for: CKRecord.ID(recordName: crewID)) {
            answered.formUnion(challenge["memberIDs"] as? [String] ?? [])
            answered.formUnion(challenge["declinedIDs"] as? [String] ?? [])
        }
        let hide = await hidden(crewID: crewID)
        return records.compactMap { record -> JoinRequest? in
            guard let id = record["requesterID"] as? String, !answered.contains(id), !hide.contains(id) else { return nil }
            return JoinRequest(id: record.recordID.recordName, crewID: crewID, requesterID: id,
                               name: record["name"] as? String ?? "A crew member",
                               requestedAt: record["requestedAt"] as? Date ?? record.creationDate)
        }
        .sorted { $0.name < $1.name }
    }

    /// Leader: yes adds them to the challenge and tells them; no is recorded so they see it.
    func answer(_ request: JoinRequest, approve: Bool, leaderName: String, title: String) async -> Bool {
        await connect()
        guard myID != nil else { return false }
        do {
            let challenge = try await db.record(for: CKRecord.ID(recordName: request.crewID))
            let key = approve ? "memberIDs" : "declinedIDs"
            var ids = challenge[key] as? [String] ?? []
            if !ids.contains(request.requesterID) { ids.append(request.requesterID) }
            challenge[key] = ids
            _ = try await db.modifyRecords(saving: [challenge], deleting: [], savePolicy: .changedKeys)
        } catch {
            status = "Couldn't answer \(request.name): \(error.localizedDescription)"
            return false
        }
        if approve {
            _ = await send("You're in \(title). Open Rep Crew and accept it on Home.", crewID: request.crewID,
                           kind: .welcome, to: request.requesterID, senderName: leaderName)
        }
        return true
    }

    /// Leader: a notification whenever someone asks to join one of your challenges.
    /// Kept apart from the message subscriptions so one missing type can't sink the other.
    func subscribeToJoinRequests() async {
        await connect()
        guard let myID else { return }
        guard NotificationSettings.isOn(NotificationSettings.joinRequests) else {
            _ = try? await db.modifySubscriptions(saving: [], deleting: [NotificationSettings.joinRequests])
            return
        }
        let subscription = CKQuerySubscription(recordType: "JoinRequest", predicate: NSPredicate(format: "leaderID == %@", myID),
                                               subscriptionID: "join-requests", options: [.firesOnRecordCreation])
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true   // wakes the app to raise the icon badge (InboxBadge)
        // A key with no translation is used as the format itself, so the record's own fields fill it in.
        info.titleLocalizationKey = "%1$@ asked to join"
        info.titleLocalizationArgs = ["name"]
        info.alertLocalizationKey = "%1$@"
        info.alertLocalizationArgs = ["title"]
        info.soundName = "default"
        subscription.notificationInfo = info
        do {
            _ = try await db.modifySubscriptions(saving: [subscription], deleting: [])
        } catch let error as CKError where error.code == .unknownItem || error.code == .partialFailure {
            // Before anyone has asked there is no JoinRequest type to subscribe to; a later launch picks it up.
        } catch {
            status = "Couldn't turn on join notifications: \(error.localizedDescription)"
        }
    }
}

// MARK: - On someone else's challenge

struct AskToJoinSection: View {
    let listing: CrewListing

    @AppStorage(CrewSettings.name) private var name = ""
    @AppStorage(CrewSettings.crewNumber) private var crewNumber = 0
    @State private var standing = JoinStanding.loading
    @State private var sending = false
    @State private var failed = false

    var body: some View {
        Section {
            switch standing {
            case .loading:
                ProgressView()
            case .canAsk where !CrewCloud.shared.can(.join):
                Text("Your access level doesn't include joining crew challenges yet. The head coach can raise it.").font(AppFont.body)
            case .canAsk:
                Button {
                    Task { await ask() }
                } label: {
                    Label("Ask to Join", systemImage: "hand.wave.fill").font(AppFont.bodyBold)
                }
                .disabled(sending)
                if failed {
                    Text("Your request didn't go through. Check iCloud in Settings and try again.").font(AppFont.body)
                }
            case .asked:
                Label("Asked. \(listing.leaderName) gets a notification.", systemImage: "checkmark.circle.fill")
                    .font(AppFont.body)
            case .approved:
                Label("You're in. Accept it under Invitations on Home.", systemImage: "checkmark.seal.fill")
                    .font(AppFont.bodyBold).foregroundStyle(.green)
            case .declined:
                Text("\(listing.leaderName) kept this one closed.").font(AppFont.body)
            case .banned:
                EmptyView()
            }
        }
        .task(id: listing.id) {
            standing = await CrewCloud.shared.joinStanding(crewID: listing.id, leaderID: listing.leaderID)
        }
    }

    private func ask() async {
        sending = true
        failed = false
        let me = name.trimmingCharacters(in: .whitespaces)
        if await CrewCloud.shared.askToJoin(listing, name: me.isEmpty ? "A crew member" : me, crewNumber: crewNumber) {
            standing = .asked
        } else {
            failed = true
        }
        sending = false
    }
}

// MARK: - On your own challenge, as leader

struct JoinRequestsSection: View {
    let challenge: Challenge
    /// Loaded by the challenge screen, so the list can stay hidden until someone asks.
    @Binding var requests: [JoinRequest]

    @AppStorage(CrewSettings.name) private var name = ""
    @State private var failed = false

    var body: some View {
        if !requests.isEmpty || failed {
            Section {
                ForEach(requests) { request in
                    HStack(spacing: 12) {
                        Text(request.name).font(AppFont.bodyBold).lineLimit(1)
                        Spacer()
                        // Borderless, so each button takes only its own taps inside a List row.
                        Button("Decline") { Task { await answer(request, approve: false) } }
                            .buttonStyle(.borderless).font(AppFont.body)
                        Button("Approve") { Task { await answer(request, approve: true) } }
                            .buttonStyle(.borderless).font(AppFont.bodyBold)
                    }
                }
                if failed {
                    Text("That didn't go through. Check iCloud in Settings and try again.").font(AppFont.body)
                }
            } header: {
                Text("Asking to join").font(AppFont.bodyBold).textCase(nil)
            }
        }
    }

    /// Unanswered requests when you lead the challenge; none otherwise.
    static func load(_ challenge: Challenge) async -> [JoinRequest] {
        guard challenge.leaderID.isEmpty, !challenge.crewID.isEmpty else { return [] }
        return await CrewCloud.shared.joinRequests(crewID: challenge.crewID)
    }

    private func answer(_ request: JoinRequest, approve: Bool) async {
        let me = name.trimmingCharacters(in: .whitespaces)
        failed = !(await CrewCloud.shared.answer(request, approve: approve,
                                                  leaderName: me.isEmpty ? "Your crew leader" : me, title: challenge.title))
        requests = await Self.load(challenge)
    }
}
