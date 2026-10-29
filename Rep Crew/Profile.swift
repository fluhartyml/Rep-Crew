//
//  Profile.swift
//  Rep Crew
//
//  Each crew member's profile page. His words, 2026-10-23: "the crew each need a profile page
//  and on the profile page would be the links to contact phone email facetime voice or facetime
//  video" · "they have to manually add their contact info that way they can omit or use alternate
//  contact info" · "i want their profile to have a contact photo of their choice".
//
//  One record type in the crew's iCloud space:
//    Profile  name = profile.<iCloud ID>; name, phone, email, facetime, photo (small JPEG),
//             photoID, updatedAt. Written only by its owner, and read only when CloudKit says
//             the owner created it.
//  REM: not named by the bare iCloud ID. Record names are unique across every type in a zone,
//  and the public database's Users record already holds that name — same reason CoachGrant is
//  coach.<ID>.
//
//  A profile photo gets the photo board's protections (his word, 2026-10-23: "yes give them the
//  photo board protections coach level remove"): the on-device filter, Report, Block, and removal
//  by a coach. A coach can't edit someone else's Profile, so removal is a PhotoRemoval named
//  removed.<photoID>, honored only when a coach or he wrote it. Each new photo gets a new photoID,
//  so a removal hides that one photo, and the next one goes through the filter again.
//

import CloudKit
import Contacts
import ContactsUI
import MessageUI
import PhotosUI
import SwiftUI

struct CrewProfile {
    let id: String
    var name = ""
    var phone = ""
    var email = ""
    var facetime = ""
    var photoID = ""
    /// A ContactMethod raw value, or "" for no preference (CrewDirectory.swift).
    var preferred = ""
    /// "phone", "email", "facetime": shown here only because this phone is a coach or the owner
    /// (ContactSeal.swift).
    var privateFields: Set<String> = []
    /// Nil when there's none, or it was removed, reported, or caught by the filter.
    var photo: UIImage?
}

extension CrewSettings {
    static let profilePhone = "profilePhone"
    static let profileEmail = "profileEmail"
    static let profileFaceTime = "profileFaceTime"
    /// A ContactMethod raw value; empty for no preference.
    static let profilePreferred = "profilePreferred"
    /// Coaches only (ContactSeal.swift).
    static let profilePhonePrivate = "profilePhonePrivate"
    static let profileEmailPrivate = "profileEmailPrivate"
    static let profileFaceTimePrivate = "profileFaceTimePrivate"
    /// Off: phone, email and FaceTime go to coaches only, and other members get no contact buttons.
    /// Unset counts as on, so profiles saved before the switch existed keep working as they did.
    static let profileAllowMemberContact = "profileAllowMemberContact"
    /// "profile.<your ID>.<UUID>" for the photo on this phone; empty for none.
    static let profilePhotoID = "profilePhotoID"
    /// What iCloud last got, so an unchanged profile isn't saved again.
    static let profileSaved = "profileSavedSignature"
    /// True once this phone has pulled your profile back from iCloud (a new phone, a reinstall).
    static let profileRestored = "profileRestored"
}

/// Your own profile, kept on this phone and copied to iCloud.
enum MyProfile {
    private static var defaults: UserDefaults { .standard }
    static let crewIDForRemovals = "profile"

    static var photoFile: URL {
        URL.applicationSupportDirectory.appending(path: "profile-photo.jpg")
    }

    static var photo: UIImage? { UIImage(contentsOfFile: photoFile.path(percentEncoded: false)) }

    private static func value(_ key: String) -> String {
        (defaults.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isPrivate(_ key: String) -> Bool { defaults.bool(forKey: key) }

    static var allowsMemberContact: Bool { defaults.object(forKey: CrewSettings.profileAllowMemberContact) as? Bool ?? true }

    @MainActor static var signature: String {
        ([CrewSettings.name, CrewSettings.profilePhone, CrewSettings.profileEmail,
          CrewSettings.profileFaceTime, CrewSettings.profilePhotoID, CrewSettings.profilePreferred].map(value)
         + [CrewSettings.profilePhonePrivate, CrewSettings.profileEmailPrivate, CrewSettings.profileFaceTimePrivate]
            .map { isPrivate($0) ? "1" : "0" }
         + [allowsMemberContact ? "1" : "0"]
         + [CrewCloud.shared.coachKeysSignature]).joined(separator: "\u{1F}")
    }

    /// Runs the photo through the same filter as the photo board, then keeps a small copy.
    /// False when the filter caught it or it couldn't be written.
    @MainActor static func setPhoto(_ image: UIImage) async -> Bool {
        if await ContentFilter.isSensitive(image) { return false }
        await CrewCloud.shared.connect()
        guard let myID = CrewCloud.shared.myID, let file = CrewCloud.jpegFile(image, longestSide: 600) else { return false }
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            try FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: photoFile)
            try FileManager.default.copyItem(at: file, to: photoFile)
        } catch {
            return false
        }
        defaults.set("profile.\(myID).\(UUID().uuidString)", forKey: CrewSettings.profilePhotoID)
        return true
    }

