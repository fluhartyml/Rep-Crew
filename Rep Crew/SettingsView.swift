//
//  SettingsView.swift
//  Rep Crew
//
//  Your name and profile, the TestFlight invite link, and your crew. Crew member 0 types the link in
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
                // REM: his word 2026-10-24, "it should be obviously displayed at the top" · "yes move it to the top".
                GodModeSection(isOn: isGod)

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

                MyProfileSection()

                Section {
                    NavigationLink { HealthMatchView() } label: {
                        Text("Match Health Workouts").font(AppFont.bodyBold)
                    }
                } header: {
                    header("Health")
                } footer: {
                    Text("Pair workouts other apps saved to Health with your Rep Crew exercises, and pick how they count.")
                        .font(AppFont.body)
                }

                Section {
                    NavigationLink { NotificationSettingsView() } label: {
                        Text("Notifications").font(AppFont.bodyBold)
                    }
                } header: {
                    header("Notifications")
                } footer: {
                    Text("Pick which challenges and notices reach this phone.").font(AppFont.body)
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

                Section {
                    Text(CrewCloud.shared.status).font(AppFont.body)
                    // Set when the app opens (RepCrewApp.container).
                    Text(UserDefaults.standard.bool(forKey: "storeNotInICloud")
                         ? "Your challenges are on this phone only right now. They'll back up to iCloud once it's available."
                         : "Your challenges and reps are set to sync with your iCloud.")
                        .font(AppFont.body).foregroundStyle(.secondary)
                } header: {
                    header("iCloud")
                }
            }
            .navigationTitle("Settings")
            .task {
                await CrewCloud.shared.connect()
                isGod = GodMode.isOn
                await MyProfile.restoreIfNeeded()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(AppFont.bodyBold)
                }
            }
            // REM: saved once when Settings closes, not on every keystroke.
            .onDisappear { Task { await MyProfile.saveIfChanged() } }
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
