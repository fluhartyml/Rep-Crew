//
//  PhotoBoard.swift
//  Rep Crew
//
//  A challenge's photo strip. Michael's idea, 2026-10-22: "maybe the crew is at a gym doing
//  challenges together perhaps a crewmember takes a picture of the team on the treadmills or
//  someone doing swiming laps." Anyone in the challenge adds one from the camera or their
//  library; everyone sees the thumbnails; tap one for full size. His word: "i want anyone to be
//  able to long press on a photo or something similar to save to their camera roll".
//
//  Two record types in the crew's iCloud space:
//    CrewPhoto     crewID, senderID, senderName, takenAt, thumb (small JPEG), image (full JPEG).
//    PhotoRemoval  name = removed.<photo ID>; crewID, photoID, removedBy.
//  Whoever posted a photo deletes it outright. The leader can't delete someone else's record
//  in the public database, so the leader leaves a PhotoRemoval and every phone hides the photo
//  — but only when it was the leader who left it. His word: "the leader can kick ban anyone
//  that posts pervy pictures" (kick/ban itself is the next piece).
//

import CloudKit
import Photos
import PhotosUI
import SwiftUI

struct CrewPhoto: Identifiable {
    let id: String
    let crewID: String
    let senderID: String
    let senderName: String
    let takenAt: Date
    let thumb: UIImage?
}

// MARK: - iCloud

extension CrewCloud {
    func postPhoto(_ image: UIImage, crewID: String, senderName: String) async -> Bool {
        await connect()
        guard let myID,
              let thumb = Self.jpegFile(image, longestSide: 400),
              let full = Self.jpegFile(image, longestSide: 1600) else { return false }
        defer { try? FileManager.default.removeItem(at: thumb); try? FileManager.default.removeItem(at: full) }
        let record = CKRecord(recordType: "CrewPhoto")
        record["crewID"] = crewID
        record["senderID"] = myID
        record["senderName"] = senderName
        record["takenAt"] = Date.now
        record["thumb"] = CKAsset(fileURL: thumb)
        record["image"] = CKAsset(fileURL: full)
        do {
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            return true
        } catch {
            status = "Couldn't share your photo: \(error.localizedDescription)"
            return false
        }
    }

    /// The challenge's photos, newest first, as thumbnails. `leaderID` empty means you lead it.
    func photos(crewID: String, leaderID: String) async -> [CrewPhoto] {
        await connect()
        guard let myID else { return [] }
        let leader = leaderID.isEmpty ? myID : leaderID
        let query = CKQuery(recordType: "CrewPhoto", predicate: NSPredicate(format: "crewID == %@", crewID))
        let photos: [CrewPhoto]
        do {
            let (results, _) = try await db.records(matching: query, desiredKeys: ["crewID", "senderID", "senderName", "takenAt", "thumb"],
                                                    resultsLimit: 200)
            photos = results.compactMap { try? $0.1.get() }.compactMap(Self.photo(from:))
        } catch let error as CKError where error.code == .unknownItem {
            return []   // No one has posted a photo yet, so the record type doesn't exist yet.
        } catch {
            status = "Couldn't load photos: \(error.localizedDescription)"
            return []
        }
        // Only the leader's removals count.
        var removed: Set<String> = []
        let removals = CKQuery(recordType: "PhotoRemoval", predicate: NSPredicate(format: "crewID == %@", crewID))
        if let (results, _) = try? await db.records(matching: removals) {
            for record in results.compactMap({ try? $0.1.get() }) where record["removedBy"] as? String == leader {
                if let id = record["photoID"] as? String { removed.insert(id) }
            }
        }
        let hide = await hidden(crewID: crewID, leaderID: leader)
        let reported = Blocklist.hiddenPhotos
        return photos.filter { !removed.contains($0.id) && !reported.contains($0.id) && !hide.contains($0.senderID) }
            .sorted { $0.takenAt > $1.takenAt }
    }

