//
//  Application.swift
//  Rep Crew
//
//  The new member's application, after the old BBS: a new user wrote to the sysop to introduce
//  themselves, and the sysop sent back a welcome letter written once when the board went up.
//  His words, 2026-10-24: "maybe it asks what the new users goals are why the new crew member wants
//  access to the app does the crew member have fitness goals does the new crew member have any
//  suggestions to improve the onboarding experience" · "maybe the new user application is
//  integrated with their new profile? maybe they enter some information to populate their profile
//  and some just goes to the head coach" · "not a gate at least not for me" · "yea".
//
//  REM: NOT A GATE. The app is open the moment they submit or tap Not Now. His idea for later: each
//  head coach runs their own board and may switch on approval ("like they wanted to start their own
//  BBS … wildcat or renegade"). Not built.
//  REM: The answers and the email go only to coaches: sealed to every coach's key (ContactSeal), in a
//  CrewApplication record (name = application.<iCloud ID>). The profile part is the same
//  MyProfileSection as Settings, so the crew sees only what the member shares there.
//  REM: Apple's email arrives only on the very first sign-in, and may be a Hide My Email relay;
//  the member sees it filled in and can change it before sending. Earlier rule "never request the
//  email" (2026-10-22) is superseded for this coach-only copy by his 2026-10-24 asks.
//

import CloudKit
import SwiftUI

extension CrewSettings {
    /// The email Apple gave at the first sign-in, if any.
    static let appleEmail = "appleEmail"
    /// The application screen has been shown and answered (sent or Not Now). It never shows again.
    static let applicationDone = "applicationDone"
    /// Answers waiting to reach the coaches (no coach key loaded yet, or offline). Empty once sent.
    static let applicationWaiting = "applicationWaiting"
    /// Coach's phone: the welcome letter, and the members it was sent to.
    static let welcomeLetter = "welcomeLetter"
    static let welcomed = "welcomedMemberIDs"
}

/// What only the coaches read.
struct CrewApplication: Codable {
    var email = ""
    var why = ""
    var goals = ""
    var suggestions = ""
}

/// Shown once after sign-in: a few words to the head coach, and the profile the crew will see.
struct ApplicationView: View {
    @AppStorage(CrewSettings.appleEmail) private var appleEmail = ""
    @AppStorage(CrewSettings.applicationDone) private var done = false
    @AppStorage(CrewSettings.applicationWaiting) private var waiting = ""
    @AppStorage(CrewSettings.name) private var name = ""
    @State private var answers = CrewApplication()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Tell the head coach a little about yourself. Only coaches see this section.")
                        .font(AppFont.body)
                    field("Your email", text: $answers.email, keyboard: .emailAddress)
                    field("Why are you joining Rep Crew?", text: $answers.why)
                    field("What are your fitness goals?", text: $answers.goals)
                    field("Any ideas to make getting started easier?", text: $answers.suggestions)
                } header: {
                    Text("For the head coach").font(AppFont.bodyBold).textCase(nil)
                }

                MyProfileSection()

                Section {
                    Button { finish(send: true) } label: {
                        Text("Send to the Head Coach").font(AppFont.bodyBold).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button { finish(send: false) } label: {
                        Text("Not Now").font(AppFont.body).frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Welcome to the Crew")
            .onAppear { if answers.email.isEmpty { answers.email = appleEmail } }
        }
    }

    private func field(_ title: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(AppFont.bodyBold)
            TextField(title, text: text, axis: .vertical)
                .font(AppFont.body)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .sentences)
                .autocorrectionDisabled(keyboard == .emailAddress)
                .lineLimit(1...6)
        }
        .padding(.vertical, 4)
    }

    /// Not Now still tells the coaches someone new arrived, just without answers.
    private func finish(send: Bool) {
        let trimmed = CrewApplication(email: send ? answers.email.trimmingCharacters(in: .whitespacesAndNewlines) : "",
                                      why: send ? answers.why.trimmingCharacters(in: .whitespacesAndNewlines) : "",
                                      goals: send ? answers.goals.trimmingCharacters(in: .whitespacesAndNewlines) : "",
                                      suggestions: send ? answers.suggestions.trimmingCharacters(in: .whitespacesAndNewlines) : "")
        waiting = String(data: (try? JSONEncoder().encode(trimmed)) ?? Data(), encoding: .utf8) ?? ""
        done = true
        Task { await CrewCloud.shared.sendWaitingApplication() }
        Task { await MyProfile.saveIfChanged() }
    }
}

