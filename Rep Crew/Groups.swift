//
//  Groups.swift
//  Rep Crew
//
//  Groups: smaller crews inside the app, each with its own home page. His words, 2026-10-29 (Smitty approved):
//  "the smitty bunch is the localized group i am in" · "yes they can be in multiple groups swipe right and left
//  between your groups you are in" · "maybe the groups have home pages with banners and an avatar" · a verified
//  user who makes a group is its crew leader and it starts with a challenge they make; the home page is made
//  automatically · fonts and colors · "both invite and ask to join" · "please code".
//
//  REM: no new iCloud record type, so nothing new to deploy to Production:
//    • A group is a CrewMessage (kind .group) named group.<UUID> on the board crewID "groups", its details as
//      JSON in the text (as Events does). Only the leader (CloudKit's creator) can change it, and a group counts
//      only when its creator is the senderID it names.
//    • Belonging is a Membership record (crewID = the group's ID), written by whoever joins, as for challenges.
//    • An invite is a CrewMessage (kind .groupInvite) named invite.<group>.<member> in their own box
//      (dm.<their ID>), so the existing "toID == me" subscription notifies them. Honored only from the leader.
//    • Asking to join is a JoinRequest named join.<group>.<you>; the leader's existing JoinRequest subscription
//      notifies them. Approve sends the invite; either answer leaves a MessageRemoval so it drops off the list.
//    • Banner and avatar are CrewPhotos (crewID groupbanner.<group> / groupavatar.<group>), honored only from
//      the leader. New photo = new record, old one deleted.
//  REM: The Smitty Bunch (the head coach's crew name, CrewName.swift) is the first page on Home; your groups
//  follow it. NOT BUILT YET: per-group announcements and events, per-person text size, Lobby.
//

import CloudKit
import PhotosUI
import SwiftData
import SwiftUI

// MARK: - Model

/// What a group holds, saved as JSON in its record's text.
struct GroupDetails: Codable, Equatable {
    var name = ""
    var about = ""
    var theme = GroupTheme.olive.rawValue
    var font = GroupFont.standard.rawValue
    /// The group's challenges (CrewChallenge record names), first one first.
    var challengeIDs: [String] = []
}

struct CrewGroup: Identifiable, Hashable {
    let id: String
    let leaderID: String
    let leaderName: String
    var details: GroupDetails

    static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.details == b.details }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var theme: GroupTheme { GroupTheme(rawValue: details.theme) ?? .olive }
    var font: GroupFont { GroupFont(rawValue: details.font) ?? .standard }
    @MainActor var isMine: Bool { leaderID == CrewCloud.shared.myID }
}

/// The leader's color choices. A set, so text on them always reads (white on each).
enum GroupTheme: String, CaseIterable, Identifiable {
    case olive, ocean, sunset, berry, slate, forest
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .olive: .oliveDrab
        case .ocean: Color(red: 0.05, green: 0.36, blue: 0.62)
        case .sunset: Color(red: 0.80, green: 0.33, blue: 0.10)
        case .berry: Color(red: 0.55, green: 0.12, blue: 0.40)
        case .slate: Color(red: 0.27, green: 0.31, blue: 0.36)
        case .forest: Color(red: 0.10, green: 0.40, blue: 0.20)
        }
    }
}

/// The leader's font choices. Sizes stay Rep Crew's (18 pt and up); only the style changes.
enum GroupFont: String, CaseIterable, Identifiable {
    case standard, rounded, serif, monospaced
    var id: String { rawValue }
    var title: String { rawValue == "monospaced" ? "Typewriter" : rawValue.capitalized }
    var design: Font.Design {
        switch self {
        case .standard: .default
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
    }
    func font(_ size: CGFloat, bold: Bool = false) -> Font { .system(size: size, weight: bold ? .bold : .regular, design: design) }
}

struct GroupJoinRequest: Identifiable {
    let id: String
    let requesterID: String
    let name: String
}

extension CrewSettings {
    /// Group invites you turned down, newline-separated record names (an invite is the leader's record).
    static let declinedGroupInvites = "declinedGroupInvites"
}

// MARK: - iCloud

extension CrewCloud {
    static let groupsBoard = "groups"

