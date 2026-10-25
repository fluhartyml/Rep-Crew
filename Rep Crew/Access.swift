//
//  Access.swift
//  Rep Crew
//
//  Access levels 0–255 and letter flags, after Renegade BBS's ACS. His words, 2026-10-24: "a table
//  with 0 to 255 access levels and letter flags that had probably 26 different meanings defined by
//  the sysop" · "have your table as shown BUT have ranges set per line like 0-5 new user but no
//  application submitted 6-10 new user application not verified 11-15 verified new user and so on
//  all configurable by the head coach" · "yes".
//
//  REM: two record kinds in the shared space, both honored only when CloudKit says who wrote them:
//    AccessTable  name = "access". The bands (low–high, name, what they allow) and the flag letters'
//                 meanings. Head coach only (GodMode.ids).
//    MemberAccess name = "access.<member ID>". One member's level, flags and title. Head coach only.
//  A member can't raise their own level: a record they wrote themselves is ignored.
//  REM: THE LOWER LEVELS ARE EARNED, NOT GRANTED. His words, 2026-10-24: "i want to promote use so i
//  want the lower access levels to be automatic where the upper moderator above is more manual
//  moderator is probably the last automatic level because a moderator starts their own challenge"
//  · "yes build it sounds awesome". Each step comes from something the member did, read from iCloud:
//    0   signed in
//    6   application in (Send or Not Now; both write the CrewApplication record)
//    11  application sent with an email (the "verified new user" line, and the first that posts)
//    16  joined someone's challenge (a Membership record they wrote)
//    55  started their own challenge (a CrewChallenge they lead), the last automatic step
//  Coach (250+) and Head Coach (255) stay by hand. 50–54 "Message base member" has no automatic step.
//  REM: a member's level is the HIGHER of what they earned and what the head coach set, so editing
//  someone's title never freezes them. To hold someone back, give them a flag that blocks the command
//  (Access Levels → command keys). Only records the member wrote themselves count toward what they earned;
//  forging one is the same as doing the thing, so it buys nothing.
//  REM: Claude's default abilities, not his: new and unverified members (0–10) can still keep and
//  join challenges, so nobody already testing loses that, but they can't post crew messages until
//  they reach 11. He can change every line.
//  ⚠️ The phone checks the abilities before showing a button. CloudKit's public database can't
//  enforce them on its own, so this keeps honest people on the right side, like the rest of the app.
//

import CloudKit
import SwiftUI

/// What a band of levels allows. The head coach picks these per band.
enum AccessAbility: String, Codable, CaseIterable, Identifiable {
    // REM: moderating and Coach Mode are NOT abilities here. The shared space honors a removal or ban
    // only from a leader, a coach or the head coach (isModerator, checked against who wrote it), so a
    // level can't grant them yet; a button for it would do nothing. Coaches are still made by long-press,
    // and their level shows as at least 250.
    case join, start, post, photos
    var id: String { rawValue }
    var label: String {
        switch self {
        case .join: "Join crew challenges"
        case .start: "Start challenges"
        case .post: "Post crew messages"
        case .photos: "Post photos"
        }
    }
}

struct AccessBand: Codable, Identifiable, Equatable {
    var id = UUID()
    var low: Int
    var high: Int
    var name: String
    var abilities: Set<AccessAbility>
}

/// A command's keys, Renegade style. His word 2026-10-24: "you had to have a key flagged to use a menu
/// command or if you had another key flagged you were denied access … like x you were allowed to log in
/// but you were not allowed to do any menu command". Letters: needs ALL of `requires`, NONE of `blockedBy`.
struct AccessKeys: Codable, Equatable {
    var requires = ""
    var blockedBy = ""
}

struct AccessFlag: Codable, Identifiable, Equatable {
    var id: String { letter }
    var letter: String
    var meaning: String
}

