//
//  Timeline.swift
//  Rep Crew
//
//  A profile banner and a timeline under it. His words, 2026-10-29 (Smitty sitting with him): "a profile
//  timeline feed where the profile has their picture and a banner picture that can be personalized
//  [often]" · "both posts and finished challenges and youtube video imbeds" · "the videos would be imbeded
//  from youtube links and not the physical video file" · "it plays if you press play" · "can you code it".
//  James's safeguard (his FaceTime, pasted): a video that needs the internet asks before it leaves the app.
//
//  REM: no new iCloud record type, so nothing new to deploy to Production:
//    • A post is a CrewMessage (kind .post) on the board crewID "timeline.<owner ID>", its details as JSON
//      in the text — the same idea as the Events board. Builds before this never ask for that crewID.
//      Only the owner's own posts count (CloudKit's creator, not a field), so no one posts on your page.
//    • A post's photo and the banner are CrewPhotos: crewID "timeline.<owner ID>" and "banner.<owner ID>".
//      Each new banner is a new record (the old one is deleted), so a coach's removal hides that one only.
//    • Finished challenges aren't posted: they're read from the same Progress records as the ×N seal in
//      the Crew Directory (every day complete, records they wrote), so old ones show up too.
//  REM: removing someone else's post or banner is coaches and him (GodMode.isOn) — a MessageRemoval or a
//  PhotoRemoval, honored only when a coach or he wrote it. No challenge here, so no leader.
//  REM: the YouTube player is YouTube's own embed in a web view. It shows a still until you press play
//  (his word), and any link that would leave Rep Crew asks first (James's safeguard).
//

import CloudKit
import PhotosUI
import SwiftUI
import WebKit

/// What a post holds, saved as JSON in the message text.
struct TimelinePostDetails: Codable, Equatable {
    var text = ""
    /// The YouTube link as typed; nil for none.
    var youtube: String? = nil
    /// A CrewPhoto on the owner's timeline board; nil for none.
    var photoID: String? = nil
}

struct TimelineItem: Identifiable {
    enum Content {
        case post(CrewMessage, TimelinePostDetails)
        case finished(crewID: String, title: String)
    }
    let id: String
    let date: Date
    let content: Content
}

// MARK: - Leaving the app

extension CrewSettings {
    /// OutsideLinks.Rule raw value; unset = ask.
    static let outsideLinks = "outsideLinks"
}

/// What happens when something in Rep Crew would open outside it (a YouTube link out of the player).
enum OutsideLinks {
    enum Rule: String, CaseIterable, Identifiable {
        case ask, open, never
        var id: String { rawValue }
        var title: String {
            switch self {
            case .ask: "Ask Me"
            case .open: "Always Open"
            case .never: "Never Open"
            }
        }
    }

    static var rule: Rule {
        get { Rule(rawValue: UserDefaults.standard.string(forKey: CrewSettings.outsideLinks) ?? "") ?? .ask }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: CrewSettings.outsideLinks) }
    }
}

// MARK: - YouTube links

enum YouTubeLink {
    /// The 11-character video ID from a watch, share (youtu.be), Shorts, live or embed link. Nil when it isn't one.
    static func videoID(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed.contains("://") ? trimmed : "https://" + trimmed),
              let host = url.host?.lowercased() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        var candidate: String?
        if host == "youtu.be" {
            candidate = parts.first
        } else if host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtube-nocookie.com" || host.hasSuffix(".youtube-nocookie.com") {
            if parts.first == "watch" {
                candidate = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value
            } else if parts.count >= 2, ["shorts", "embed", "live", "v"].contains(parts[0]) {
                candidate = parts[1]
            }
        }
        guard let id = candidate, id.count == 11,
              id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }) else { return nil }
        return id
    }

    static func thumbnail(_ id: String) -> URL? { URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg") }
    static func watch(_ id: String) -> URL? { URL(string: "https://www.youtube.com/watch?v=\(id)") }
}

// MARK: - iCloud

extension CrewCloud {
    static func timelineBoard(_ memberID: String) -> String { "timeline.\(memberID)" }
    static func bannerBoard(_ memberID: String) -> String { "banner.\(memberID)" }