    /// Makes a group (id nil) or saves the leader's changes.
    func saveGroup(_ details: GroupDetails, id: String?, leaderName: String) async -> CrewGroup? {
        await connect()
        guard let myID, let json = try? JSONEncoder().encode(details), let text = String(data: json, encoding: .utf8) else { return nil }
        let groupID = id ?? "group.\(UUID().uuidString)"
        let record = CKRecord(recordType: "CrewMessage", recordID: CKRecord.ID(recordName: groupID))
        record["crewID"] = Self.groupsBoard
        record["text"] = text
        record["senderID"] = myID
        record["senderName"] = leaderName
        record["kind"] = CrewMessage.Kind.group.rawValue
        record["toID"] = CrewMessage.everyone
        record["sentAt"] = Date.now
        record["title"] = "👥 \(details.name)"
        do {
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            // The leader is the first member.
            if id == nil { _ = await joinGroup(groupID, leaderID: myID, name: leaderName) }
            return CrewGroup(id: groupID, leaderID: myID, leaderName: leaderName, details: details)
        } catch {
            status = "Couldn't save the group: \(error.localizedDescription)"
            return nil
        }
    }

    /// Every group, minus ones a coach removed and ones led by someone you blocked.
    func allGroups() async -> [CrewGroup] {
        await connect()
        let query = CKQuery(recordType: "CrewMessage", predicate: NSPredicate(format: "crewID == %@", Self.groupsBoard))
        guard let (results, _) = try? await db.records(matching: query, resultsLimit: 300) else { return [] }
        let removed = await removedMessages(crewID: Self.groupsBoard, leaderID: nil)
        return results.compactMap { try? $0.1.get() }.compactMap { record in
            guard let message = Self.message(from: record), message.kind == .group, writer(of: record) == message.senderID,
                  !removed.contains(message.id), !Blocklist.ids.contains(message.senderID),
                  let details = try? JSONDecoder().decode(GroupDetails.self, from: Data(message.text.utf8)) else { return nil }
            return CrewGroup(id: message.id, leaderID: message.senderID, leaderName: message.senderName, details: details)
        }
        .sorted { $0.details.name.localizedCaseInsensitiveCompare($1.details.name) == .orderedAscending }
    }

    /// The groups you belong to.
    func myGroups() async -> [CrewGroup] {
        await connect()
        guard let myID else { return [] }
        let query = CKQuery(recordType: "Membership", predicate: NSPredicate(format: "memberID == %@", myID))
        guard let (results, _) = try? await db.records(matching: query, resultsLimit: 300) else { return [] }
        let ids = Set(results.compactMap { try? $0.1.get() }.compactMap { $0["crewID"] as? String }.filter { $0.hasPrefix("group.") })
        guard !ids.isEmpty else { return [] }
        return await allGroups().filter { ids.contains($0.id) }
    }

    func joinGroup(_ groupID: String, leaderID: String, name: String) async -> Bool {
        await connect()
        guard let myID else { return false }
        let record = CKRecord(recordType: "Membership", recordID: CKRecord.ID(recordName: "\(groupID).\(myID)"))
        record["crewID"] = groupID
        record["leaderID"] = leaderID
        record["memberID"] = myID
        record["name"] = name
        record["crewNumber"] = UserDefaults.standard.integer(forKey: CrewSettings.crewNumber)
        do {
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            return true
        } catch {
            status = "Couldn't join the group: \(error.localizedDescription)"
            return false
        }
    }

    func leaveGroup(_ groupID: String) async -> Bool {
        await connect()
        guard let myID else { return false }
        do {
            _ = try await db.modifyRecords(saving: [], deleting: [CKRecord.ID(recordName: "\(groupID).\(myID)")])
            return true
        } catch {
            status = "Couldn't leave the group: \(error.localizedDescription)"
            return false
        }
    }

