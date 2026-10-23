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

    private var linkIsValid: Bool { Invite.isTestFlightLink(testFlight) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

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

                Section {
                    if let invite = crewInvite {
                        ShareLink(item: invite.message) {
                            Label("Invite to Crew", systemImage: "person.badge.plus").font(AppFont.bodyBold)
                        }
                    } else {
                        Text("Add your name and the TestFlight link to send invites.").font(AppFont.body)
                    }
                }

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

                Section {
                    Text(CrewCloud.shared.status).font(AppFont.body)
                } header: {
                    header("iCloud")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(AppFont.bodyBold)
                }
            }
        }
    }

    private var linkFooter: String {
        if testFlight.isEmpty { return "Paste Rep Crew's TestFlight public link. It goes into every invite you send." }
        return linkIsValid ? "Every invite you send includes this link." : "This doesn't look like a TestFlight link. It should start with https://testflight.apple.com/join/"
    }

    /// An invite to the crew with no challenge attached.
    private var crewInvite: Invite? {
        guard linkIsValid, !trimmedName.isEmpty else { return nil }
        return Invite(from: trimmedName, crewNumber: crewNumber, testFlight: testFlight.trimmingCharacters(in: .whitespaces),
                      challenge: nil, fromID: CrewCloud.shared.myID)
    }

    private func header(_ text: String) -> some View {
        Text(text).font(AppFont.bodyBold).textCase(nil)
    }
}