    static func removePhoto() {
        try? FileManager.default.removeItem(at: photoFile)
        defaults.set("", forKey: CrewSettings.profilePhotoID)
    }

    /// Saves to iCloud when something changed since the last save.
    @MainActor static func saveIfChanged() async {
        guard defaults.bool(forKey: CrewSettings.profileRestored) else { return }
        await CrewCloud.shared.connect()
        let now = signature
        guard now != defaults.string(forKey: CrewSettings.profileSaved) else { return }
        var profile = CrewProfile(id: "")
        profile.name = value(CrewSettings.name)
        profile.photoID = value(CrewSettings.profilePhotoID)
        profile.preferred = value(CrewSettings.profilePreferred)
        // Coaches only: the plain field goes up blank and the value goes into the seal.
        // REM: his word, 2026-10-25: "what if they dont want other members to contact them. add a toggle
        // 'alow other crew members to contact you'". Off seals all three, so coaches can still reach them
        // and builds from before the switch show other members nothing either.
        let allow = allowsMemberContact
        var hidden = PrivateContact()
        for (key, flag, path) in [(CrewSettings.profilePhone, CrewSettings.profilePhonePrivate, \CrewProfile.phone),
                                  (CrewSettings.profileEmail, CrewSettings.profileEmailPrivate, \CrewProfile.email),
                                  (CrewSettings.profileFaceTime, CrewSettings.profileFaceTimePrivate, \CrewProfile.facetime)] {
            let text = value(key)
            if (isPrivate(flag) || !allow) && !text.isEmpty {
                switch key {
                case CrewSettings.profilePhone: hidden.phone = text
                case CrewSettings.profileEmail: hidden.email = text
                default: hidden.facetime = text
                }
            } else {
                profile[keyPath: path] = text
            }
        }
        let sealed = hidden.isEmpty ? nil : ContactSeal.seal(hidden, to: CrewCloud.shared.sealReaders())
        if await CrewCloud.shared.saveProfile(profile, photoFile: profile.photoID.isEmpty ? nil : photoFile, sealed: sealed) {
            defaults.set(now, forKey: CrewSettings.profileSaved)
        }
    }

    /// On a new phone or after a reinstall, fills in whatever this phone is missing from iCloud,
    /// so the first save doesn't wipe what you entered before. Local entries win.
    @MainActor static func restoreIfNeeded() async {
        guard !defaults.bool(forKey: CrewSettings.profileRestored) else { return }
        await CrewCloud.shared.connect()
        guard let myID = CrewCloud.shared.myID else { return }
        switch await CrewCloud.shared.fetchProfile(myID) {
        case .failed:
            return   // Try again next time Settings opens.
        case .none:
            break
        case .found(let saved):
            // Your name too, so a reinstall or a new phone doesn't ask it again (SignIn.swift).
            // Starting over (StartOver.swift): the name screen comes back, so the old name isn't put back.
            let startingOver = defaults.bool(forKey: CrewSettings.startingOver)
            for (key, cloud) in [(CrewSettings.name, startingOver ? "" : saved.name),
                                 (CrewSettings.profilePhone, saved.phone), (CrewSettings.profileEmail, saved.email),
                                 (CrewSettings.profileFaceTime, saved.facetime),
                                 (CrewSettings.profilePreferred, saved.preferred)] where value(key).isEmpty {
                defaults.set(cloud, forKey: key)
            }
            for (field, flag) in [("phone", CrewSettings.profilePhonePrivate), ("email", CrewSettings.profileEmailPrivate),
                                  ("facetime", CrewSettings.profileFaceTimePrivate)] where saved.privateFields.contains(field) {
                defaults.set(true, forKey: flag)
            }
            if value(CrewSettings.profilePhotoID).isEmpty, let photo = saved.photo,
               let data = photo.jpegData(compressionQuality: 0.85) {
                try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
                if (try? data.write(to: photoFile)) != nil {
                    defaults.set(saved.photoID, forKey: CrewSettings.profilePhotoID)
                }
            }
            // A profile is only saved from the home screen, so whoever has one already sent the application.
            if !startingOver { defaults.set(true, forKey: CrewSettings.applicationDone) }
            // Saved again on the next check, with this phone's merged entries and seal.
            defaults.set("", forKey: CrewSettings.profileSaved)
        }
        defaults.set(true, forKey: CrewSettings.profileRestored)
    }
}

// MARK: - iCloud

extension CrewCloud {
    enum ProfileFetch {
        case found(CrewProfile)
        case none
        case failed
    }