    /// Who is in the group: Membership records each member wrote for themselves.
    func groupMembers(_ groupID: String) async -> [ProfileTarget] {
        let query = CKQuery(recordType: "Membership", predicate: NSPredicate(format: "crewID == %@", groupID))
        guard let (results, _) = try? await db.records(matching: query, resultsLimit: 400) else { return [] }
        return results.compactMap { try? $0.1.get() }.compactMap { record in
            guard let id = record["memberID"] as? String, writer(of: record) == id, !Blocklist.ids.contains(id) else { return nil }
            return ProfileTarget(id: id, name: record["name"] as? String ?? "Crew member")
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Invites

    private static func inviteName(_ groupID: String, _ memberID: String) -> String { "invite.\(groupID).\(memberID)" }

    /// Leader only: invites someone. It lands in their Inbox box and notifies them.
    func inviteToGroup(_ group: CrewGroup, memberID: String, leaderName: String) async -> Bool {
        await connect()
        guard let myID, group.leaderID == myID else { return false }
        let record = CKRecord(recordType: "CrewMessage", recordID: CKRecord.ID(recordName: Self.inviteName(group.id, memberID)))
        record["crewID"] = CrewMessage.direct(to: memberID)
        record["text"] = "\(leaderName) invited you to join \(group.details.name). Open Rep Crew to accept."
        record["senderID"] = myID
        record["senderName"] = leaderName
        record["kind"] = CrewMessage.Kind.groupInvite.rawValue
        record["toID"] = memberID
        record["sentAt"] = Date.now
        record["title"] = "👥 \(leaderName) invited you"
        do {
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            return true
        } catch {
            status = "Couldn't send the invite: \(error.localizedDescription)"
            return false
        }
    }

    /// Group invites waiting for you: from the group's own leader, for groups you aren't in, not turned down.
    func groupInvites() async -> [(invite: CrewMessage, group: CrewGroup)] {
        await connect()
        guard let myID else { return [] }
        let query = CKQuery(recordType: "CrewMessage", predicate: NSPredicate(format: "crewID == %@", CrewMessage.direct(to: myID)))
        guard let (results, _) = try? await db.records(matching: query, resultsLimit: 200) else { return [] }
        let invites = results.compactMap { try? $0.1.get() }.filter { $0["kind"] as? String == CrewMessage.Kind.groupInvite.rawValue }
        guard !invites.isEmpty else { return [] }
        let declined = Set((UserDefaults.standard.string(forKey: CrewSettings.declinedGroupInvites) ?? "").split(separator: "\n").map(String.init))
        let groups = await allGroups()
        let mine = Set(await myGroups().map(\.id))
        return invites.compactMap { record in
            let name = record.recordID.recordName
            guard !declined.contains(name), let message = Self.message(from: record),
                  let group = groups.first(where: { Self.inviteName($0.id, myID) == name }),
                  writer(of: record) == group.leaderID, !mine.contains(group.id) else { return nil }
            return (message, group)
        }
    }

    static func declineGroupInvite(_ invite: CrewMessage) {
        let key = CrewSettings.declinedGroupInvites
        let old = UserDefaults.standard.string(forKey: key) ?? ""
        UserDefaults.standard.set(old.isEmpty ? invite.id : old + "\n" + invite.id, forKey: key)
    }

    // MARK: Asking to join

    private static func requestName(_ groupID: String, _ memberID: String) -> String { "join.\(groupID).\(memberID)" }

    func askToJoinGroup(_ group: CrewGroup, name: String) async -> Bool {
        await connect()
        guard let myID else { return false }
        let record = CKRecord(recordType: "JoinRequest", recordID: CKRecord.ID(recordName: Self.requestName(group.id, myID)))
        record["crewID"] = group.id
        record["leaderID"] = group.leaderID
        record["requesterID"] = myID
        record["name"] = name
        record["crewNumber"] = UserDefaults.standard.integer(forKey: CrewSettings.crewNumber)
        record["title"] = group.details.name
        record["requestedAt"] = Date.now
        do {
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            return true
        } catch {
            status = "Couldn't ask to join: \(error.localizedDescription)"
            return false
        }
    }

    /// True when you've asked this group and the leader hasn't answered.
    func hasAskedToJoin(_ group: CrewGroup) async -> Bool {
        guard let myID else { return false }
        return (try? await db.record(for: CKRecord.ID(recordName: Self.requestName(group.id, myID)))) != nil
    }

    /// Leader: requests not yet answered, from people not already in.
    func groupJoinRequests(_ group: CrewGroup) async -> [GroupJoinRequest] {
        let query = CKQuery(recordType: "JoinRequest", predicate: NSPredicate(format: "crewID == %@", group.id))
        guard let (results, _) = try? await db.records(matching: query, resultsLimit: 200) else { return [] }
        let answered = await removedMessages(crewID: group.id, leaderID: group.leaderID)
        let members = Set(await groupMembers(group.id).map(\.id))
        return results.compactMap { try? $0.1.get() }.compactMap { record in
            guard let id = record["requesterID"] as? String, writer(of: record) == id, !answered.contains(record.recordID.recordName),
                  !members.contains(id), !Blocklist.ids.contains(id) else { return nil }
            return GroupJoinRequest(id: record.recordID.recordName, requesterID: id, name: record["name"] as? String ?? "Crew member")
        }
    }

    /// Leader: approve sends the invite; either way the request is marked answered.
    func answerGroupRequest(_ request: GroupJoinRequest, group: CrewGroup, approve: Bool, leaderName: String) async -> Bool {
        await connect()
        guard let myID, group.leaderID == myID else { return false }
        if approve, await !inviteToGroup(group, memberID: request.requesterID, leaderName: leaderName) { return false }
        let record = CKRecord(recordType: "MessageRemoval", recordID: CKRecord.ID(recordName: "removed.\(request.id)"))
        record["crewID"] = group.id
        record["messageID"] = request.id
        record["removedBy"] = myID
        return (try? await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)) != nil
    }

    // MARK: Banner and avatar

    static func groupPhotoBoard(_ groupID: String, _ kind: String) -> String { "group\(kind).\(groupID)" }

    /// Leader only. `kind` is "banner" or "avatar".
    func setGroupPhoto(_ image: UIImage, group: CrewGroup, kind: String, leaderName: String) async -> Bool {
        await connect()
        guard group.isMine else { return false }
        if await ContentFilter.isSensitive(image) { return false }
        let board = Self.groupPhotoBoard(group.id, kind)
        let old = await groupPhotoRecords(board, leaderID: group.leaderID).map(\.recordID)
        guard await postPhotoID(image, crewID: board, senderName: leaderName) != nil else { return false }
        if !old.isEmpty { _ = try? await db.modifyRecords(saving: [], deleting: old) }
        return true
    }

    func groupPhoto(_ group: CrewGroup, kind: String) async -> UIImage? {
        let newest = await groupPhotoRecords(Self.groupPhotoBoard(group.id, kind), leaderID: group.leaderID)
            .filter { !Blocklist.hiddenPhotos.contains($0.recordID.recordName) }
            .max { ($0["takenAt"] as? Date ?? .distantPast) < ($1["takenAt"] as? Date ?? .distantPast) }
        let key = kind == "avatar" ? "thumb" : "image"
        guard let newest, let url = (newest[key] as? CKAsset)?.fileURL, let data = try? Data(contentsOf: url),
              let image = UIImage(data: data), await !ContentFilter.isSensitive(image) else { return nil }
        return image
    }

    private func groupPhotoRecords(_ board: String, leaderID: String) async -> [CKRecord] {
        let query = CKQuery(recordType: "CrewPhoto", predicate: NSPredicate(format: "crewID == %@", board))
        guard let (results, _) = try? await db.records(matching: query, resultsLimit: 20) else { return [] }
        return results.compactMap { try? $0.1.get() }.filter { writer(of: $0) == leaderID }
    }

    /// The group's challenges, as the crew list shows them.
    func groupChallenges(_ group: CrewGroup) async -> [CrewListing] {
        let ids = group.details.challengeIDs.map { CKRecord.ID(recordName: $0) }
        guard !ids.isEmpty, let found = try? await db.records(for: ids) else { return [] }
        return group.details.challengeIDs.compactMap { id in
            guard let record = try? found[CKRecord.ID(recordName: id)]?.get(), let invite = Self.invite(from: record),
                  let info = invite.challenge else { return nil }
            return CrewListing(info: info, leaderID: invite.fromID ?? "", leaderName: invite.from)
        }
    }
}

// MARK: - Home: swipe between your groups

/// The Smitty Bunch first, then each group you're in, one card per page. Tap a group's card for its home page.
struct GroupsPagerSection: View {
    @AppStorage(CrewSettings.crewName) private var crewName = ""
    @AppStorage(CrewSettings.name) private var myName = ""
    @State private var groups: [CrewGroup] = []
    @State private var invites: [(invite: CrewMessage, group: CrewGroup)] = []
    @State private var page = 0
    @State private var making = false
    @State private var note: String?