// MARK: - iCloud

/// One application as a coach reads it.
struct ApplicationEntry: Identifiable {
    var id: String          // the member's iCloud ID
    var name: String
    var sent: Date
    var answers: CrewApplication?
}

extension CrewCloud {
    /// Sends answers saved on this phone. Retried on every sync until a coach's key is loaded and the save works.
    func sendWaitingApplication() async {
        let defaults = UserDefaults.standard
        guard let text = defaults.string(forKey: CrewSettings.applicationWaiting), !text.isEmpty,
              let answers = try? JSONDecoder().decode(CrewApplication.self, from: Data(text.utf8)) else { return }
        await connect()
        // Sealed to coaches only. With no coach key yet nobody could read it, so wait.
        guard let myID, !coachKeys.isEmpty, let sealed = ContactSeal.seal(answers, to: coachKeys) else { return }
        let name = defaults.string(forKey: CrewSettings.name)?.trimmingCharacters(in: .whitespaces) ?? ""
        let record = CKRecord(recordType: "CrewApplication", recordID: CKRecord.ID(recordName: "application.\(myID)"))
        record["memberID"] = myID
        record["name"] = name.isEmpty ? "A crew member" : name
        record["sealed"] = sealed
        do {
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            defaults.set("", forKey: CrewSettings.applicationWaiting)
        } catch {
            status = "Couldn't send your application yet: \(error.localizedDescription)"
        }
    }

    /// Coach's phone: every application, newest first, opened with this phone's key.
    func applications() async -> [ApplicationEntry] {
        await connect()
        guard let myID else { return [] }
        let key = ContactKey.mine(create: false)
        let query = CKQuery(recordType: "CrewApplication", predicate: NSPredicate(value: true))
        guard let (results, _) = try? await db.records(matching: query, resultsLimit: 400) else { return [] }
        return results.compactMap { try? $0.1.get() }.map { record in
            var opened: CrewApplication?
            if let key, let sealed = record["sealed"] as? Data {
                opened = ContactSeal.open(CrewApplication.self, sealed, for: myID, key: key)
            }
            return ApplicationEntry(id: record["memberID"] as? String ?? record.recordID.recordName,
                                    name: record["name"] as? String ?? "A crew member",
                                    sent: record.modificationDate ?? record.creationDate ?? .distantPast,
                                    answers: opened)
        }
        .sorted { $0.sent > $1.sent }
    }

    /// Coach's phone: a notification for each new crew member. Settings → Notifications → New crew members.
    func subscribeToNewMembers() async {
        await connect()
        guard GodMode.isOn, NotificationSettings.isOn(NotificationSettings.newMembers) else {
            _ = try? await db.modifySubscriptions(saving: [], deleting: [NotificationSettings.newMembers])
            return
        }
        let subscription = CKQuerySubscription(recordType: "CrewApplication", predicate: NSPredicate(value: true),
                                               subscriptionID: NotificationSettings.newMembers, options: [.firesOnRecordCreation])
        let info = CKSubscription.NotificationInfo()
        info.titleLocalizationKey = "%1$@ joined the crew"
        info.titleLocalizationArgs = ["name"]
        info.alertBody = "Tap to read their application."
        info.soundName = "default"
        subscription.notificationInfo = info
        do {
            _ = try await db.modifySubscriptions(saving: [subscription], deleting: [])
        } catch let error as CKError where error.code == .unknownItem || error.code == .partialFailure {
            // Before the first application there is no CrewApplication type to subscribe to; a later launch picks it up.
        } catch {
            status = "Couldn't turn on new member notifications: \(error.localizedDescription)"
        }
    }
}

// MARK: - Coach Mode → New Crew Members

struct ApplicationsView: View {
    @AppStorage(CrewSettings.welcomed) private var welcomed = ""
    @State private var entries: [ApplicationEntry] = []
    @State private var loaded = false