    /// Posts on your own timeline. The photo goes through the photo board's filter first.
    func postToTimeline(_ details: TimelinePostDetails, photo: UIImage?, senderName: String) async -> Bool {
        await connect()
        guard let myID else { return false }
        var details = details
        if let photo {
            if await ContentFilter.isSensitive(photo) { return false }
            guard let id = await postPhotoID(photo, crewID: Self.timelineBoard(myID), senderName: senderName) else { return false }
            details.photoID = id
        }
        guard let json = try? JSONEncoder().encode(details), let text = String(data: json, encoding: .utf8) else { return false }
        return await send(text, crewID: Self.timelineBoard(myID), kind: .post, senderName: senderName)
    }

    /// Someone's timeline, newest first: their own posts plus the challenges they finished.
    func timeline(of memberID: String) async -> [TimelineItem] {
        await connect()
        async let posts = timelinePosts(memberID)
        async let finished = finishedChallengeList(memberID)
        return (await posts + finished).sorted { $0.date > $1.date }
    }

    private func timelinePosts(_ memberID: String) async -> [TimelineItem] {
        let board = Self.timelineBoard(memberID)
        guard !Blocklist.ids.contains(memberID) else { return [] }
        let query = CKQuery(recordType: "CrewMessage", predicate: NSPredicate(format: "crewID == %@", board))
        guard let (results, _) = try? await db.records(matching: query, resultsLimit: 200) else { return [] }
        let removed = await removedMessages(crewID: board, leaderID: nil)
        return results.compactMap { try? $0.1.get() }
            .filter { writer(of: $0) == memberID }
            .compactMap(Self.message(from:))
            .filter { $0.kind == .post && !removed.contains($0.id) }
            .compactMap { message in
                guard let details = try? JSONDecoder().decode(TimelinePostDetails.self, from: Data(message.text.utf8)) else { return nil }
                return TimelineItem(id: message.id, date: message.sentAt, content: .post(message, details))
            }
    }

    /// The challenges someone finished (every day complete in Progress records they wrote), dated by
    /// their last day's record. Same rule as the ×N seal (finishedChallenges in CrewDirectory.swift).
    private func finishedChallengeList(_ memberID: String) async -> [TimelineItem] {
        guard !Blocklist.ids.contains(memberID) else { return [] }
        let query = CKQuery(recordType: "Progress", predicate: NSPredicate(format: "memberID == %@ AND complete == 1", memberID))
        guard let (results, _) = try? await db.records(matching: query, resultsLimit: 400) else { return [] }
        var days: [String: Set<Int>] = [:]
        var last: [String: Date] = [:]
        for record in results.compactMap({ try? $0.1.get() }) where writer(of: record) == memberID {
            guard let crewID = record["crewID"] as? String, let day = record["dayNumber"] as? Int else { continue }
            days[crewID, default: []].insert(day)
            let when = record.modificationDate ?? .distantPast
            last[crewID] = max(last[crewID] ?? .distantPast, when)
        }
        guard !days.isEmpty,
              let found = try? await db.records(for: days.keys.map { CKRecord.ID(recordName: $0) }) else { return [] }
        return found.compactMap { recordID, result in
            guard let record = try? result.get(), let length = record["days"] as? Int, length > 0,
                  (days[recordID.recordName]?.count ?? 0) >= length else { return nil }
            let crewID = recordID.recordName
            return TimelineItem(id: "finished.\(crewID)", date: last[crewID] ?? .distantPast,
                                content: .finished(crewID: crewID, title: record["title"] as? String ?? "A challenge"))
        }
    }

    // MARK: Banner

    /// Sets your banner: filtered like any photo, then the old one is deleted.
    func setBanner(_ image: UIImage, senderName: String) async -> Bool {
        await connect()
        guard let myID else { return false }
        if await ContentFilter.isSensitive(image) { return false }
        let old = await bannerRecords(myID).map(\.recordID)
        guard await postPhotoID(image, crewID: Self.bannerBoard(myID), senderName: senderName) != nil else { return false }
        if !old.isEmpty { _ = try? await db.modifyRecords(saving: [], deleting: old) }
        return true
    }

    func removeMyBanner() async -> Bool {
        await connect()
        guard let myID else { return false }
        let old = await bannerRecords(myID).map(\.recordID)
        guard !old.isEmpty else { return true }
        do {
            _ = try await db.modifyRecords(saving: [], deleting: old)
            return true
        } catch {
            status = "Couldn't remove your banner: \(error.localizedDescription)"
            return false
        }
    }