    /// His rule: a verified user makes groups (level 11 and up, VerifiedSeal.swift).
    private var canMake: Bool { CrewCloud.shared.effectiveLevel >= 11 }

    var body: some View {
        Section {
            TabView(selection: $page) {
                crewCard.tag(0)
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    NavigationLink(value: group) { GroupCard(group: group) }
                        .buttonStyle(.plain)
                        .tag(index + 1)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: groups.isEmpty ? .never : .always))
            .frame(height: 230)
            .listRowInsets(EdgeInsets())
            ForEach(invites, id: \.invite.id) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.invite.text).font(AppFont.body)
                    Button { Task { await accept(item.group) } } label: {
                        Label("Join \(item.group.details.name)", systemImage: "person.badge.plus").font(AppFont.bodyBold)
                    }
                    .buttonStyle(.borderless)
                    Button(role: .destructive) {
                        CrewCloud.declineGroupInvite(item.invite)
                        invites.removeAll { $0.invite.id == item.invite.id }
                    } label: {
                        Label("No Thanks", systemImage: "xmark").font(AppFont.bodyBold)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            }
            NavigationLink { FindGroupsView() } label: {
                Label("Find a Group", systemImage: "magnifyingglass").font(AppFont.bodyBold)
            }
            if canMake {
                Button { making = true } label: {
                    Label("New Group", systemImage: "person.3.fill").font(AppFont.bodyBold)
                }
            }
            if let note { Text(note).font(AppFont.body) }
        } header: {
            Text(groups.isEmpty ? "Groups" : "Your groups — swipe").font(AppFont.bodyBold).textCase(nil)
        }
        .task { await load() }
        .sheet(isPresented: $making, onDismiss: { Task { await load() } }) { GroupEditView(group: nil) }
    }

