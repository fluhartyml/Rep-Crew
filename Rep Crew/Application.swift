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
    /// The member sent the application with an email in it: level 11 (Access.swift).
    static let applicationEmailGiven = "applicationEmailGiven"
    /// Answers waiting to reach the coaches (no coach key loaded yet, or offline). Empty once sent.
    static let applicationWaiting = "applicationWaiting"
    /// Your answers as you last sent them, kept on this phone, so the application opens filled in.
    /// Only coaches can open the copy in iCloud (it's sealed to them).
    static let applicationLast = "applicationLast"
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
    /// Closes it when it was opened from Home's welcome card (HomeTiers.swift); after sign-in it does nothing.
    @Environment(\.dismiss) private var dismiss
    /// Opened from Home: Cancel closes it without sending anything. After sign-in there's no Cancel.
    /// REM: his word, 2026-10-25: "yes add a cancel button it should show my application info as it was the first
    /// time i filled it out". Send and Not Now both save, so Home needed a way out that saves nothing.
    var canCancel = false
    @AppStorage(CrewSettings.appleEmail) private var appleEmail = ""
    @AppStorage(CrewSettings.applicationDone) private var done = false
    @AppStorage(CrewSettings.applicationWaiting) private var waiting = ""
    @AppStorage(CrewSettings.name) private var name = ""
    @AppStorage(CrewSettings.crewName) private var crewName = ""
    @State private var answers = CrewApplication()
    /// Send or Not Now tapped with no email: asks once more before going on.
    @State private var askingEmail: Bool?
    @FocusState private var focusedField: String?

    var body: some View {
        NavigationStack {
            Form {
                Text("Welcome to \(CrewCloud.displayName(crewName))")
                    .font(AppFont.title)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 24, leading: 4, bottom: 0, trailing: 4))
                Section {
                    Text("Tell the head coach a little about yourself. Only coaches see this section.")
                        .font(AppFont.body)
                    field("Your email", text: $answers.email, keyboard: .emailAddress)
                    // REM: his word, 2026-10-25: "as long as it pesters the user to enter an email address, can it
                    // also offer a 'hide my email' by apple?" Hide My Email can't be made from inside an app; the
                    // footer says where. The email field is marked as one, so the keyboard can suggest an address.
                    if trimmedEmail.isEmpty {
                        Label("Add your email to get verified. Without it you can look around, but you can't join or start challenges.",
                              systemImage: "exclamationmark.circle.fill")
                            .font(AppFont.bodyBold).foregroundStyle(.orange)
                    }
                    Text("Want to keep your address private? With iCloud+, make a Hide My Email address in Settings → your name → iCloud → Hide My Email, then paste it here.")
                        .font(AppFont.body).foregroundStyle(.secondary)
                    field("Why are you joining Rep Crew?", text: $answers.why)
                    field("What are your fitness goals?", text: $answers.goals)
                    field("Any ideas to make getting started easier?", text: $answers.suggestions)
                } header: {
                    Text("For the head coach").font(AppFont.bodyBold).textCase(nil)
                }

                MyProfileSection()

                Section {
                    Button { tapped(send: true) } label: {
                        Text("Send to the Head Coach").font(AppFont.bodyBold).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button { tapped(send: false) } label: {
                        Text("Not Now").font(AppFont.body).frame(maxWidth: .infinity)
                    }
                    if canCancel {
                        Button(role: .cancel) { dismiss() } label: {
                            Text("Cancel").font(AppFont.body).frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            // REM: his word 2026-10-24, "welcome to the... should take two lines if needed". A navigation
            // title can't wrap, so the title is the form's first line and wraps like any text.
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("Go on without an email?", isPresented: Binding(get: { askingEmail != nil }, set: { if !$0 { askingEmail = nil } }),
                                titleVisibility: .visible) {
                Button("Add My Email") { askingEmail = nil; focusedField = "Your email" }
                Button("Go On Without Email", role: .destructive) {
                    if let send = askingEmail { finish(send: send) }
                    askingEmail = nil
                }
            } message: {
                Text("Without an email you stay a new user: you can look around but not join or start challenges, and the head coach can only welcome you in your Inbox.")
            }
            .onAppear {
                // What you sent last time, then Apple's email if there's still none.
                if let text = UserDefaults.standard.string(forKey: CrewSettings.applicationLast),
                   let last = try? JSONDecoder().decode(CrewApplication.self, from: Data(text.utf8)) { answers = last }
                if answers.email.isEmpty { answers.email = appleEmail }
            }
            // A coach can open their own sealed copy in iCloud, for an application sent before this phone kept one.
            .task {
                guard GodMode.isOn || GodMode.isRealOwner, answers.why.isEmpty && answers.goals.isEmpty && answers.suggestions.isEmpty,
                      let myID = CrewCloud.shared.myID,
                      let mine = await CrewCloud.shared.applications().first(where: { $0.id == myID })?.answers else { return }
                answers = mine
                if answers.email.isEmpty { answers.email = appleEmail }
            }
            // REM: the profile came back from iCloud only when Settings opened, so on his reinstalled 16e
            // this screen showed "No photo" while his 11 showed it (build 72). Fetch it here first.
            .task { await MyProfile.restoreIfNeeded() }
        }
    }

    private func field(_ title: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(AppFont.bodyBold)
            // The question is the label above, so the box doesn't repeat it (seen doubled on his 11, build 72).
            TextField(keyboard == .emailAddress ? "name@example.com" : "Type here", text: text, axis: .vertical)
                .font(AppFont.body)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .sentences)
                .autocorrectionDisabled(keyboard == .emailAddress)
                .lineLimit(1...6)
                .textContentType(keyboard == .emailAddress ? .emailAddress : nil)
                .focused($focusedField, equals: title)
        }
        .padding(.vertical, 4)
    }

    private var trimmedEmail: String {
        answers.email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Asks once more when there's no email to send (Send uses the typed one, Not Now Apple's).
    private func tapped(send: Bool) {
        let email = send ? trimmedEmail : appleEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if email.isEmpty { askingEmail = send } else { finish(send: send) }
    }

    /// Not Now still tells the coaches someone new arrived, without answers but with Apple's email.
    /// REM: his word 2026-10-25, after James's blank application: "this is why i want an email from sign in
    /// with apple". Sign-in already says the email goes only to the head coach, so Not Now keeps it.
    private func finish(send: Bool) {
        let email = (send ? answers.email : appleEmail).trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = CrewApplication(email: email,
                                      why: send ? answers.why.trimmingCharacters(in: .whitespacesAndNewlines) : "",
                                      goals: send ? answers.goals.trimmingCharacters(in: .whitespacesAndNewlines) : "",
                                      suggestions: send ? answers.suggestions.trimmingCharacters(in: .whitespacesAndNewlines) : "")
        waiting = String(data: (try? JSONEncoder().encode(trimmed)) ?? Data(), encoding: .utf8) ?? ""
        if send { UserDefaults.standard.set(waiting, forKey: CrewSettings.applicationLast) }
        done = true
        UserDefaults.standard.set(false, forKey: CrewSettings.startingOver)
        if !trimmed.email.isEmpty { UserDefaults.standard.set(true, forKey: CrewSettings.applicationEmailGiven) }
        Task { await CrewCloud.shared.sendWaitingApplication(); await CrewCloud.shared.refreshMyAccess() }
        Task { await MyProfile.saveIfChanged() }
        dismiss()
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

    /// Everyone's user number, BBS style: the head coach is 1, then everyone in the order their application first
    /// reached iCloud (creationDate, which a later save doesn't change). Empty when iCloud didn't answer.
    /// REM: his word, 2026-10-25, seeing "Crew member 2" on his own card: "i should have been number one".
    /// The old number came from the invite chain (inviter + 1, kept per phone), so it wasn't anyone's real place.
    /// "01", "02" … "99", then "100". His word, 2026-10-25: "make my number 01".
    static func numberText(_ number: Int) -> String { String(format: "%02d", number) }

    func userNumbers() async -> [String: Int] {
        await connect()
        let query = CKQuery(recordType: "CrewApplication", predicate: NSPredicate(value: true))
        guard let (results, _) = try? await db.records(matching: query, resultsLimit: 400) else { return [:] }
        let joined = results.compactMap { try? $0.1.get() }
            .compactMap { record -> (id: String, at: Date)? in
                guard let id = record["memberID"] as? String, writer(of: record) == id else { return nil }
                return (id, record.creationDate ?? .distantFuture)
            }
            .filter { !GodMode.ids.contains($0.id) }
            .sorted { $0.at < $1.at }
        var numbers: [String: Int] = [:]
        for id in GodMode.ids { numbers[id] = 1 }
        for (index, member) in joined.enumerated() { numbers[member.id] = index + 2 }
        return numbers
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
        info.shouldSendContentAvailable = true   // wakes the app to raise the icon badge (InboxBadge)
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
                    let isWelcomed = welcomed.split(separator: "\n").contains(Substring(entry.id))
                    NavigationLink {
                        UserAccountView(memberID: entry.id, application: entry)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            // REM: his word, 2026-10-25: "it should have a blue dot or something till i have processed or
                            // sent a welcome letter". Blue until the welcome letter goes, like Inbox.
                            Circle().fill(.blue).frame(width: 10, height: 10).padding(.top, 8)
                                .opacity(isWelcomed ? 0 : 1)
                                .accessibilityLabel(isWelcomed ? "" : "Not welcomed yet")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.name).font(AppFont.bodyBold)
                                Text(entry.sent.formatted(date: .abbreviated, time: .shortened) + (isWelcomed ? " · Welcomed" : ""))
                                    .font(AppFont.body).foregroundStyle(.secondary)
                                if entry.answers.map({ $0.email.isEmpty }) ?? false {
                                    Text("No email given").font(AppFont.body).foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                    .contextMenu { AccessLevelMenu(memberID: entry.id, name: entry.name) }
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

/// Send Welcome Letter: by email when one was given, else to their Rep Crew Inbox.
struct WelcomeLetterSection: View {
    let entry: ApplicationEntry
    @AppStorage(CrewSettings.welcomeLetter) private var letter = WelcomeLetterView.starter
    @AppStorage(CrewSettings.welcomed) private var welcomed = ""
    @AppStorage(CrewSettings.name) private var myName = ""
    @Environment(\.openURL) private var openURL
    @State private var sending = false
    @State private var note: String?

    private var email: String { entry.answers?.email.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }

    var body: some View {
        // REM: his word 2026-10-25: "if no email address is given i want the fallback to be within the apps inbox".
        Section {
            if email.isEmpty {
                Button { Task { await sendToInbox() } } label: {
                    Label("Send Welcome Letter to Inbox", systemImage: "tray.and.arrow.down.fill").font(AppFont.bodyBold)
                }
                .disabled(sending)
            } else {
                Button(action: sendEmail) {
                    Label("Send Welcome Letter", systemImage: "paperplane.fill").font(AppFont.bodyBold)
                }
            }
            if let note { Text(note).font(AppFont.body) }
        } header: {
            Text("Welcome Letter").font(AppFont.bodyBold).textCase(nil)
        } footer: {
            Text(email.isEmpty ? "No email was given, so the letter goes to their Rep Crew Inbox."
                               : (isWelcomed ? "Already welcomed." : "Opens Mail with your welcome letter."))
                .font(AppFont.body)
        }
    }

    private var isWelcomed: Bool { welcomed.split(separator: "\n").contains(Substring(entry.id)) }

    private func sendToInbox() async {
        sending = true
        let me = myName.trimmingCharacters(in: .whitespaces)
        if await CrewCloud.shared.send(letter, crewID: CrewMessage.direct(to: entry.id), kind: .direct, to: entry.id,
                                       senderName: me.isEmpty ? "Head Coach" : me) {
            note = "Sent to \(entry.name)'s Inbox."
            markWelcomed()
        } else {
            note = "That didn't go through. Check Settings → iCloud and try again."
        }
        sending = false
    }

    /// Opens Mail with the letter, from his own address. The app can't send mail by itself.
    private func sendEmail() {
        var parts = URLComponents()
        parts.scheme = "mailto"
        parts.path = email
        parts.queryItems = [URLQueryItem(name: "subject", value: "Welcome to Rep Crew"),
                            URLQueryItem(name: "body", value: letter)]
        guard let url = parts.url else { return }
        openURL(url)
        markWelcomed()
    }

    private func markWelcomed() {
        if !isWelcomed {
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