    private static func profileRecordID(_ memberID: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "profile.\(memberID)")
    }

    func saveProfile(_ profile: CrewProfile, photoFile: URL?, sealed: Data?) async -> Bool {
        await connect()
        guard let myID else { return false }
        let record = CKRecord(recordType: "Profile", recordID: Self.profileRecordID(myID))
        record["name"] = profile.name
        record["phone"] = profile.phone
        record["email"] = profile.email
        record["facetime"] = profile.facetime
        record["photoID"] = profile.photoID
        record["contactPreference"] = profile.preferred
        record["sealed"] = sealed
        record["photo"] = photoFile.map { CKAsset(fileURL: $0) }
        record["updatedAt"] = Date.now
        do {
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            if status.hasPrefix("Couldn't save your profile:") { status = "Connected to iCloud" }
            return true
        } catch {
            status = "Couldn't save your profile: \(error.localizedDescription)"
            return false
        }
    }

    /// A member's profile as you're allowed to see it.
    func fetchProfile(_ memberID: String) async -> ProfileFetch {
        await connect()
        guard myID != nil else { return .failed }
        let record: CKRecord
        do {
            record = try await db.record(for: Self.profileRecordID(memberID))
        } catch let error as CKError where error.code == .unknownItem {
            return .none   // They haven't saved a profile, or no one has yet and the type doesn't exist.
        } catch {
            status = "Couldn't load the profile: \(error.localizedDescription)"
            return .failed
        }
        // REM: anyone signed in to iCloud can create a record with any name, so a Profile counts
        // only when CloudKit says its member created it.
        guard writer(of: record) == memberID else { return .none }
        var profile = CrewProfile(id: memberID)
        profile.name = record["name"] as? String ?? ""
        profile.phone = record["phone"] as? String ?? ""
        profile.email = record["email"] as? String ?? ""
        profile.facetime = record["facetime"] as? String ?? ""
        profile.photoID = record["photoID"] as? String ?? ""
        profile.preferred = record["contactPreference"] as? String ?? ""
        // Coaches only: opens when one of the envelopes is for this phone. A plain field that's
        // filled in wins, so an old seal can't bring back a number they've since made public.
        if let sealed = record["sealed"] as? Data, let myID, let key = ContactKey.mine(create: false),
           let opened = ContactSeal.open(sealed, for: myID, key: key) {
            for (field, path, text) in [("phone", \CrewProfile.phone, opened.phone), ("email", \CrewProfile.email, opened.email),
                                        ("facetime", \CrewProfile.facetime, opened.facetime)] {
                guard let text, profile[keyPath: path].isEmpty else { continue }
                profile[keyPath: path] = text
                profile.privateFields.insert(field)
            }
        }
        if !profile.photoID.isEmpty, !Blocklist.hiddenPhotos.contains(profile.photoID),
           await !profilePhotoRemoved(profile.photoID),
           let url = (record["photo"] as? CKAsset)?.fileURL,
           let data = try? Data(contentsOf: url), let image = UIImage(data: data),
           await !ContentFilter.isSensitive(image) {
            profile.photo = image
        }
        return .found(profile)
    }

    /// A coach's PhotoRemoval for this profile photo. No challenge, so no leader: coaches and him.
    private func profilePhotoRemoved(_ photoID: String) async -> Bool {
        guard let removal = try? await db.record(for: CKRecord.ID(recordName: "removed.\(photoID)")) else { return false }
        return isModerator(writer(of: removal), leaderID: nil)
    }

    // MARK: Head coach's photo for someone

    // REM: his word, 2026-10-25: "as head coach i want to be able to maintain the user lists i want to
    // overide their avitar or add one if one is missing". He can't edit someone else's Profile record,
    // so his photo is a CrewPhoto of his own named avatar.<their ID> on the "avatars" board — an existing
    // record type, so nothing new to deploy in iCloud. It counts only when CloudKit says he wrote it
    // (GodMode.ids), and it wins over their own photo on every phone, theirs too. Remove it and their
    // own photo shows again.
    static let avatarsBoard = "avatars"

    private static func avatarRecordID(_ memberID: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "avatar.\(memberID)")
    }

    func loadAvatarOverrides() async {
        let query = CKQuery(recordType: "CrewPhoto", predicate: NSPredicate(format: "crewID == %@", Self.avatarsBoard))
        guard let (results, _) = try? await db.records(matching: query, desiredKeys: ["crewID", "thumb"], resultsLimit: 400) else { return }
        var found: [String: UIImage] = [:]
        for record in results.compactMap({ try? $0.1.get() }) {
            let name = record.recordID.recordName
            guard name.hasPrefix("avatar."), let by = writer(of: record), GodMode.ids.contains(by),
                  let url = (record["thumb"] as? CKAsset)?.fileURL,
                  let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { continue }
            found[String(name.dropFirst("avatar.".count))] = image
        }
        avatarOverrides = found
    }

    /// Head coach only: set someone's photo, or (nil) take yours off so theirs shows again.
    func setAvatarOverride(_ image: UIImage?, for memberID: String) async -> Bool {
        await connect()
        guard GodMode.isOwner, let myID else { return false }
        do {
            if let image {
                guard let thumb = Self.jpegFile(image, longestSide: 600) else { return false }
                defer { try? FileManager.default.removeItem(at: thumb) }
                let record = CKRecord(recordType: "CrewPhoto", recordID: Self.avatarRecordID(memberID))
                record["crewID"] = Self.avatarsBoard
                record["senderID"] = myID
                record["senderName"] = "Head Coach"
                record["takenAt"] = Date.now
                record["thumb"] = CKAsset(fileURL: thumb)
                _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
                avatarOverrides[memberID] = UIImage(contentsOfFile: thumb.path(percentEncoded: false)) ?? image
            } else {
                _ = try await db.modifyRecords(saving: [], deleting: [Self.avatarRecordID(memberID)])
                avatarOverrides[memberID] = nil
            }
            return true
        } catch {
            status = "Couldn't change the photo: \(error.localizedDescription)"
            return false
        }
    }

    /// The profile photo a report points at, for the Reports screen. Nil once it's been replaced.
    func profilePhoto(_ photoID: String) async -> UIImage? {
        let parts = photoID.split(separator: ".")
        guard parts.count == 3, parts[0] == "profile",
              let record = try? await db.record(for: Self.profileRecordID(String(parts[1]))),
              record["photoID"] as? String == photoID,
              let url = (record["photo"] as? CKAsset)?.fileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Settings → Your profile

/// Photo, phone, email and FaceTime, every one optional. Saved when Settings closes.
struct MyProfileSection: View {
    @AppStorage(CrewSettings.profilePhone) private var phone = ""
    @AppStorage(CrewSettings.profileEmail) private var email = ""
    @AppStorage(CrewSettings.profileFaceTime) private var facetime = ""
    @AppStorage(CrewSettings.profilePhotoID) private var photoID = ""
    @AppStorage(CrewSettings.profilePreferred) private var preferred = ""
    @AppStorage(CrewSettings.profilePhonePrivate) private var phonePrivate = false
    @AppStorage(CrewSettings.profileEmailPrivate) private var emailPrivate = false
    @AppStorage(CrewSettings.profileFaceTimePrivate) private var facetimePrivate = false
    @AppStorage(CrewSettings.profileAllowMemberContact) private var allowMemberContact = true
    @State private var picked: PhotosPickerItem?
    @State private var note: String?
    @State private var pickedBanner: PhotosPickerItem?
    @State private var bannerNote: String?
    @State private var hasBanner = false
    @State private var showingMine = false
    @AppStorage(CrewSettings.name) private var myName = ""

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        Section {
            HStack(spacing: 16) {
                ProfilePhoto(image: photoID.isEmpty ? nil : MyProfile.photo, size: 72, seed: CrewCloud.shared.myID ?? "")
                    .id(photoID)
                Text(photoID.isEmpty ? "No photo" : "Your photo").font(AppFont.body)
            }
            // One button per row, as on the photo board (two buttons in one row both fire).
            if cameraAvailable {
                Button { CameraPresenter.shared.present { image in Task { await use(image) } } } label: {
                    Label("Take Photo", systemImage: "camera.fill").font(AppFont.bodyBold)
                }
            }
            PhotosPicker(selection: $picked, matching: .images) {
                Label("Choose Photo", systemImage: "photo.on.rectangle").font(AppFont.bodyBold)
            }
            // REM: his word: "even if they want to use one as an avatar" (CrewMedia.swift).
            ChooseFromMediaButton { _, image in Task { await use(image) } }
            if !photoID.isEmpty {
                Button(role: .destructive) {
                    MyProfile.removePhoto()
                    note = nil
                    Task { await MyProfile.saveIfChanged() }
                } label: {
                    Label("Remove Photo", systemImage: "trash").font(AppFont.bodyBold)
                }
            }
            if let note { Text(note).font(AppFont.body) }
            // REM: his word, 2026-10-29: "a banner picture that can be personalized [often]" (Timeline.swift).
            if cameraAvailable {
                Button { CameraPresenter.shared.present { image in Task { await useBanner(image) } } } label: {
                    Label("Take Banner Photo", systemImage: "camera.fill").font(AppFont.bodyBold)
                }
            }
            PhotosPicker(selection: $pickedBanner, matching: .images) {
                Label(hasBanner ? "Change Banner" : "Choose Banner", systemImage: "rectangle.on.rectangle").font(AppFont.bodyBold)
            }
            if hasBanner {
                Button(role: .destructive) {
                    Task {
                        bannerNote = await CrewCloud.shared.removeMyBanner() ? nil : "The banner wasn't removed. Check iCloud and try again."
                        await checkBanner()
                    }
                } label: {
                    Label("Remove Banner", systemImage: "trash").font(AppFont.bodyBold)
                }
            }
            if let bannerNote { Text(bannerNote).font(AppFont.body) }
            Button { showingMine = true } label: {
                Label("View Your Profile and Timeline", systemImage: "person.crop.rectangle").font(AppFont.bodyBold)
            }
            TextField("Phone", text: $phone)
                .font(AppFont.body)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
            coachesOnly($phonePrivate)
            TextField("Email", text: $email)
                .font(AppFont.body)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            coachesOnly($emailPrivate)
            TextField("FaceTime phone or email", text: $facetime)
                .font(AppFont.body)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            coachesOnly($facetimePrivate)
            // His word, 2026-10-23: the directory "displays prefered contact method".
            Picker(selection: $preferred) {
                Text("No preference").font(AppFont.body).tag("")
                ForEach(ContactMethod.allCases) { Text($0.title).font(AppFont.body).tag($0.rawValue) }
            } label: {
                Text("Preferred contact").font(AppFont.body)
            }
            Toggle(isOn: $allowMemberContact) {
                Label("Allow other crew members to contact you", systemImage: "person.2.fill").font(AppFont.body)
            }
        } header: {
            Text("Your profile").font(AppFont.bodyBold).textCase(nil)
        } footer: {
            // REM: his word: "they have to manually add their contact info that way they can omit or
            // use alternate contact info". Sign in with Apple gives a name only.
            Text("Everything here is optional. Your crewmates see your photo and a button for each way you fill in. Leave any blank to keep it private, or switch on Coaches only to share it with coaches and no one else. Your preferred contact shows next to your name in the Crew Directory. Switch off Allow other crew members to contact you and only coaches can reach you.")
                .font(AppFont.body)
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await use(image)
                }
                picked = nil
            }
        }
        .onChange(of: pickedBanner) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await useBanner(image)
                }
                pickedBanner = nil
            }
        }
        .task { await checkBanner() }
        .sheet(isPresented: $showingMine, onDismiss: { Task { await checkBanner() } }) {
            if let me = CrewCloud.shared.myID { ProfileView(target: ProfileTarget(id: me, name: myName)) }
        }
    }

    private func useBanner(_ image: UIImage) async {
        bannerNote = "Checking your banner…"
        let me = myName.trimmingCharacters(in: .whitespaces)
        bannerNote = await CrewCloud.shared.setBanner(image, senderName: me.isEmpty ? "A crew member" : me)
            ? "Banner saved." : "This photo can't be used as your banner, or iCloud didn't answer."
        await checkBanner()
    }

    private func checkBanner() async {
        await CrewCloud.shared.connect()
        guard let me = CrewCloud.shared.myID else { return }
        hasBanner = await CrewCloud.shared.banner(of: me) != nil
    }

    private func coachesOnly(_ isOn: Binding<Bool>) -> some View {
        // With other members' contact switched off, everything is coaches only already.
        Toggle(isOn: allowMemberContact ? isOn : .constant(true)) { Label("Coaches only", systemImage: "lock.fill").font(AppFont.body) }
            .disabled(!allowMemberContact)
    }

    private func use(_ image: UIImage) async {
        note = "Checking your photo…"
        if await MyProfile.setPhoto(image) {
            photoID = UserDefaults.standard.string(forKey: CrewSettings.profilePhotoID) ?? ""
            note = nil
            await MyProfile.saveIfChanged()
        } else {
            note = "This photo can't be used for your profile."
        }
    }
}