    /// The head coach's crew, as Home already shows it.
    private var crewCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.strengthtraining.traditional").font(.system(size: 44)).foregroundStyle(.white)
            Text(CrewCloud.displayName(crewName)).font(AppFont.title).foregroundStyle(.white)
            Text("Everyone on the app").font(AppFont.body).foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.oliveDrab)
    }

    private func accept(_ group: CrewGroup) async {
        let me = myName.trimmingCharacters(in: .whitespaces)
        if await CrewCloud.shared.joinGroup(group.id, leaderID: group.leaderID, name: me.isEmpty ? "A crew member" : me) {
            note = "You're in \(group.details.name)."
            await load()
        } else {
            note = "That didn't go through. Check iCloud in Settings and try again."
        }
    }

    private func load() async {
        async let mine = CrewCloud.shared.myGroups()
        async let waiting = CrewCloud.shared.groupInvites()
        groups = await mine
        invites = await waiting
        if page > groups.count { page = 0 }
    }
}

/// A group's banner, avatar and name in its own color and font.
struct GroupCard: View {
    let group: CrewGroup
    @State private var banner: UIImage?
    @State private var avatar: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let banner {
                    Image(uiImage: banner).resizable().scaledToFill()
                } else {
                    group.theme.color
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
            HStack(spacing: 12) {
                GroupAvatar(image: avatar, theme: group.theme, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.details.name).font(group.font.font(28, bold: true)).foregroundStyle(.white)
                    Text("Crew leader \(group.leaderName)").font(group.font.font(18)).foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: group) {
            banner = await CrewCloud.shared.groupPhoto(group, kind: "banner")
            avatar = await CrewCloud.shared.groupPhoto(group, kind: "avatar")
        }
        .accessibilityElement(children: .combine)
    }
}