    var body: some View {
        List {
            Section {
                NavigationLink {
                    WelcomeLetterView()
                } label: {
                    Label("Welcome Letter", systemImage: "envelope.open.fill").font(AppFont.bodyBold)
                }
            }
            Section {
                if loaded && entries.isEmpty {
                    Text("No applications yet.").font(AppFont.body).foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    NavigationLink {
                        ApplicationDetailView(entry: entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.name).font(AppFont.bodyBold)
                            Text(entry.sent.formatted(date: .abbreviated, time: .shortened)
                                 + (welcomed.split(separator: "\n").contains(Substring(entry.id)) ? " · Welcomed" : ""))
                                .font(AppFont.body).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Applications").font(AppFont.bodyBold).textCase(nil)
            }
        }
        .navigationTitle("New Crew Members")
        .refreshable { entries = await CrewCloud.shared.applications() }
        .task {
            entries = await CrewCloud.shared.applications()
            loaded = true
        }
    }
}

private struct ApplicationDetailView: View {
    let entry: ApplicationEntry
    @AppStorage(CrewSettings.welcomeLetter) private var letter = WelcomeLetterView.starter
    @AppStorage(CrewSettings.welcomed) private var welcomed = ""
    @Environment(\.openURL) private var openURL

    private var email: String { entry.answers?.email ?? "" }

    var body: some View {
        List {
            if let answers = entry.answers {
                answer("Email", answers.email)
                answer("Why they're joining", answers.why)
                answer("Fitness goals", answers.goals)
                answer("Ideas for getting started", answers.suggestions)
            } else {
                Text("This application wasn't sealed to your phone's key, so it can't be opened here.")
                    .font(AppFont.body)
            }
            Section {
                Button(action: sendWelcome) {
                    Label("Send Welcome Letter", systemImage: "paperplane.fill").font(AppFont.bodyBold)
                }
                .disabled(email.isEmpty)
                if email.isEmpty {
                    Text("No email was given, so there's nowhere to send it.").font(AppFont.body).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(entry.name)
    }

    private func answer(_ title: String, _ text: String) -> some View {
        Section {
            Text(text.isEmpty ? "Left blank" : text)
                .font(AppFont.body)
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
        } header: {
            Text(title).font(AppFont.bodyBold).textCase(nil)
        }
    }

    /// Opens Mail with the letter, from his own address. The app can't send mail by itself.
    private func sendWelcome() {
        var parts = URLComponents()
        parts.scheme = "mailto"
        parts.path = email
        parts.queryItems = [URLQueryItem(name: "subject", value: "Welcome to Rep Crew"),
                            URLQueryItem(name: "body", value: letter)]
        guard let url = parts.url else { return }
        openURL(url)
        if !welcomed.split(separator: "\n").contains(Substring(entry.id)) {
            welcomed = (welcomed.split(separator: "\n").map(String.init) + [entry.id]).joined(separator: "\n")
        }
    }
}

/// The form letter, written once and sent to each new member.
struct WelcomeLetterView: View {
    @AppStorage(CrewSettings.welcomeLetter) private var letter = WelcomeLetterView.starter

    static let starter = """
    Welcome to the crew!

    Thanks for joining Rep Crew. A few things worth trying:

    • Start a challenge with the + button, or find one under Other challenges and tap Ask to Join.
    • Log reps with the quick buttons, or time a set with Start Set, which saves the workout to Health.
    • The leaderboard starts fresh every morning, so every day is a new chance.
    • Fill in your profile in Settings so your crew can reach you.

    Reply to this email any time with questions or ideas.

    Your head coach
    """

    var body: some View {
        Form {
            Section {
                TextEditor(text: $letter)
                    .font(AppFont.body)
                    .frame(minHeight: 360)
            } footer: {
                Text("Sent from your own Mail each time you tap Send Welcome Letter.").font(AppFont.body)
            }
            Section {
                Button("Start Over with the Starter Letter") { letter = Self.starter }
                    .font(AppFont.body)
            }
        }
        .navigationTitle("Welcome Letter")
    }
}