    /// Someone's banner as you're allowed to see it: theirs, newest, not removed, reported or filtered.
    func banner(of memberID: String) async -> (photo: CrewPhoto, image: UIImage)? {
        guard !Blocklist.ids.contains(memberID) else { return nil }
        let board = Self.bannerBoard(memberID)
        var removed: Set<String> = []
        let removals = CKQuery(recordType: "PhotoRemoval", predicate: NSPredicate(format: "crewID == %@", board))
        if let (results, _) = try? await db.records(matching: removals) {
            for record in results.compactMap({ try? $0.1.get() }) where isModerator(writer(of: record), leaderID: nil) {
                if let id = record["photoID"] as? String { removed.insert(id) }
            }
        }
        let newest = await bannerRecords(memberID)
            .filter { !removed.contains($0.recordID.recordName) && !Blocklist.hiddenPhotos.contains($0.recordID.recordName) }
            .max { ($0["takenAt"] as? Date ?? .distantPast) < ($1["takenAt"] as? Date ?? .distantPast) }
        guard let newest, let url = (newest["image"] as? CKAsset)?.fileURL,
              let data = try? Data(contentsOf: url), let image = UIImage(data: data),
              await !ContentFilter.isSensitive(image) else { return nil }
        let photo = CrewPhoto(id: newest.recordID.recordName, crewID: board, senderID: memberID,
                              senderName: newest["senderName"] as? String ?? "Crew member",
                              takenAt: newest["takenAt"] as? Date ?? .now, thumb: nil)
        return (photo, image)
    }

    /// Banner records CloudKit says this member wrote.
    private func bannerRecords(_ memberID: String) async -> [CKRecord] {
        let query = CKQuery(recordType: "CrewPhoto", predicate: NSPredicate(format: "crewID == %@", Self.bannerBoard(memberID)))
        guard let (results, _) = try? await db.records(matching: query, resultsLimit: 20) else { return [] }
        return results.compactMap { try? $0.1.get() }.filter { writer(of: $0) == memberID }
    }

    /// A post's photo, full size.
    func timelinePhoto(_ id: String) async -> UIImage? {
        guard !Blocklist.hiddenPhotos.contains(id), let image = await fullPhoto(id), await !ContentFilter.isSensitive(image) else { return nil }
        return image
    }
}

// MARK: - The top of a profile

/// The banner across the top with the round photo over its lower edge.
struct ProfileHeader: View {
    let memberID: String
    let photo: UIImage?
    let banner: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let banner {
                    Image(uiImage: banner).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color.secondary.opacity(0.15))
                }
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .clipped()
            .accessibilityHidden(true)
            ProfilePhoto(image: photo, size: 120, seed: memberID)
                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 4))
                .padding(.top, -60)
        }
    }
}

// MARK: - The timeline on a profile

struct TimelineSection: View {
    let memberID: String
    let name: String

    @AppStorage(CrewSettings.name) private var myName = ""
    @State private var items: [TimelineItem] = []
    @State private var loaded = false
    @State private var composing = false
    @State private var removing: CrewMessage?
    @State private var viewingPhoto: String?
    @State private var failed = false

    private var isMine: Bool { memberID == CrewCloud.shared.myID }