// MARK: - Someone's profile

/// A round photo, or a dumbbell when there's none.
/// REM: his word, 2026-10-24: "can blank profiles be default? maybe with random avatar ... or a piece of
/// gym equipment like a dumbbell or kettlebell". Apple's symbols have a dumbbell but no kettlebell. The
/// color comes from their ID (`seed`), so one person always gets the same one on every phone.
struct ProfilePhoto: View {
    let image: UIImage?
    let size: CGFloat
    var seed: String = ""

    private static let colors: [Color] = [.blue, .orange, .green, .purple, .red, .teal, .indigo, .pink]
    /// Summed scalars, not hashValue: Swift seeds hashValue fresh on every launch.
    private var color: Color {
        seed.isEmpty ? .secondary : Self.colors[seed.unicodeScalars.reduce(0) { $0 + Int($1.value) } % Self.colors.count]
    }

    var body: some View {
        Group {
            // The head coach's photo for them wins (CrewCloud.avatarOverrides).
            if let image = CrewCloud.shared.avatarOverrides[seed] ?? image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "dumbbell.fill").resizable().scaledToFit().padding(size * 0.2)
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
        .background(color.opacity(0.15))
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// Who the profile sheet is for. The name is what the board or message showed, for before the
/// profile loads or when they haven't saved one.
struct ProfileTarget: Identifiable {
    let id: String
    let name: String
}

enum ProfileAction: String, Identifiable {
    case report, block, remove, reportBanner, removeBanner
    var id: String { rawValue }
}

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    let target: ProfileTarget
    /// Message shows for coaches, and for anyone answering a direct message (the Inbox passes true).
    var canMessage = false
    @AppStorage(CrewSettings.name) private var myName = ""
    @State private var draft = ""
    @State private var sending = false
    @State private var sentNote: String?

    @State private var profile: CrewProfile?
    /// Their banner (Timeline.swift), and the photo behind it for Report / Remove.
    @State private var banner: (photo: CrewPhoto, image: UIImage)?
    @State private var loaded = false
    @State private var confirming: ProfileAction?
    @State private var note: String?
    @State private var failed = false
    /// Their points, league and awards (Rewards.swift); nil until they have a card.
    @State private var rewards: RewardCard?

    private var isMine: Bool { target.id == CrewCloud.shared.myID }
    /// Their saved name, else the one the board or message showed.
    private var savedName: String {
        let saved = profile?.name.trimmingCharacters(in: .whitespaces) ?? ""
        return saved.isEmpty ? target.name : saved
    }
    private var name: String { isMine ? "You" : savedName }

    var body: some View {
        NavigationStack {
            List {
                MemberAccessSection(memberID: target.id, name: savedName)
                Section {
                    VStack(spacing: 12) {
                        // REM: his word, 2026-10-29: "the profile has their picture and a banner picture".
                        ProfileHeader(memberID: target.id, photo: profile?.photo, banner: banner?.image)
                        Text(name).font(AppFont.title).multilineTextAlignment(.center)
                        if let profile, let method = ContactMethod.preferred(profile) {
                            Label("Prefers \(method.title)", systemImage: method.systemImage)
                                .font(AppFont.body).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
                    .listRowInsets(EdgeInsets())
                }
                if let rewards { RewardsSection(card: rewards) }
                Section {
                    contactButtons
                    if !loaded {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Loading…").font(AppFont.body)
                        }
                    } else if let profile, hasContact(profile) {
                        if !profile.privateFields.isEmpty {
                            Label(isMine ? "Locked items are for coaches only." : "Locked items: you see them as a coach.",
                                  systemImage: "lock.fill").font(AppFont.body).foregroundStyle(.secondary)
                        }
                        // REM: his word: "export … to apple contacts" · "i want it to be one contact and
                        // not all contacts". One card, only what they typed; no Contacts access asked.
                        Button { ContactsPresenter.shared.save(contact(from: profile)) } label: {
                            Label("Save to Contacts", systemImage: "person.crop.circle.badge.plus").font(AppFont.bodyBold)
                        }
                    } else {
                        Text(isMine ? "You haven't added contact info. Add it in Settings."
                                    : "No contact info shared yet.").font(AppFont.body)
                    }
                } header: {
                    Text("Contact").font(AppFont.bodyBold).textCase(nil)
                }
                // REM: his word, 2026-10-24: "as a coach go into a crew directory and tap into a user card and
                // have a button to send a message to the crew members inbox" — reaches people who shared nothing.
                if !isMine && (canMessage || GodMode.isOn) {
                    Section {
                        TextField("Message to \(savedName)", text: $draft, axis: .vertical)
                            .font(AppFont.body).lineLimit(1...6)
                        Button { Task { await sendMessage() } } label: {
                            Label("Send to Their Inbox", systemImage: "paperplane.fill").font(AppFont.bodyBold)
                        }
                        .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if let sentNote { Text(sentNote).font(AppFont.body).foregroundStyle(.secondary) }
                    } header: {
                        Text("Message").font(AppFont.bodyBold).textCase(nil)
                    } footer: {
                        Text("Goes to their Rep Crew Inbox, and as a notification if they allow it. No contact info needed.")
                            .font(AppFont.body)
                    }
                }
                TimelineSection(memberID: target.id, name: savedName)
                if note != nil || failed {
                    Section {
                        if let note { Text(note).font(AppFont.body) }
                        if failed {
                            Text("That didn't go through. Check iCloud in Settings and try again.").font(AppFont.body)
                        }
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(AppFont.bodyBold)
                }
                if !isMine {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            if profile?.photo != nil {
                                Button { confirming = .report } label: {
                                    Label("Report Photo", systemImage: "exclamationmark.bubble")
                                }
                                // REM: his word: "coach level remove". No challenge here, so no leader.
                                if GodMode.isOn {
                                    Button(role: .destructive) { confirming = .remove } label: {
                                        Label("Remove Photo", systemImage: "trash")
                                    }
                                }
                            }
                            if banner != nil {
                                Button { confirming = .reportBanner } label: {
                                    Label("Report Banner", systemImage: "exclamationmark.bubble")
                                }
                                if GodMode.isOn {
                                    Button(role: .destructive) { confirming = .removeBanner } label: {
                                        Label("Remove Banner", systemImage: "trash")
                                    }
                                }
                            }
                            Button { confirming = .block } label: {
                                Label("Block \(name)", systemImage: "hand.raised.fill")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle").font(AppFont.bodyBold)
                        }
                        .accessibilityLabel("More")
                    }
                }
            }
            .confirmationDialog(question, isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                                titleVisibility: .visible, presenting: confirming) { action in
                Button(buttonTitle(action), role: .destructive) { Task { await act(action) } }
            }
            .task { await load() }
        }
    }

    // MARK: Buttons

    private func sendMessage() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        failed = false
        let me = myName.trimmingCharacters(in: .whitespaces)
        if await CrewCloud.shared.send(text, crewID: CrewMessage.direct(to: target.id), kind: .direct, to: target.id,
                                       senderName: me.isEmpty ? "A crew member" : me) {
            draft = ""
            sentNote = "Sent to \(savedName)'s Inbox."
        } else {
            failed = true
        }
        sending = false
    }

    /// One per way they filled in; a blank field shows nothing.
    @ViewBuilder private var contactButtons: some View {
        if let profile {
            if let url = Self.url("tel:", Self.dialable(profile.phone)) {
                Link(destination: url) { Label("Call", systemImage: "phone.fill").font(AppFont.bodyBold) }
            }
            if let url = Self.url("sms:", Self.dialable(profile.phone)) {
                Link(destination: url) { Label("Text", systemImage: "message.fill").font(AppFont.bodyBold) }
            }
            if let url = Self.url("mailto:", profile.email.trimmingCharacters(in: .whitespaces)) {
                Link(destination: url) { Label("Email", systemImage: "envelope.fill").font(AppFont.bodyBold) }
            }
            if let url = Self.url("facetime-audio:", Self.handle(profile.facetime)) {
                Link(destination: url) { Label("FaceTime Audio", systemImage: "phone.circle.fill").font(AppFont.bodyBold) }
            }
            if let url = Self.url("facetime:", Self.handle(profile.facetime)) {
                Link(destination: url) { Label("FaceTime Video", systemImage: "video.fill").font(AppFont.bodyBold) }
            }
        }
    }

    private func hasContact(_ profile: CrewProfile) -> Bool {
        ![profile.phone, profile.email, profile.facetime].allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Digits and a leading +, which is all a phone link wants.
    static func dialable(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.filter(\.isNumber)
        return digits.isEmpty ? "" : (trimmed.hasPrefix("+") ? "+" : "") + digits
    }

    /// An email address as typed, or a phone number as digits.
    static func handle(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") ? trimmed : dialable(trimmed)
    }

    static func url(_ scheme: String, _ value: String) -> URL? {
        guard !value.isEmpty, let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: scheme + encoded)
    }

    private func contact(from profile: CrewProfile) -> CNMutableContact {
        let card = CNMutableContact()
        card.givenName = savedName
        let phone = profile.phone.trimmingCharacters(in: .whitespaces)
        if !phone.isEmpty {
            card.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone))]
        }
        var emails: [String] = []
        let email = profile.email.trimmingCharacters(in: .whitespaces)
        if !email.isEmpty { emails.append(email) }
        let facetime = profile.facetime.trimmingCharacters(in: .whitespaces)
        if facetime.contains("@"), facetime != email { emails.append(facetime) }
        card.emailAddresses = emails.map { CNLabeledValue(label: CNLabelHome, value: $0 as NSString) }
        if !facetime.isEmpty, !facetime.contains("@"), Self.dialable(facetime) != Self.dialable(phone) {
            card.phoneNumbers.append(CNLabeledValue(label: CNLabelPhoneNumberiPhone, value: CNPhoneNumber(stringValue: facetime)))
        }
        card.imageData = profile.photo?.jpegData(compressionQuality: 0.85)
        return card
    }

    // MARK: Moderation

    private var question: String {
        switch confirming {
        case .report: return "Report this photo to the developer?"
        case .block: return "Block \(name)?"
        case .remove: return "Remove this photo for everyone?"
        case .reportBanner: return "Report this banner to the developer?"
        case .removeBanner: return "Remove this banner for everyone?"
        case nil: return ""
        }
    }

    private func buttonTitle(_ action: ProfileAction) -> String {
        switch action {
        case .report: return "Report"
        case .block: return "Block"
        case .remove: return "Remove Photo"
        case .reportBanner: return "Report"
        case .removeBanner: return "Remove Banner"
        }
    }

    /// The photo board's own Report, Block and PhotoRemoval, pointed at the profile photo.
    private func act(_ action: ProfileAction) async {
        failed = false
        // The banner is a CrewPhoto of its own (Timeline.swift), so the photo board's Report and removal fit it as is.
        if action == .reportBanner || action == .removeBanner {
            guard let banner else { return }
            let done = action == .reportBanner ? await CrewCloud.shared.report(banner.photo, kind: "banner")
                                               : await CrewCloud.shared.removePhoto(banner.photo)
            if done {
                if action == .reportBanner { note = "Reported. The developer reviews every report, and the banner is hidden for you." }
                await load()
            } else {
                failed = true
            }
            return
        }
        guard let profile else { return }
        let photo = CrewPhoto(id: profile.photoID, crewID: MyProfile.crewIDForRemovals, senderID: target.id,
                              senderName: name, takenAt: .now, thumb: nil)
        switch action {
        case .report:
            if await CrewCloud.shared.report(photo, kind: "profile") {
                note = "Reported. The developer reviews every report, and the photo is hidden for you."
                await load()
            } else {
                failed = true
            }
        case .block:
            Blocklist.block(target.id, name: name)
            dismiss()
        case .remove:
            if await CrewCloud.shared.removePhoto(photo) { await load() } else { failed = true }
        case .reportBanner, .removeBanner:
            break   // handled above
        }
    }

    private func load() async {
        if case .found(let found) = await CrewCloud.shared.fetchProfile(target.id) { profile = found }
        banner = await CrewCloud.shared.banner(of: target.id)
        rewards = await Rewards.card(for: target.id)
        loaded = true
    }
}