/// Round avatar; the dumbbell when there's none, as on profiles.
struct GroupAvatar: View {
    let image: UIImage?
    let theme: GroupTheme
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "dumbbell.fill").resizable().scaledToFit().padding(size * 0.22).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .background(theme.color)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 3))
        .accessibilityHidden(true)
    }
}

// MARK: - A group's home page

struct GroupHomeView: View {
    @State var group: CrewGroup
    @AppStorage(CrewSettings.name) private var myName = ""
    @State private var members: [ProfileTarget] = []
    @State private var challenges: [CrewListing] = []
    @State private var requests: [GroupJoinRequest] = []
    @State private var asked = false
    @State private var loaded = false
    @State private var editing = false
    @State private var inviting = false
    @State private var confirmingLeave = false
    @State private var profileOf: ProfileTarget?
    @State private var note: String?

    private var me: String { myName.trimmingCharacters(in: .whitespaces).isEmpty ? "A crew member" : myName.trimmingCharacters(in: .whitespaces) }
    private var isMember: Bool { members.contains { $0.id == CrewCloud.shared.myID } }

    var body: some View {
        List {
            Section {
                GroupCard(group: group).frame(height: 220).listRowInsets(EdgeInsets())
                if !group.details.about.isEmpty { Text(group.details.about).font(group.font.font(18)) }
            }
            Section {
                if challenges.isEmpty {
                    Text(loaded ? "No challenges yet." : "Loading…").font(AppFont.body)
                }
                ForEach(challenges) { listing in
                    NavigationLink(value: listing) {
                        Text(listing.info.title).font(group.font.font(18, bold: true))
                    }
                }
            } header: {
                Text("Challenges").font(AppFont.bodyBold).textCase(nil)
            }
            Section {
                ForEach(members) { person in
                    Button { profileOf = person } label: {
                        HStack(spacing: 8) {
                            Text(person.id == CrewCloud.shared.myID ? "You" : person.name).font(AppFont.body)
                            VerifiedSeal(memberID: person.id)
                            if person.id == group.leaderID {
                                Text("Crew leader").font(AppFont.body).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Members (\(members.count))").font(AppFont.bodyBold).textCase(nil)
            }
            if group.isMine { leaderSection }
            Section {
                if group.isMine {
                    EmptyView()
                } else if isMember {
                    Button(role: .destructive) { confirmingLeave = true } label: {
                        Label("Leave \(group.details.name)", systemImage: "rectangle.portrait.and.arrow.right").font(AppFont.bodyBold)
                    }
                } else if asked {
                    Text("You asked to join. The crew leader will answer.").font(AppFont.body)
                } else if loaded {
                    Button { Task { await ask() } } label: {
                        Label("Ask to Join", systemImage: "hand.raised.fill").font(AppFont.bodyBold)
                    }
                }
                if let note { Text(note).font(AppFont.body) }
            }
        }
        .tint(group.theme.color)
        .navigationTitle(group.details.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: group) { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $editing) {
            GroupEditView(group: group) { saved in group = saved }
        }
        .sheet(isPresented: $inviting, onDismiss: { Task { await load() } }) {
            GroupInviteView(group: group, members: Set(members.map(\.id)))
        }
        .sheet(item: $profileOf) { ProfileView(target: $0) }
        .confirmationDialog("Leave \(group.details.name)?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) {
                Task {
                    note = await CrewCloud.shared.leaveGroup(group.id) ? nil : "That didn't go through. Try again."
                    await load()
                }
            }
        }
    }

    private var leaderSection: some View {
        Section {
            Button { editing = true } label: {
                Label("Edit Group", systemImage: "paintbrush.fill").font(AppFont.bodyBold)
            }
            Button { inviting = true } label: {
                Label("Invite People", systemImage: "person.badge.plus").font(AppFont.bodyBold)
            }
            ForEach(requests) { request in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(request.name) asked to join.").font(AppFont.body)
                    Button { Task { await answer(request, approve: true) } } label: {
                        Label("Approve", systemImage: "checkmark").font(AppFont.bodyBold)
                    }
                    .buttonStyle(.borderless)
                    Button(role: .destructive) { Task { await answer(request, approve: false) } } label: {
                        Label("Decline", systemImage: "xmark").font(AppFont.bodyBold)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Crew leader").font(AppFont.bodyBold).textCase(nil)
        } footer: {
            Text("Approving sends them an invite to accept.").font(AppFont.body)
        }
    }

    private func load() async {
        async let people = CrewCloud.shared.groupMembers(group.id)
        async let list = CrewCloud.shared.groupChallenges(group)
        members = await people
        challenges = await list
        if group.isMine {
            requests = await CrewCloud.shared.groupJoinRequests(group)
        } else if !isMember {
            asked = await CrewCloud.shared.hasAskedToJoin(group)
        }
        loaded = true
    }

    private func ask() async {
        if await CrewCloud.shared.askToJoinGroup(group, name: me) { asked = true } else { note = "That didn't go through. Try again." }
    }

    private func answer(_ request: GroupJoinRequest, approve: Bool) async {
        if await CrewCloud.shared.answerGroupRequest(request, group: group, approve: approve, leaderName: me) {
            note = approve ? "Invite sent to \(request.name)." : nil
            await load()
        } else {
            note = "That didn't go through. Try again."
        }
    }
}

// MARK: - Making and editing a group

struct GroupEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Challenge.startDate, order: .reverse) private var allChallenges: [Challenge]
    let group: CrewGroup?
    var saved: (CrewGroup) -> Void = { _ in }

    @AppStorage(CrewSettings.name) private var myName = ""
    @State private var details = GroupDetails()
    @State private var banner: UIImage?
    @State private var avatar: UIImage?
    @State private var pickedBanner: PhotosPickerItem?
    @State private var pickedAvatar: PhotosPickerItem?
    @State private var saving = false
    @State private var note: String?

    /// Challenges you lead that are still running: what a group can start with.
    private var yours: [Challenge] { allChallenges.filter { $0.leaderID.isEmpty && !$0.crewID.isEmpty && !$0.isFinished } }
    private var trimmedName: String { details.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !saving && !trimmedName.isEmpty && !details.challengeIDs.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Group name", text: $details.name).font(AppFont.body)
                    TextField("What the group is about", text: $details.about, axis: .vertical).font(AppFont.body).lineLimit(2...5)
                }
                Section {
                    if yours.isEmpty {
                        Text("A group starts with a challenge you lead. Start one first, then make your group with it.").font(AppFont.body)
                    }
                    ForEach(yours) { challenge in
                        Toggle(isOn: Binding(get: { details.challengeIDs.contains(challenge.crewID) }, set: { on in
                            details.challengeIDs.removeAll { $0 == challenge.crewID }
                            if on { details.challengeIDs.append(challenge.crewID) }
                        })) {
                            Text(challenge.title).font(AppFont.body)
                        }
                    }
                } header: {
                    Text("Challenges").font(AppFont.bodyBold).textCase(nil)
                } footer: {
                    Text("Pick at least one.").font(AppFont.body)
                }
                Section {
                    Picker(selection: $details.theme) {
                        ForEach(GroupTheme.allCases) { Text($0.title).font(AppFont.body).tag($0.rawValue) }
                    } label: { Text("Color").font(AppFont.body) }
                    Picker(selection: $details.font) {
                        ForEach(GroupFont.allCases) { Text($0.title).font($0.font(18)).tag($0.rawValue) }
                    } label: { Text("Font").font(AppFont.body) }
                    PhotosPicker(selection: $pickedBanner, matching: .images) {
                        Label(banner == nil ? "Choose Banner" : "Banner Chosen", systemImage: "rectangle.on.rectangle").font(AppFont.bodyBold)
                    }
                    PhotosPicker(selection: $pickedAvatar, matching: .images) {
                        Label(avatar == nil ? "Choose Avatar" : "Avatar Chosen", systemImage: "person.crop.circle").font(AppFont.bodyBold)
                    }
                } header: {
                    Text("Look").font(AppFont.bodyBold).textCase(nil)
                } footer: {
                    Text("Without a banner or avatar the group gets its color and a dumbbell.").font(AppFont.body)
                }
                if let note { Section { Text(note).font(AppFont.body) } }
            }
            .navigationTitle(group == nil ? "New Group" : "Edit Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.font(AppFont.body) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(group == nil ? "Make Group" : "Save") { Task { await save() } }
                        .font(AppFont.bodyBold).disabled(!canSave)
                }
            }
            .onAppear {
                if let group, details == GroupDetails() { details = group.details }
            }
            .onChange(of: pickedBanner) { _, item in Task { banner = await load(item); pickedBanner = nil } }
            .onChange(of: pickedAvatar) { _, item in Task { avatar = await load(item); pickedAvatar = nil } }
        }
    }

    private func load(_ item: PhotosPickerItem?) async -> UIImage? {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return UIImage(data: data)
    }

    private func save() async {
        saving = true
        note = nil
        details.name = trimmedName
        let me = myName.trimmingCharacters(in: .whitespaces).isEmpty ? "A crew member" : myName.trimmingCharacters(in: .whitespaces)
        guard let result = await CrewCloud.shared.saveGroup(details, id: group?.id, leaderName: me) else {
            note = "It didn't save. Check iCloud in Settings and try again."
            saving = false
            return
        }
        var photoFailed = false
        if let banner, await !CrewCloud.shared.setGroupPhoto(banner, group: result, kind: "banner", leaderName: me) { photoFailed = true }
        if let avatar, await !CrewCloud.shared.setGroupPhoto(avatar, group: result, kind: "avatar", leaderName: me) { photoFailed = true }
        saved(result)
        saving = false
        if photoFailed {
            note = "The group saved, but a picture can't be used or didn't upload."
        } else {
            dismiss()
        }
    }
}