    func fullPhoto(_ id: String) async -> UIImage? {
        guard let record = try? await db.record(for: CKRecord.ID(recordName: id)),
              let url = (record["image"] as? CKAsset)?.fileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Saves the full-size photo to this phone's photo library.
    func savePhotoToLibrary(_ id: String) async -> Bool {
        guard let image = await fullPhoto(id) else { return false }
        return await Self.saveToLibrary(image)
    }

    static func saveToLibrary(_ image: UIImage) async -> Bool {
        guard await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: image) }
            return true
        } catch {
            return false
        }
    }

    /// Yours: deleted. Someone else's, as leader: hidden from every phone.
    func removePhoto(_ photo: CrewPhoto) async -> Bool {
        await connect()
        guard let myID else { return false }
        do {
            if photo.senderID == myID {
                _ = try await db.modifyRecords(saving: [], deleting: [CKRecord.ID(recordName: photo.id)])
            } else {
                let record = CKRecord(recordType: "PhotoRemoval", recordID: CKRecord.ID(recordName: "removed.\(photo.id)"))
                record["crewID"] = photo.crewID
                record["photoID"] = photo.id
                record["removedBy"] = myID
                _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            }
            return true
        } catch {
            status = "Couldn't remove the photo: \(error.localizedDescription)"
            return false
        }
    }

    private static func photo(from record: CKRecord) -> CrewPhoto? {
        guard let crewID = record["crewID"] as? String, let senderID = record["senderID"] as? String else { return nil }
        let thumb = ((record["thumb"] as? CKAsset)?.fileURL).flatMap { try? Data(contentsOf: $0) }.flatMap(UIImage.init(data:))
        return CrewPhoto(id: record.recordID.recordName, crewID: crewID, senderID: senderID,
                         senderName: record["senderName"] as? String ?? "Crew member",
                         takenAt: record["takenAt"] as? Date ?? record.creationDate ?? .now, thumb: thumb)
    }

    /// A JPEG no bigger than `longestSide` pixels, written to a temporary file for upload.
    private static func jpegFile(_ image: UIImage, longestSide: CGFloat) -> URL? {
        let scale = min(1, longestSide / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let data = UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.75) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".jpg")
        return (try? data.write(to: url)) == nil ? nil : url
    }
}

// MARK: - On a challenge

struct PhotoBoardSection: View {
    let crewID: String
    /// Empty when you lead the challenge.
    let leaderID: String
    /// Only people in the challenge add photos.
    let canAdd: Bool