// MARK: - Contacts and Messages

/// Presented from the window's top screen, like the camera (CameraPresenter), so a redraw
/// underneath doesn't take them away.
final class ContactsPresenter: NSObject, CNContactViewControllerDelegate, CNContactPickerDelegate,
                               MFMessageComposeViewControllerDelegate {
    static let shared = ContactsPresenter()
    private var inviteText = ""

    /// Export: one card, prefilled, for the person to save or add to an existing contact.
    @MainActor func save(_ contact: CNMutableContact) {
        guard let top = CameraPresenter.topScreen() else { return }
        let card = CNContactViewController(forUnknownContact: contact)
        card.contactStore = CNContactStore()
        card.allowsActions = false
        card.delegate = self
        card.navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak card] _ in
            card?.dismiss(animated: true)
        })
        top.present(UINavigationController(rootViewController: card), animated: true)
    }

    func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        viewController.dismiss(animated: true)
    }

    /// Import: pick one person's phone number or email, then the invite goes to just that one.
    /// REM: his word: "i want it to be one contact and not all contacts". Apple's picker gives the
    /// app only what's picked and asks for no permission.
    @MainActor func invite(text: String) {
        guard let top = CameraPresenter.topScreen() else { return }
        inviteText = text
        let picker = CNContactPickerViewController()
        picker.delegate = self
        picker.displayedPropertyKeys = MFMessageComposeViewController.canSendText()
            ? [CNContactPhoneNumbersKey, CNContactEmailAddressesKey] : [CNContactEmailAddressesKey]
        picker.predicateForEnablingContact = MFMessageComposeViewController.canSendText()
            ? NSPredicate(format: "phoneNumbers.@count > 0 OR emailAddresses.@count > 0")
            : NSPredicate(format: "emailAddresses.@count > 0")
        top.present(picker, animated: true)
    }

    func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
        let text = inviteText
        let phone = (contactProperty.value as? CNPhoneNumber)?.stringValue
        let email = contactProperty.value as? String
        // The picker closes itself after a pick; Messages waits until it's gone.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.6))
            if let phone {
                self.text(text, to: phone)
            } else if let email {
                self.email(text, to: email)
            }
        }
    }

    @MainActor private func text(_ body: String, to phone: String) {
        guard MFMessageComposeViewController.canSendText(), let top = CameraPresenter.topScreen() else { return }
        let compose = MFMessageComposeViewController()
        compose.recipients = [phone]
        compose.body = body
        compose.messageComposeDelegate = self
        top.present(compose, animated: true)
    }

    /// Mail, through a mailto: link: whatever mail app this phone uses opens with it addressed.
    @MainActor private func email(_ body: String, to address: String) {
        var parts = URLComponents()
        parts.scheme = "mailto"
        parts.path = address
        parts.queryItems = [URLQueryItem(name: "subject", value: "Join my crew on Rep Crew"),
                            URLQueryItem(name: "body", value: body)]
        if let url = parts.url { UIApplication.shared.open(url) }
    }

    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        controller.dismiss(animated: true)
    }
}