// MARK: - Inviting

private struct GroupInviteView: View {
    @Environment(\.dismiss) private var dismiss
    let group: CrewGroup
    let members: Set<String>
    @AppStorage(CrewSettings.name) private var myName = ""
    @State private var people: [CrewUser] = []
    @State private var loaded = false
    @State private var sent: Set<String> = []
    @State private var failed = false

    var body: some View {
        NavigationStack {
            List {
                if !loaded {
                    HStack(spacing: 12) { ProgressView(); Text("Loading…").font(AppFont.body) }
                }
                ForEach(people) { person in
                    Button {
                        Task {
                            let me = myName.trimmingCharacters(in: .whitespaces)
                            if await CrewCloud.shared.inviteToGroup(group, memberID: person.id, leaderName: me.isEmpty ? "A crew leader" : me) {
                                sent.insert(person.id)
                            } else {
                                failed = true
                            }
                        }
                    } label: {
                        HStack {
                            Text(person.name).font(AppFont.body)
                            Spacer()
                            Text(sent.contains(person.id) ? "Invited" : "Invite").font(AppFont.bodyBold)
                        }
                    }
                    .disabled(sent.contains(person.id))
                }
                if failed { Text("An invite didn't go through. Try again.").font(AppFont.body) }
            }
            .navigationTitle("Invite People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.font(AppFont.bodyBold) } }
            .task {
                people = await CrewCloud.shared.allUsers()
                    .filter { !members.contains($0.id) && $0.id != CrewCloud.shared.myID && !Blocklist.ids.contains($0.id) }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                loaded = true
            }
        }
    }
}

// MARK: - Finding a group

struct FindGroupsView: View {
    @State private var groups: [CrewGroup] = []
    @State private var loaded = false

    var body: some View {
        List {
            if groups.isEmpty {
                Text(loaded ? "No groups yet." : "Loading…").font(AppFont.body)
            }
            ForEach(groups) { group in
                NavigationLink(value: group) {
                    HStack(spacing: 12) {
                        GroupAvatar(image: nil, theme: group.theme, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.details.name).font(group.font.font(18, bold: true))
                            Text("Crew leader \(group.leaderName)").font(AppFont.body).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Find a Group")
        .task {
            groups = await CrewCloud.shared.allGroups()
            loaded = true
        }
        .refreshable { groups = await CrewCloud.shared.allGroups() }
    }
}