    var body: some View {
        Section {
            if isMine {
                if CrewCloud.shared.can(.post) {
                    Button { composing = true } label: {
                        Label("New Post", systemImage: "square.and.pencil").font(AppFont.bodyBold)
                    }
                } else {
                    Text("Your access level doesn't include posting yet. The head coach can raise it.").font(AppFont.body)
                }
            }
            if !loaded {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Loading…").font(AppFont.body)
                }
            } else if items.isEmpty {
                Text(isMine ? "Nothing here yet. Your posts and finished challenges show here." : "Nothing here yet.")
                    .font(AppFont.body)
            }
            ForEach(items) { item in
                row(item)
            }
            if failed {
                Text("That didn't go through. Check iCloud in Settings and try again.").font(AppFont.body)
            }
        } header: {
            Text("Timeline").font(AppFont.bodyBold).textCase(nil)
        }
        .task(id: memberID) { await load() }
        .sheet(isPresented: $composing) {
            TimelineComposer { details, photo in
                let me = myName.trimmingCharacters(in: .whitespaces)
                let sent = await CrewCloud.shared.postToTimeline(details, photo: photo, senderName: me.isEmpty ? "A crew member" : me)
                if sent { await load() }
                return sent
            }
        }
        .sheet(item: Binding(get: { viewingPhoto.map(PhotoRef.init) }, set: { viewingPhoto = $0?.id })) { ref in
            TimelinePhotoViewer(photoID: ref.id)
        }
        .confirmationDialog(isMine ? "Delete this post?" : "Remove this post for everyone?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { message in
            Button(isMine ? "Delete Post" : "Remove Post", role: .destructive) {
                Task {
                    failed = !(await CrewCloud.shared.removeMessage(message))
                    // Your own post's photo goes with it.
                    if !failed, isMine, let photoID = (try? JSONDecoder().decode(TimelinePostDetails.self, from: Data(message.text.utf8)))?.photoID {
                        _ = await CrewCloud.shared.removePhoto(CrewPhoto(id: photoID, crewID: message.crewID, senderID: memberID,
                                                                         senderName: name, takenAt: .now, thumb: nil))
                    }
                    await load()
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: TimelineItem) -> some View {
        switch item.content {
        case .finished(_, let title):
            VStack(alignment: .leading, spacing: 4) {
                Label("Finished \(title)", systemImage: "flag.checkered").font(AppFont.bodyBold)
                Text(item.date.formatted(date: .abbreviated, time: .omitted)).font(AppFont.body).foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        case .post(let message, let details):
            VStack(alignment: .leading, spacing: 10) {
                if !details.text.isEmpty { Text(details.text).font(AppFont.body) }
                if let photoID = details.photoID {
                    TimelinePhotoThumb(photoID: photoID) { viewingPhoto = photoID }
                }
                if let link = details.youtube, let id = YouTubeLink.videoID(link) {
                    YouTubeCard(videoID: id)
                }
                Text(item.date.formatted(date: .abbreviated, time: .shortened)).font(AppFont.body).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .contextMenu {
                if isMine || GodMode.isOn {
                    Button(role: .destructive) { removing = message } label: {
                        Label(isMine ? "Delete Post" : "Remove Post", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func load() async {
        items = await CrewCloud.shared.timeline(of: memberID)
        loaded = true
    }
}

struct PhotoRef: Identifiable { let id: String }

/// A post's photo, loaded on its own so the timeline shows before the pictures arrive.
struct TimelinePhotoThumb: View {
    let photoID: String
    let open: () -> Void
    @State private var image: UIImage?

    var body: some View {
        Button(action: open) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .background(Color.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Photo")
        .task(id: photoID) { image = await CrewCloud.shared.timelinePhoto(photoID) }
    }
}

struct TimelinePhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let photoID: String
    @State private var image: UIImage?
    @State private var note: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    ProgressView()
                }
                if let note { Text(note).font(AppFont.body) }
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
                        guard let image else { return }
                        Task {
                            note = await CrewCloud.saveToLibrary(image)
                                ? "Saved to Photos."
                                : "It wasn't saved. Allow Rep Crew to add photos in the iPhone Settings app."
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.down").font(AppFont.bodyBold)
                    }
                    .disabled(image == nil)
                    .accessibilityLabel("Save to Photos")
                }
            }
            .task { image = await CrewCloud.shared.timelinePhoto(photoID) }
        }
    }
}

// MARK: - New post

private struct TimelineComposer: View {
    @Environment(\.dismiss) private var dismiss
    let post: (TimelinePostDetails, UIImage?) async -> Bool

    @State private var text = ""
    @State private var link = ""
    @State private var photo: UIImage?
    @State private var picked: PhotosPickerItem?
    @State private var sending = false
    @State private var failed = false

    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedLink: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var linkIsBad: Bool { !trimmedLink.isEmpty && YouTubeLink.videoID(trimmedLink) == nil }
    private var canPost: Bool { !sending && !linkIsBad && (!trimmedText.isEmpty || !trimmedLink.isEmpty || photo != nil) }
    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What's new?", text: $text, axis: .vertical)
                        .font(AppFont.body)
                        .lineLimit(3...8)
                }
                Section {
                    TextField("YouTube link", text: $link)
                        .font(AppFont.body)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let id = YouTubeLink.videoID(trimmedLink) {
                        YouTubeCard(videoID: id)
                    }
                } header: {
                    Text("Video").font(AppFont.bodyBold).textCase(nil)
                } footer: {
                    Text(linkIsBad ? "That isn't a YouTube video link." : "Paste a YouTube link. It plays when someone presses play.")
                        .font(AppFont.body)
                }
                if CrewCloud.shared.can(.photos) {
                    Section {
                        if let photo {
                            Image(uiImage: photo).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
                            Button(role: .destructive) { self.photo = nil } label: {
                                Label("Remove Photo", systemImage: "trash").font(AppFont.bodyBold)
                            }
                        } else {
                            // One button per row (two buttons in one row both fire; PhotoBoard.swift).
                            if cameraAvailable {
                                Button { CameraPresenter.shared.present { photo = $0 } } label: {
                                    Label("Take Photo", systemImage: "camera.fill").font(AppFont.bodyBold)
                                }
                            }
                            PhotosPicker(selection: $picked, matching: .images) {
                                Label("Choose Photo", systemImage: "photo.on.rectangle").font(AppFont.bodyBold)
                            }
                        }
                    } header: {
                        Text("Photo").font(AppFont.bodyBold).textCase(nil)
                    }
                }
                if failed {
                    Section {
                        Text("It didn't post. The photo may not be allowed, or iCloud didn't answer. Try again.").font(AppFont.body)
                    }
                }
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.font(AppFont.body)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        sending = true
                        failed = false
                        let details = TimelinePostDetails(text: trimmedText, youtube: trimmedLink.isEmpty ? nil : trimmedLink)
                        Task {
                            if await post(details, photo) { dismiss() } else { failed = true }
                            sending = false
                        }
                    }
                    .font(AppFont.bodyBold)
                    .disabled(!canPost)
                }
            }
            .onChange(of: picked) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) { photo = UIImage(data: data) }
                    picked = nil
                }
            }
        }
    }
}