struct AccessTable: Codable, Equatable {
    var bands: [AccessBand]
    var flags: [AccessFlag]
    /// Per command (AccessAbility raw value). Missing = no keys needed. Optional so older saved tables still read.
    var keys: [String: AccessKeys]? = nil

    static let starter = AccessTable(bands: [
        AccessBand(low: 0, high: 5, name: "New user, no application", abilities: [.join, .start, .photos]),
        AccessBand(low: 6, high: 10, name: "New user, application not verified", abilities: [.join, .start, .photos]),
        AccessBand(low: 11, high: 15, name: "Verified new user", abilities: [.join, .start, .post, .photos]),
        AccessBand(low: 16, high: 49, name: "Member", abilities: [.join, .start, .post, .photos]),
        AccessBand(low: 50, high: 54, name: "Message base member", abilities: [.join, .start, .post, .photos]),
        AccessBand(low: 55, high: 249, name: "Moderator", abilities: [.join, .start, .post, .photos]),
        AccessBand(low: 250, high: 254, name: "Coach", abilities: [.join, .start, .post, .photos]),
        AccessBand(low: 255, high: 255, name: "Head Coach", abilities: Set(AccessAbility.allCases)),
    ], flags: [])

    func band(for level: Int) -> AccessBand? { bands.first { (min($0.low, $0.high)...max($0.low, $0.high)).contains(level) } }
}

/// One member's place in the table.
struct MemberAccess: Equatable {
    var level: Int
    var flags: String     // letters, e.g. "PZ"
    var title: String     // e.g. "Black Belt"
}

extension CrewSettings {
    static let accessTable = "accessTable"
}

extension CrewCloud {
    private static let tableID = CKRecord.ID(recordName: "access")
    private static func memberID(_ id: String) -> CKRecord.ID { CKRecord.ID(recordName: "access.\(id)") }

    /// The table: from iCloud when the head coach wrote it, else the copy on this phone, else the starter.
    var accessTable: AccessTable {
        guard let text = UserDefaults.standard.string(forKey: CrewSettings.accessTable),
              let table = try? JSONDecoder().decode(AccessTable.self, from: Data(text.utf8)) else { return .starter }
        return table
    }

    func loadAccess() async {
        if let record = try? await db.record(for: Self.tableID), let writer = writer(of: record), GodMode.ids.contains(writer),
           let text = record["table"] as? String {
            UserDefaults.standard.set(text, forKey: CrewSettings.accessTable)
        }
        if let myID { myAccess = await memberAccess(myID) }
    }

    func saveAccessTable(_ table: AccessTable) async -> Bool {
        guard GodMode.isOwner, let data = try? JSONEncoder().encode(table), let text = String(data: data, encoding: .utf8) else { return false }
        let record = (try? await db.record(for: Self.tableID)) ?? CKRecord(recordType: "AccessTable", recordID: Self.tableID)
        record["table"] = text
        do {
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
            UserDefaults.standard.set(text, forKey: CrewSettings.accessTable)
            return true
        } catch {
            status = "Couldn't save the access table: \(error.localizedDescription)"
            return false
        }
    }

    /// Someone's level, flags and title: the higher of what they earned and what the head coach set.
    /// Only a MemberAccess record the head coach wrote counts.
    func memberAccess(_ id: String) async -> MemberAccess {
        var access = MemberAccess(level: 0, flags: "", title: "")
        if let record = try? await db.record(for: Self.memberID(id)), let writer = writer(of: record), GodMode.ids.contains(writer) {
            access = MemberAccess(level: record["level"] as? Int ?? 0, flags: record["flags"] as? String ?? "",
                                  title: record["title"] as? String ?? "")
        }
        access.level = max(access.level, await earnedLevel(id))
        if coaches[id] != nil { access.level = max(access.level, 250) }
        if GodMode.ids.contains(id) { access.level = 255 }
        return access
    }

