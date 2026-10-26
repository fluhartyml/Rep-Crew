//
//  UserAccountView.swift
//  Rep Crew
//
//  One crew member's account page: photo, access (level, title, flags), contact, application, welcome
//  letter. His word, 2026-10-25: "the user account should be a swift page and call it up where needed
//  like new crew members or user list or coaches".
//
//  REM: every place that shows a person's account calls this page, so a change here shows everywhere.
//  Coaches-only fields open because this phone's key is in the seal (ContactSeal). Editing access stays
//  head-coach only (MemberAccessSection).
//

import PhotosUI
import SwiftUI

struct CrewUser: Identifiable {
    let id: String
    var profile: CrewProfile?
    var access: MemberAccess
    var application: ApplicationEntry?

    var name: String {
        let saved = profile?.name.trimmingCharacters(in: .whitespaces) ?? ""
        if !saved.isEmpty { return saved }
        return application?.name ?? "A crew member"
    }
}

/// Pass a user already loaded (User List), or just an ID and it loads itself (New Crew Members, Coaches).
struct UserAccountView: View {
    let memberID: String
    private let given: CrewUser?
    private let application: ApplicationEntry?
    @State private var loaded: CrewUser?

    init(user: CrewUser) {
        memberID = user.id
        given = user
        application = user.application
    }

    init(memberID: String, application: ApplicationEntry? = nil) {
        self.memberID = memberID
        given = nil
        self.application = application
    }

    var body: some View {
        Group {
            if let user = given ?? loaded { card(user) } else { ProgressView() }
        }
        .task {
            guard given == nil, loaded == nil else { return }
            let cloud = CrewCloud.shared
            var profile: CrewProfile?
            if case .found(let found) = await cloud.fetchProfile(memberID) { profile = found }
            var entry = application
            if entry == nil, GodMode.isOn { entry = await cloud.applications().first { $0.id == memberID } }
            loaded = CrewUser(id: memberID, profile: profile, access: await cloud.memberAccess(memberID), application: entry)
        }
    }

    private func card(_ user: CrewUser) -> some View {
        List {
            Section {
                HStack {
                    Spacer()
                    ProfilePhoto(image: user.profile?.photo, size: 120, seed: user.id)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
            if GodMode.isOwner { HeadCoachPhotoSection(memberID: user.id, hasOwnPhoto: user.profile?.photo != nil) }
            MemberAccessSection(memberID: user.id, name: user.name)
            Section {
                field("Phone", user.profile?.phone, privately: user.profile?.privateFields.contains("phone") ?? false)
                field("Email", user.profile?.email, privately: user.profile?.privateFields.contains("email") ?? false)
                field("FaceTime", user.profile?.facetime, privately: user.profile?.privateFields.contains("facetime") ?? false)
            } header: {
                Text("Contact").font(AppFont.bodyBold).textCase(nil)
            }
            Section {
                if let answers = user.application?.answers {
                    field("Email given to the coach", answers.email, privately: true)
                    field("Why they joined", answers.why, privately: true)
                    field("Fitness goals", answers.goals, privately: true)
                    field("Ideas for getting started", answers.suggestions, privately: true)
                } else {
                    Text(user.application == nil ? "No application sent." : "Their application wasn't sealed to your phone's key.")
                        .font(AppFont.body).foregroundStyle(.secondary)
                }
            } header: {
                Text("Application").font(AppFont.bodyBold).textCase(nil)
            }
            if let application = user.application, GodMode.isOn { WelcomeLetterSection(entry: application) }
            if user.application != nil, GodMode.isOn { ApproveSection(memberID: user.id) }
            Section {
                Text(user.id).font(AppFont.body).foregroundStyle(.secondary).textSelection(.enabled)
            } header: {
                Text("iCloud ID").font(AppFont.bodyBold).textCase(nil)
            }
        }
        .navigationTitle(user.name)
    }

    private func field(_ title: String, _ value: String?, privately: Bool) -> some View {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return VStack(alignment: .leading, spacing: 4) {
            Text(title + (privately && !text.isEmpty ? " · Coaches only" : "")).font(AppFont.bodyBold)
            Text(text.isEmpty ? "Not given" : text)
                .font(AppFont.body)
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

/// Head coach only: set this person's photo from Crew Media, the camera roll or the camera, or take
/// yours off so their own shows again (CrewCloud.setAvatarOverride, Profile.swift).
private struct HeadCoachPhotoSection: View {
    let memberID: String
    let hasOwnPhoto: Bool
    private var cloud = CrewCloud.shared
    @State private var picked: PhotosPickerItem?
    @State private var working = false
    @State private var note: String?

    init(memberID: String, hasOwnPhoto: Bool) {
        self.memberID = memberID
        self.hasOwnPhoto = hasOwnPhoto
    }

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
    private var isSet: Bool { cloud.avatarOverrides[memberID] != nil }

    var body: some View {
        Section {
            // One button per row (two buttons in one List row both fire).
            ChooseFromMediaButton { _, image in Task { await set(image) } }
                .disabled(working)
            PhotosPicker(selection: $picked, matching: .images) {
                Label("Choose Photo", systemImage: "photo.on.rectangle").font(AppFont.bodyBold)
            }
            .disabled(working)
            if cameraAvailable {
                Button { CameraPresenter.shared.present { image in Task { await set(image) } } } label: {
                    Label("Take Photo", systemImage: "camera.fill").font(AppFont.bodyBold)
                }
                .disabled(working)
            }
            if isSet {
                Button(role: .destructive) { Task { await set(nil) } } label: {
                    // The arrow red like the words (his word, 2026-10-26: "yes add the red arrow").
                    Label {
                        Text(hasOwnPhoto ? "Use Their Own Photo" : "Remove Photo")
                    } icon: {
                        Image(systemName: "arrow.uturn.backward").foregroundStyle(.red)
                    }
                    .font(AppFont.bodyBold)
                }
                .disabled(working)
            }
            if working {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Saving…").font(AppFont.body)
                }
            }
            if let note { Text(note).font(AppFont.body) }
        } header: {
            Text("Their Photo").font(AppFont.bodyBold).textCase(nil)
        } footer: {
            Text(isSet ? "You set this photo. Everyone sees it in place of theirs, them included."
                       : hasOwnPhoto ? "Pick a photo to show in place of theirs, everywhere in the app."
                                     : "They have no photo. Pick one to give them.")
                .font(AppFont.body)
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await set(image)
                }
                picked = nil
            }
        }
    }

    private func set(_ image: UIImage?) async {
        working = true
        note = nil
        if let image, await ContentFilter.isSensitive(image) {
            note = "This photo can't be used."
        } else if !(await cloud.setAvatarOverride(image, for: memberID)) {
            note = "That didn't go through. Check iCloud in Settings and try again."
        }
        working = false
    }
}
