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
//  REM: with no MemberAccess record, a member is level 0, or 6 once their application is in (the
//  bands' defaults). Coaches are at least 250 and the head coach is 255, whatever the table says.
//  REM: Claude's default abilities, not his: new and unverified members (0–10) can still keep and
//  join challenges, so nobody already testing loses that, but they can't post crew messages until
//  the head coach raises them to 11 or higher. He can change every line.
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
    case join, start, post
    var id: String { rawValue }
    var label: String {
        switch self {
        case .join: "Join crew challenges"
        case .start: "Start challenges"
        case .post: "Post crew messages"
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

struct AccessFlag: Codable, Identifiable, Equatable {
    var id: String { letter }
    var letter: String
    var meaning: String
}

struct AccessTable: Codable, Equatable {
    var bands: [AccessBand]
    var flags: [AccessFlag]

    static let starter = AccessTable(bands: [
        AccessBand(low: 0, high: 5, name: "New user, no application", abilities: [.join, .start]),
        AccessBand(low: 6, high: 10, name: "New user, application not verified", abilities: [.join, .start]),
        AccessBand(low: 11, high: 15, name: "Verified new user", abilities: [.join, .start, .post]),
        AccessBand(low: 16, high: 49, name: "Member", abilities: [.join, .start, .post]),
        AccessBand(low: 50, high: 54, name: "Message base member", abilities: [.join, .start, .post]),
        AccessBand(low: 55, high: 249, name: "Moderator", abilities: [.join, .start, .post]),
        AccessBand(low: 250, high: 254, name: "Coach", abilities: [.join, .start, .post]),
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

    /// Someone's level, flags and title. Only a record the head coach wrote counts.
    func memberAccess(_ id: String) async -> MemberAccess {
        var access = MemberAccess(level: 0, flags: "", title: "")
        if let record = try? await db.record(for: Self.memberID(id)), let writer = writer(of: record), GodMode.ids.contains(writer) {
            access = MemberAccess(level: record["level"] as? Int ?? 0, flags: record["flags"] as? String ?? "",
                                  title: record["title"] as? String ?? "")
        } else if id == myID, UserDefaults.standard.bool(forKey: CrewSettings.applicationDone) {
            access.level = 6
        }
        if coaches[id] != nil { access.level = max(access.level, 250) }
        if GodMode.ids.contains(id) { access.level = 255 }
        return access
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
        return accessTable.band(for: myAccess.level)?.abilities.contains(ability) ?? false
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
    @State private var access = MemberAccess(level: 0, flags: "", title: "")
    @State private var loaded = false
    @State private var note: String?

    var body: some View {
        Section {
            let table = CrewCloud.shared.accessTable
            if !access.title.isEmpty { Text(access.title).font(AppFont.bodyBold) }
            Text("Level \(access.level) · \(table.band(for: access.level)?.name ?? "No range set")").font(AppFont.body)
            if !access.flags.isEmpty {
                Text("Flags \(access.flags)").font(AppFont.body).foregroundStyle(.secondary)
            }
            if GodMode.isOwner && loaded && !GodMode.ids.contains(memberID) {
                Stepper("Level \(access.level)", value: $access.level, in: 0...249).font(AppFont.body)
                TextField("Title, like Team Leader", text: $access.title).font(AppFont.body)
                TextField("Flags, like PZ", text: $access.flags)
                    .font(AppFont.body)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Save Access") {
                    Task { note = await CrewCloud.shared.saveMemberAccess(access, for: memberID) ? "Saved." : "Couldn't save. Check Settings → iCloud." }
                }
                .font(AppFont.bodyBold)
                if let note { Text(note).font(AppFont.body) }
            }
        } header: {
            Text("Access").font(AppFont.bodyBold).textCase(nil)
        }
        .task {
            access = await CrewCloud.shared.memberAccess(memberID)
            loaded = true
        }
    }
}