    /// The level someone reached by using the app (the steps in the REM at the top). Highest step first.
    func earnedLevel(_ id: String) async -> Int {
        if await wroteAny("CrewChallenge", NSPredicate(format: "leaderID == %@", id), as: id) { return 55 }
        if await wroteAny("Membership", NSPredicate(format: "memberID == %@", id), as: id) { return 16 }
        let defaults = UserDefaults.standard
        if id == myID, defaults.bool(forKey: CrewSettings.applicationEmailGiven) { return 11 }
        if let record = try? await db.record(for: CKRecord.ID(recordName: "application.\(id)")), writer(of: record) == id {
            // A coach's phone can open the application and see whether an email came with it.
            if let myID, let key = ContactKey.mine(create: false), let sealed = record["sealed"] as? Data,
               let answers = ContactSeal.open(CrewApplication.self, sealed, for: myID, key: key), !answers.email.isEmpty { return 11 }
            return 6
        }
        if id == myID, defaults.bool(forKey: CrewSettings.applicationDone) { return 6 }
        return 0
    }

    /// True when the member wrote at least one record of this type matching the predicate.
    private func wroteAny(_ type: String, _ predicate: NSPredicate, as id: String) async -> Bool {
        guard let (results, _) = try? await db.records(matching: CKQuery(recordType: type, predicate: predicate), resultsLimit: 20)
        else { return false }
        return results.compactMap { try? $0.1.get() }.contains { writer(of: $0) == id }
    }

    /// Re-reads this phone's member's level after they did something that may have raised it.
    func refreshMyAccess() async {
        if let myID { myAccess = await memberAccess(myID) }
    }

    func saveMemberAccess(_ access: MemberAccess, for id: String) async -> Bool {
        guard GodMode.isOwner else { return false }
        let record = (try? await db.record(for: Self.memberID(id))) ?? CKRecord(recordType: "MemberAccess", recordID: Self.memberID(id))
        record["memberID"] = id
        record["level"] = min(max(access.level, 0), 255)
        record["flags"] = String(Set(access.flags.uppercased().filter(\.isLetter)).sorted())
        record["title"] = access.title.trimmingCharacters(in: .whitespaces)
        do {
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
            if id == myID { myAccess = await memberAccess(id) }
            return true
        } catch {
            status = "Couldn't save access: \(error.localizedDescription)"
            return false
        }
    }

    /// True when this phone's member may do it.
    func can(_ ability: AccessAbility) -> Bool {
        if GodMode.isOwner { return true }
        let table = accessTable
        guard table.band(for: myAccess.level)?.abilities.contains(ability) ?? false else { return false }
        let mine = Set(myAccess.flags.uppercased())
        let keys = table.keys?[ability.rawValue] ?? AccessKeys()
        return Set(keys.requires.uppercased()).isSubset(of: mine) && Set(keys.blockedBy.uppercased()).isDisjoint(with: mine)
    }
}

// MARK: - Coach Mode → Access Levels

struct AccessTableView: View {
    @State private var table = CrewCloud.shared.accessTable
    @State private var note: String?

