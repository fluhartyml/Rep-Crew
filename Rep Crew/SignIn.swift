//
//  SignIn.swift
//  Rep Crew
//
//  Every crew member signs in with Apple before anything else. Michael, 2026-10-22: "have a
//  new crewmember register via apple" · "let apple handle the new user validation so when we
//  kick or ban it has weight" · "were not the apple id police we are making our honest best
//  effort to protect our crew members."
//
//  Only the name is requested, never the email. The Apple user ID is kept on this phone; on
//  every launch the app asks Apple whether that sign-in still stands, and if it was revoked
//  the sign-in screen comes back.
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
    @State private var openedURL: URL?

    var body: some View {
        Group {
            if appleUser.isEmpty {
                SignInView()
            } else if name.trimmingCharacters(in: .whitespaces).isEmpty {
                // REM: shakedown bug 3 (2026-10-23), "it says anonymous". Apple gives the name only on the
                // very first sign-in, so a reinstall left it empty and the crew saw "A crew member".
                NameView()
            } else {
                ContentView(openedURL: $openedURL)
            }
        }
        .onOpenURL { openedURL = $0 }
        .task(id: appleUser) {
            guard !appleUser.isEmpty,
                  let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: appleUser) else { return }
            if state == .revoked || state == .notFound { appleUser = "" }
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
            Text("Sign in with Apple to join the crew. It keeps every crew member a real person. Rep Crew asks Apple only for your name.")
                .font(AppFont.body)
                .multilineTextAlignment(.center)
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { failed = true; return }
                    // Apple gives the name only the first time; keep a name already typed in Settings.
                    if name.trimmingCharacters(in: .whitespaces).isEmpty, let given = credential.fullName?.givenName {
                        name = given
                    }
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