    @AppStorage(CrewSettings.name) private var name = ""
    @State private var photos: [CrewPhoto] = []
    @State private var picked: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var uploading = false
    @State private var failed = false
    @State private var viewing: CrewPhoto?
    @State private var saveNote: String?

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        if !crewID.isEmpty {
            Section {
                // One button per row: two buttons sharing a List row both fire on a tap (build 35
                // opened the camera when Choose Photo was tapped, and neither screen worked).
                if canAdd {
                    if cameraAvailable {
                        Button { showingCamera = true } label: {
                            Label("Take Photo", systemImage: "camera.fill").font(AppFont.bodyBold)
                        }
                        .disabled(uploading)
                    }
                    PhotosPicker(selection: $picked, matching: .images) {
                        Label("Choose Photo", systemImage: "photo.on.rectangle").font(AppFont.bodyBold)
                    }
                    .disabled(uploading)
                }
                if uploading {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Sharing your photo…").font(AppFont.body)
                    }
                } else if failed {
                    Text("It didn't upload. Check iCloud in Settings and try again.").font(AppFont.body)
                }
                if let saveNote { Text(saveNote).font(AppFont.body) }
                if photos.isEmpty {
                    if !canAdd { Text("No photos yet.").font(AppFont.body) }
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 10) {
                            ForEach(photos) { photo in
                                Button { viewing = photo } label: { thumbnail(photo) }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Photo from \(photo.senderName)")
                                    .contextMenu {
                                        Button { Task { await save(photo) } } label: {
                                            Label("Save to Photos", systemImage: "square.and.arrow.down")
                                        }
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.hidden)
                }
            } header: {
                Text("Photos").font(AppFont.bodyBold).textCase(nil)
            }
            .task(id: crewID) { await load() }
            .onChange(of: picked) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        await upload(image)
                    }
                    picked = nil
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in Task { await upload(image) } }.ignoresSafeArea()
            }
            .sheet(item: $viewing) { photo in
                PhotoViewer(photo: photo, isMine: photo.senderID == CrewCloud.shared.myID, isLeader: isLeader) { action in
                    await act(action, on: photo)
                }
            }
        }
    }

    private func thumbnail(_ photo: CrewPhoto) -> some View {
        Group {
            if let thumb = photo.thumb {
                Image(uiImage: thumb).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").font(AppFont.heading).foregroundStyle(.secondary)
            }
        }
        .frame(width: 96, height: 96)
        .background(Color.secondary.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var isLeader: Bool { leaderID.isEmpty || leaderID == CrewCloud.shared.myID }

    /// Carries out what was picked in the photo's menu; true when it worked.
    private func act(_ action: PhotoAction, on photo: CrewPhoto) async -> Bool {
        let done: Bool
        switch action {
        case .remove:
            done = await CrewCloud.shared.removePhoto(photo)
        case .report:
            done = await CrewCloud.shared.report(photo)
            if done { saveNote = "Reported. The developer reviews every report, and the photo is hidden for you." }
        case .block:
            Blocklist.block(photo.senderID, name: photo.senderName)
            done = true
            saveNote = "\(photo.senderName) is blocked. Unblock in Settings."
        case .ban:
            let banned = await CrewCloud.shared.ban(crewID: crewID, memberID: photo.senderID, name: photo.senderName)
            let hiddenPhoto = await CrewCloud.shared.removePhoto(photo)
            done = banned && hiddenPhoto
        }
        if done { await load() }
        return done
    }

    private func save(_ photo: CrewPhoto) async {
        saveNote = "Saving…"
        saveNote = await CrewCloud.shared.savePhotoToLibrary(photo.id)
            ? "Saved to Photos."
            : "It wasn't saved. Allow Rep Crew to add photos in the iPhone Settings app."
    }

    private func load() async {
        photos = await CrewCloud.shared.photos(crewID: crewID, leaderID: leaderID)
    }

    private func upload(_ image: UIImage) async {
        uploading = true
        failed = false
        let me = name.trimmingCharacters(in: .whitespaces)
        if await CrewCloud.shared.postPhoto(image, crewID: crewID, senderName: me.isEmpty ? "A crew member" : me) {
            await load()
        } else {
            failed = true
        }
        uploading = false
    }
}

enum PhotoAction: String, Identifiable {
    case remove, report, block, ban
    var id: String { rawValue }
}

private struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let photo: CrewPhoto
    let isMine: Bool
    let isLeader: Bool
    let perform: (PhotoAction) async -> Bool

    @State private var full: UIImage?
    @State private var confirming: PhotoAction?
    @State private var failed = false
    @State private var saveNote: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let image = full ?? photo.thumb {
                    Image(uiImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                if full == nil { ProgressView() }
                Text("\(photo.senderName) · \(photo.takenAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(AppFont.body)
                if let saveNote { Text(saveNote).font(AppFont.body) }
                if failed {
                    Text("That didn't go through. Check iCloud in Settings and try again.").font(AppFont.body)
                }
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(AppFont.bodyBold)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        guard let full else { return }
                        Task {
                            saveNote = await CrewCloud.saveToLibrary(full)
                                ? "Saved to Photos."
                                : "It wasn't saved. Allow Rep Crew to add photos in the iPhone Settings app."
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.down").font(AppFont.bodyBold)
                    }
                    .disabled(full == nil)
                    .accessibilityLabel("Save to Photos")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        if isMine || isLeader {
                            Button(role: .destructive) { confirming = .remove } label: {
                                Label("Remove Photo", systemImage: "trash")
                            }
                        }
                        if !isMine {
                            Button { confirming = .report } label: {
                                Label("Report Photo", systemImage: "exclamationmark.bubble")
                            }
                            Button { confirming = .block } label: {
                                Label("Block \(photo.senderName)", systemImage: "hand.raised.fill")
                            }
                            if isLeader {
                                Button(role: .destructive) { confirming = .ban } label: {
                                    Label("Remove Photo and Ban \(photo.senderName)", systemImage: "person.fill.xmark")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(AppFont.bodyBold)
                    }
                    .accessibilityLabel("More")
                }
            }
            .confirmationDialog(question, isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                                titleVisibility: .visible, presenting: confirming) { action in
                Button(buttonTitle(action), role: .destructive) {
                    Task { if await perform(action) { dismiss() } else { failed = true } }
                }
            }
            .task { full = await CrewCloud.shared.fullPhoto(photo.id) }
        }
    }

    private var question: String {
        switch confirming {
        case .remove: return "Remove this photo for the whole crew?"
        case .report: return "Report this photo to the developer?"
        case .block: return "Block \(photo.senderName)?"
        case .ban: return "Remove this photo and ban \(photo.senderName) from the challenge?"
        case nil: return ""
        }
    }

    private func buttonTitle(_ action: PhotoAction) -> String {
        switch action {
        case .remove: return "Remove Photo"
        case .report: return "Report"
        case .block: return "Block"
        case .ban: return "Remove and Ban"
        }
    }
}

/// The camera, for a photo taken on the spot.
private struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onImage: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