    var body: some View {
        Form {
            Section {
                ForEach($table.bands) { $band in
                    NavigationLink {
                        AccessBandView(band: $band)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(band.low)–\(band.high)  \(band.name)").font(AppFont.bodyBold)
                            Text(band.abilities.isEmpty ? "Nothing allowed"
                                 : AccessAbility.allCases.filter(band.abilities.contains).map(\.label).joined(separator: ", "))
                                .font(AppFont.body).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { table.bands.remove(atOffsets: $0) }
                Button("Add a Range") {
                    let next = min((table.bands.map(\.high).max() ?? -1) + 1, 255)
                    table.bands.append(AccessBand(low: next, high: next, name: "New range", abilities: []))
                }
                .font(AppFont.body)
            } header: {
                Text("Levels 0–255").font(AppFont.bodyBold).textCase(nil)
            }

            Section {
                ForEach(AccessAbility.allCases) { ability in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ability.label).font(AppFont.bodyBold)
                        TextField("Needs flags, like Z", text: keyBinding(ability, \.requires))
                            .font(AppFont.body).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        TextField("Blocked by flags, like X", text: keyBinding(ability, \.blockedBy))
                            .font(AppFont.body).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Command Keys").font(AppFont.bodyBold).textCase(nil)
            } footer: {
                Text("A member needs every \"needs\" letter and none of the \"blocked by\" letters, plus a range that allows the command. Put X in every \"blocked by\" to let someone sign in and look without doing anything.")
                    .font(AppFont.body)
            }

            Section {
                ForEach($table.flags) { $flag in
                    HStack {
                        Text(flag.letter).font(AppFont.heading).frame(width: 32)
                        TextField("What \(flag.letter) means", text: $flag.meaning).font(AppFont.body)
                    }
                }
                .onDelete { table.flags.remove(atOffsets: $0) }
                Menu("Add a Flag") {
                    ForEach(Self.letters.filter { letter in !table.flags.contains { $0.letter == letter } }, id: \.self) { letter in
                        Button(letter) { table.flags.append(AccessFlag(letter: letter, meaning: "")) }
                    }
                }
                .font(AppFont.body)
            } header: {
                Text("Flags A–Z").font(AppFont.bodyBold).textCase(nil)
            } footer: {
                Text("Each letter means whatever you decide. Set a member's level, flags and title from their profile. Levels 250 and up are coaches, made with a long-press in Coaches.")
                    .font(AppFont.body)
            }

            Section {
                Button {
                    Task { note = await CrewCloud.shared.saveAccessTable(table) ? "Saved for the whole crew." : "Couldn't save. Check Settings → iCloud." }
                } label: {
                    Text("Save").font(AppFont.bodyBold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                if let note { Text(note).font(AppFont.body) }
                Button("Start Over with the Starter Table") { table = .starter }.font(AppFont.body)
            }
        }
        .navigationTitle("Access Levels")
    }

    static let letters = (65...90).map { String(UnicodeScalar($0)!) }

    private func keyBinding(_ ability: AccessAbility, _ path: WritableKeyPath<AccessKeys, String>) -> Binding<String> {
        Binding(get: { table.keys?[ability.rawValue]?[keyPath: path] ?? "" },
                set: { text in
                    var keys = table.keys ?? [:]
                    var entry = keys[ability.rawValue] ?? AccessKeys()
                    entry[keyPath: path] = String(Set(text.uppercased().filter(\.isLetter)).sorted())
                    keys[ability.rawValue] = entry
                    table.keys = keys
                })
    }
}

private struct AccessBandView: View {
    @Binding var band: AccessBand

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $band.name).font(AppFont.body)
                Stepper("From \(band.low)", value: $band.low, in: 0...255).font(AppFont.body)
                Stepper("To \(band.high)", value: $band.high, in: 0...255).font(AppFont.body)
            } header: {
                Text("Range").font(AppFont.bodyBold).textCase(nil)
            }
            Section {
                ForEach(AccessAbility.allCases) { ability in
                    Toggle(isOn: Binding(get: { band.abilities.contains(ability) },
                                         set: { if $0 { band.abilities.insert(ability) } else { band.abilities.remove(ability) } })) {
                        Text(ability.label).font(AppFont.body)
                    }
                }
            } header: {
                Text("Allowed").font(AppFont.bodyBold).textCase(nil)
            }
        }
        .navigationTitle(band.name)
    }
}

// MARK: - On a profile

/// Everyone sees a member's title and range; the head coach can change them here.
struct MemberAccessSection: View {
    let memberID: String
    /// Shown in Coach Mode → Coaches when a level of 250 or more makes them a coach.
    var name = ""
    @State private var access = MemberAccess(level: 0, flags: "", title: "")
    @State private var loaded = false
    @State private var note: String?

    /// 255 is the head coach alone (GodMode.ids), so a member tops out at 254.
    static let highest = 254
    static let coachLevel = 250