// MARK: - YouTube

/// The video's still with a play button. Nothing loads from YouTube's player until play is pressed.
struct YouTubeCard: View {
    let videoID: String
    @State private var playing = false

    var body: some View {
        Group {
            if playing {
                YouTubePlayer(videoID: videoID)
            } else {
                Button { playing = true } label: {
                    ZStack {
                        AsyncImage(url: YouTubeLink.thumbnail(videoID)) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.secondary.opacity(0.15)
                        }
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play video")
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// YouTube's embedded player. Anything that would open outside the player (the YouTube logo, a channel,
/// "Watch on YouTube") asks before it leaves Rep Crew.
private struct YouTubePlayer: UIViewRepresentable {
    let videoID: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []   // they already pressed play
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.scrollView.isScrollEnabled = false
        view.isOpaque = false
        view.backgroundColor = .black
        // REM: YouTube's embed wants to know which app it's in (a Referer); the page's address is the app's
        // bundle ID as an https origin. Untested on a device as of 2026-10-29.
        let origin = "https://\(Bundle.main.bundleIdentifier ?? "com.accountability.dailyrepcrew")"
        context.coordinator.home = URL(string: origin)
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;background:#000}iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style>
        </head><body>
        <iframe src="https://www.youtube.com/embed/\(videoID)?autoplay=1&playsinline=1&rel=0&origin=\(origin)"
          allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen
          referrerpolicy="strict-origin-when-cross-origin"></iframe>
        </body></html>
        """
        view.loadHTMLString(html, baseURL: context.coordinator.home)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var home: URL?

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            // The player itself loads inside its frame; only the page's own address loads in the main frame.
            if action.targetFrame?.isMainFrame == false { return .allow }
            if let url = action.request.url, url.host == home?.host || url.scheme == "about" { return .allow }
            if let url = action.request.url { await askToLeave(url) }
            return .cancel
        }

        /// A link meant for a new window (target=_blank).
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url { Task { await askToLeave(url) } }
            return nil
        }

        /// James's safeguard: nothing leaves Rep Crew without asking.
        /// REM: his word, 2026-10-29: "ask once and save as a rule". The first answer is kept (OutsideLinks)
        /// and used from then on; Settings → Links Outside Rep Crew changes it.
        @MainActor private func askToLeave(_ url: URL) {
            switch OutsideLinks.rule {
            case .open: UIApplication.shared.open(url); return
            case .never: return
            case .ask: break
            }
            guard let top = CameraPresenter.topScreen() else { return }
            let alert = UIAlertController(title: "Leave Rep Crew?",
                                          message: "This opens YouTube outside the app. Rep Crew remembers your answer; change it in Settings.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Don't Open", style: .cancel) { _ in OutsideLinks.rule = .never })
            alert.addAction(UIAlertAction(title: "Open", style: .default) { _ in
                OutsideLinks.rule = .open
                UIApplication.shared.open(url)
            })
            top.present(alert, animated: true)
        }
    }
}
