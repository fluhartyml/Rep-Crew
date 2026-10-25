//
//  SignIn.swift
//  Rep Crew
//
//  Every crew member signs in with Apple before anything else. Michael, 2026-10-22: "have a
//  new crewmember register via apple" · "let apple handle the new user validation so when we
//  kick or ban it has weight" · "were not the apple id police we are making our honest best
//  effort to protect our crew members."
//
//  The name and email are requested. The email goes only to coaches, in the new member's
//  application (Application.swift, his asks 2026-10-24; was name only).
//   The Apple user ID is kept on this phone; on
//  every launch the app asks Apple whether that sign-in still stands, and if it was revoked
//  the sign-in screen comes back.
//
//  REM: the account is made at sign-in (his "can you do everything we discussed please?", 2026-10-24).
//  Right after signing in, the app looks for your Profile in iCloud. Found: your name and profile come
//  back and nothing is asked again. None: your profile is made then, with the name Apple gave. Apple
//  gives the name only on the very first sign-in ever, so with no profile and no name, it's asked.
//

import AuthenticationServices
import SwiftUI

extension CrewSettings {
    /// The Apple user ID from Sign in with Apple. Empty until signed in.
    static let appleUser = "appleUserID"
}

/// Sign in with Apple first, then the app. An invite link opened before signing in is held
/// and handed on once you're in.
struct RootView: View {
    @AppStorage(CrewSettings.appleUser) private var appleUser = ""
    @AppStorage(CrewSettings.name) private var name = ""
    @AppStorage(CrewSettings.applicationDone) private var applicationDone = false
    @AppStorage(CrewSettings.profileRestored) private var accountChecked = false
    /// The iCloud lookup was tried; if iCloud didn't answer, the name is asked as before.
    @State private var lookedUp = false
    @State private var openedURL: URL?
    /// Read so the screen changes the moment I Agree is tapped (UserAgreement.swift).
    @AppStorage(CrewSettings.agreementVersion) private var agreementVersion = 0

    var body: some View {
        Group {
            if agreementVersion < UserAgreement.version {
                UserAgreementView()
            } else if appleUser.isEmpty {
                SignInView()
            } else if !accountChecked && !lookedUp && !applicationDone {
                // Until iCloud answers, so a returning member isn't asked their name or the application again.
                ProgressView("Setting up your account…").font(AppFont.body)
            } else if name.trimmingCharacters(in: .whitespaces).isEmpty {
                // REM: shakedown bug 3 (2026-10-23), "it says anonymous". Apple gives the name only on the
                // very first sign-in, so a reinstall left it empty and the crew saw "A crew member".
                NameView()
            } else if !applicationDone {
                ApplicationView()
            } else {
                ContentView(openedURL: $openedURL)
            }
        }
        .onOpenURL { openedURL = $0 }
        .task(id: appleUser) {
            guard !appleUser.isEmpty else { return }
            if let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: appleUser),
               state == .revoked || state == .notFound {
                appleUser = ""
                return
            }
            await CrewCloud.shared.startOverIfRequested()
            await MyProfile.restoreIfNeeded()
            // A new member's profile is made now, once there's a name to put on it.
            if !name.trimmingCharacters(in: .whitespaces).isEmpty { await MyProfile.saveIfChanged() }
            lookedUp = true
        }
    }
}

struct SignInView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(CrewSettings.appleUser) private var appleUser = ""
    @AppStorage(CrewSettings.name) private var name = ""
    @State private var failed = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "figure.strengthtraining.functional")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Rep Crew").font(AppFont.title)
            Text("Sign in with Apple to join the crew. It keeps every crew member a real person. Rep Crew asks Apple for your name and email. Your email goes only to the head coach.")
                .font(AppFont.body)
                .multilineTextAlignment(.center)
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { failed = true; return }
                    // Apple gives the name only the first time; keep a name already typed in Settings.
                    if name.trimmingCharacters(in: .whitespaces).isEmpty, let given = credential.fullName?.givenName {
                        name = given
                    }
                    // Apple gives the email only the first time too; it's offered on the application.
                    if let email = credential.email { UserDefaults.standard.set(email, forKey: CrewSettings.appleEmail) }
                    appleUser = credential.user
                case .failure(let error):
                    failed = (error as? ASAuthorizationError)?.code != .canceled
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 56)
            if failed {
                Text("Sign in didn't finish. Check that you're signed in to your Apple Account in the iPhone Settings app, then try again.")
                    .font(AppFont.body)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(32)
    }
}

/// Asked once, when signing in left no name: your crew sees it on challenges and messages.
struct NameView: View {
    @AppStorage(CrewSettings.name) private var name = ""
    @State private var typed = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("What should your crew call you?").font(AppFont.title).multilineTextAlignment(.center)
            Text("Your crew sees this name on your challenges and messages. You can change it later in Settings.")
                .font(AppFont.body)
                .multilineTextAlignment(.center)
            TextField("Your name", text: $typed)
                .font(AppFont.heading)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .textContentType(.givenName)
                .submitLabel(.done)
                .focused($focused)
                .onSubmit(save)
            Button(action: save) {
                Text("Continue").font(AppFont.bodyBold).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
            Spacer()
        }
        .padding(32)
        .onAppear { focused = true }
    }

    private func save() {
        let trimmed = typed.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        name = trimmed
    }
}