    var body: some View {
        Section {
            let table = CrewCloud.shared.accessTable
            if !access.title.isEmpty { Text(access.title).font(AppFont.bodyBold) }
            Text("Level \(access.level) · \(table.band(for: access.level)?.name ?? "No range set")").font(AppFont.body)
            if !access.flags.isEmpty {
                Text("Flags \(access.flags)").font(AppFont.body).foregroundStyle(.secondary)
            }
            if GodMode.isOwner && loaded && !GodMode.ids.contains(memberID) {
                // REM: his word 2026-10-25: "the up and down arrow should snap to the pre defined access levels and
                // there should also be a number input box so you can fine adjust the levels … one point advantage
                // over two coaches so one could have seniority". The arrows stopped at 249, so he couldn't make
                // James a coach. Arrows jump to the start of each range; the box takes any level 0–254.
                HStack {
                    Text("Level").font(AppFont.body)
                    TextField("0", value: $access.level, format: .number)
                        .font(AppFont.bodyBold)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 72)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: access.level) { _, level in
                            let clamped = min(max(level, 0), Self.highest)
                            if clamped != level { access.level = clamped }
                        }
                    Spacer()
                    Stepper("Level", onIncrement: { access.level = Self.nextStart(above: access.level, in: table) },
                            onDecrement: { access.level = Self.previousStart(below: access.level, in: table) })
                        .labelsHidden()
                }
                TextField("Title, like Team Leader", text: $access.title).font(AppFont.body)
                TextField("Flags, like PZ", text: $access.flags)
                    .font(AppFont.body)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Save Access") { Task { await save() } }
                    .font(AppFont.bodyBold)
                if let note { Text(note).font(AppFont.body) }
            }
        } header: {
            Text("Access").font(AppFont.bodyBold).textCase(nil)
        } footer: {
            if GodMode.isOwner && loaded && !GodMode.ids.contains(memberID) {
                Text("The arrows jump to the start of each range. Type a number to set any level up to \(Self.highest). Level \(Self.coachLevel) or higher makes them a coach; lower takes it back.")
                    .font(AppFont.body)
            }
        }
        .task {
            access = await CrewCloud.shared.memberAccess(memberID)
            loaded = true
        }
    }

    /// REM: coach powers come from the CoachGrant list (GodMode.swift), not the level, so a level that
    /// crosses 250 also grants or takes back coach. Otherwise "Coach" would show with no powers.
    private func save() async {
        let cloud = CrewCloud.shared
        guard await cloud.saveMemberAccess(access, for: memberID) else {
            note = "Couldn't save. Check Settings → iCloud."
            return
        }
        let isCoach = cloud.coaches[memberID] != nil
        let wantsCoach = access.level >= Self.coachLevel
        if wantsCoach != isCoach {
            let label = access.title.trimmingCharacters(in: .whitespaces)
            guard await cloud.setCoach(memberID, name: name.isEmpty ? (label.isEmpty ? "Coach" : label) : name, on: wantsCoach) else {
                note = "Level saved, but the coach change didn't go through. Check Settings → iCloud."
                return
            }
        }
        access = await cloud.memberAccess(memberID)
        note = wantsCoach && !isCoach ? "Saved. They're a coach now." : (!wantsCoach && isCoach ? "Saved. They're no longer a coach." : "Saved.")
    }

    /// The starts of the table's ranges a member can hold, low to high, always including 0.
    private static func starts(_ table: AccessTable) -> [Int] {
        Array(Set([0] + table.bands.map { min($0.low, $0.high) }.filter { $0 <= highest })).sorted()
    }

    static func nextStart(above level: Int, in table: AccessTable) -> Int {
        starts(table).first { $0 > level } ?? highest
    }

    static func previousStart(below level: Int, in table: AccessTable) -> Int {
        starts(table).last { $0 < level } ?? 0
    }
}
