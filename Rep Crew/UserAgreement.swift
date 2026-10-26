//
//  UserAgreement.swift
//  Rep Crew
//
//  The user agreement. His word, 2026-10-25: "we are also going to need to have a user agreement they
//  have to acknowledge after reading in order to use the app and it should be for past and all future
//  users to have to agree on".
//
//  REM: RootView shows this before anything else, sign-in included, until this phone has agreed to the
//  current `version`. Everyone already using the app sees it on their next launch. Change the text →
//  raise `version`, and everyone agrees again.
//  REM: version 2, his word 2026-10-26: "your crew should find and replace with your crewmates" — the crew is
//  his; to a member the others are crewmates.
//  REM: version 3, his words 2026-10-26: "if you do not agree please uninstall and discontinue use of [Daily] Rep
//  Crew" · "use daily rep crew accountability thats its folmal name it may be shortened elsewhere".
//  REM: "after reading": I Agree stays off until you've scrolled to the end.
//  REM: Apple guideline 1.2 (user-generated content) asks for terms people agree to, with no tolerance
//  for objectionable content or abusive users. The rest restates what the app already does (filter,
//  Report, Block, removal and ban, Health stays on the phone). Wording drafted by Claude for him to
//  review; it is not a lawyer's text.
//

import SwiftUI

extension CrewSettings {
    /// The agreement version this phone agreed to; 0 for none.
    static let agreementVersion = "agreementVersion"
}

enum UserAgreement {
    static let version = 3

    static var isAccepted: Bool { UserDefaults.standard.integer(forKey: CrewSettings.agreementVersion) >= version }

    static let sections: [(heading: String, body: String)] = [
        ("Using Rep Crew",
         "Rep Crew helps you and your crewmates keep each other accountable for exercise. By tapping I Agree, you agree to everything below. If you do not agree, please uninstall and discontinue use of Daily Rep Crew Accountability."),
        ("Respect your crewmates",
         "No nudity or sexual content, no harassment, bullying, threats, hate or violence, and no spam. There is zero tolerance for objectionable content or abusive behavior."),
        ("What you post",
         "Your crewmates see the photos, messages, events and profile you share. Post only what you have the right to share, and only photos of people who said yes. You can delete what you posted."),
        ("Reports, removal and bans",
         "You can report anything and block anyone. The developer reviews every report. Coaches and challenge leaders can remove posts, and anyone who breaks these rules can be removed or banned from the crew."),
        ("Your health",
         "Rep Crew is a way to keep track of your own exercise. It is not medical advice. Check with a doctor before starting a new exercise routine, and stop if something hurts."),
        ("Your privacy",
         "What Rep Crew reads from Health stays on your iPhone unless you choose to share it. Your contact info is shared only the way you set it in Settings → Your profile."),
        ("Apple's terms",
         "Apple's standard license agreement for apps from the App Store also applies."),
        ("Changes",
         "When this agreement changes, you'll be asked to read and agree to it again."),
    ]
}

/// Full screen, before the app opens.
struct UserAgreementView: View {
    @AppStorage(CrewSettings.agreementVersion) private var agreed = 0
    @State private var readToEnd = false

    var body: some View {
        NavigationStack {
            ScrollView {
                // Lazy, so the marker at the end appears only when it's scrolled onto the screen.
                LazyVStack(alignment: .leading, spacing: 20) {
                    Text("Please read this before using Rep Crew.").font(AppFont.body)
                    ForEach(UserAgreement.sections, id: \.heading) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.heading).font(AppFont.heading)
                            Text(section.body).font(AppFont.body).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("Version \(UserAgreement.version)").font(AppFont.body).foregroundStyle(.secondary)
                    Color.clear.frame(height: 1).onAppear { readToEnd = true }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button { agreed = UserAgreement.version } label: {
                        Text("I Agree").font(AppFont.bodyBold).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!readToEnd)
                    if !readToEnd {
                        Text("Scroll to the end to agree.").font(AppFont.body).foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("User Agreement")
        }
    }
}

/// The text, for the agreement screen and About.
struct AgreementText: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(UserAgreement.sections, id: \.heading) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.heading).font(AppFont.heading)
                    Text(section.body).font(AppFont.body).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Version \(UserAgreement.version)").font(AppFont.body).foregroundStyle(.secondary)
        }
    }
}

/// About → User Agreement, to read it again.
struct AgreementReadView: View {
    var body: some View {
        ScrollView {
            AgreementText().padding()
        }
        .navigationTitle("User Agreement")
        .navigationBarTitleDisplayMode(.inline)
    }
}
