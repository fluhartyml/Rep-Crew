//
//  CrewName.swift
//  Rep Crew
//
//  The head coach names the crew, the way a sysop named the board. His words, 2026-10-24: "the head
//  coach should be able to make this app their own and welcome to the {dailyrepcrew} should be
//  configurable to any name … or whatever name the head coach decides" · "yes build it".
//
//  REM: one CrewBoard record (name = "board") in the shared space, honored only when CloudKit says
//  the head coach wrote it (GodMode.ids), so nobody else can rename the crew. Shown on Home and on
//  the welcome screen. Blank means the app's own name, Rep Crew. Kept on the phone too, so it shows
//  before iCloud answers.
//

import CloudKit
import SwiftUI

extension CrewSettings {
    static let crewName = "crewName"
}

extension CrewCloud {
    /// The crew's name as screens show it. Views read the setting with @AppStorage so they update when it loads.
    static func displayName(_ saved: String) -> String {
        let name = saved.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Rep Crew" : name
    }

    private static let boardID = CKRecord.ID(recordName: "board")

    func loadCrewName() async {
        guard let record = try? await db.record(for: Self.boardID),
              let writer = writer(of: record), GodMode.ids.contains(writer) else { return }
        UserDefaults.standard.set(record["name"] as? String ?? "", forKey: CrewSettings.crewName)
    }

    /// Head coach only. True when it was saved.
    func saveCrewName(_ name: String) async -> Bool {
        await connect()
        guard GodMode.isOwner else { return false }
        let record = (try? await db.record(for: Self.boardID)) ?? CKRecord(recordType: "CrewBoard", recordID: Self.boardID)
        record["name"] = name.trimmingCharacters(in: .whitespaces)
        do {
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
            UserDefaults.standard.set(name.trimmingCharacters(in: .whitespaces), forKey: CrewSettings.crewName)
            return true
        } catch {
            status = "Couldn't save the crew name: \(error.localizedDescription)"
            return false
        }
    }
}

/// Coach Mode → Crew Name.
struct CrewNameView: View {
    @AppStorage(CrewSettings.crewName) private var saved = ""
    @State private var typed = ""
    @State private var result: String?

    var body: some View {
        Form {
            Section {
                TextField("Your crew's name", text: $typed)
                    .font(AppFont.heading)
                Button {
                    Task {
                        result = await CrewCloud.shared.saveCrewName(typed)
                            ? "Saved. Every phone in your crew shows it the next time it opens."
                            : "Couldn't save it. Check Settings → iCloud."
                    }
                } label: {
                    Text("Save").font(AppFont.bodyBold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(typed.trimmingCharacters(in: .whitespaces) == saved)
                if let result { Text(result).font(AppFont.body) }
            } footer: {
                Text("Shown at the top of Home and on the welcome screen for new members. Leave it blank to use Rep Crew.")
                    .font(AppFont.body)
            }
        }
        .navigationTitle("Crew Name")
        .onAppear { typed = saved }
    }
}
