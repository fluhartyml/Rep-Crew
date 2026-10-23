//
//  SettingsView.swift
//  Rep Crew
//
//  Your name, the TestFlight invite link, and your crew. Crew member 0 types the link in
//  once; everyone after gets it filled in when they join an invite.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CrewMember.addedAt) private var crew: [CrewMember]

    @AppStorage(CrewSettings.name) private var name = ""
    @AppStorage(CrewSettings.testFlight) private var testFlight = ""
    @AppStorage(CrewSettings.crewNumber) private var crewNumber = 0
    /// Checked against iCloud when Settings opens, not left to whenever iCloud answers.
    @State private var isGod = false

    private var linkIsValid: Bool { Invite.isTestFlightLink(testFlight) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your first name", text: $name)
                        .font(AppFont.body)
                        .textContentType(.givenName)
                } header: {
                    header("You")
                } footer: {
                    Text("Your crew sees this name on your invites. You are crew member \(crewNumber).")
                        .font(AppFont.body)
                }

                Section {
                    TextField("https://testflight.apple.com/join/…", text: $testFlight, axis: .vertical)
                        .font(AppFont.body)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    header("TestFlight invite link")
                } footer: {
                    Text(linkFooter).font(AppFont.body)
                }

                // REM: His word 2026-10-22: "yes remove it" — Invite to Crew is gone; Share Challenge on
                // each challenge carries the join link.

                Section {
                    if crew.isEmpty {
                        // REM: his wording 2026-10-22 — the old "People whose invites you join" read two ways.
                        Text("No one yet. Your accepted invites show here.").font(AppFont.body)
                    } else {
                        ForEach(crew) { member in
                            HStack {
                                Text(member.name).font(AppFont.bodyBold)
                                Spacer()
                                Text("Crew member \(member.crewNumber)").font(AppFont.body)
                            }
                        }
                    }
                } header: {
                    header("Your crew")
                }

                BlockedPeopleSection()
                GodModeSection(isOn: isGod)

                Section {
                    Text(CrewCloud.shared.status).font(AppFont.body)
                } header: {
                    header("iCloud")
                }
            }
            .navigationTitle("Settings")
            .task {
                await CrewCloud.shared.connect()
                isGod = GodMode.isOn
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(AppFont.bodyBold)
                }
            }
        }
    }

    private var linkFooter: String {
        if testFlight.isEmpty { return "Invites use Rep Crew's public TestFlight link. Paste a different one here to override it." }
        return linkIsValid ? "Every invite you send includes this link." : "This doesn't look like a TestFlight link. It should start with https://testflight.apple.com/join/"
    }

    private func header(_ text: String) -> some View {
        Text(text).font(AppFont.bodyBold).textCase(nil)
    }
}
