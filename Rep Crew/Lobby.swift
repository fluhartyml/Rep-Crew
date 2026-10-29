//
//  Lobby.swift
//  Rep Crew
//
//  The Lobby's feed, filtered by fitness level. From the Smitty session recording, 2026-10-29: "how your
//  Instagram shows you stuff that you wanna see … beginner stuff if you're a beginner … harder stuff if you're
//  [intermediate] … that's where the grouping would come to play … for the public feed". His "please code the
//  feed by level". Earlier the same day: the Lobby is open to everyone with the app, posting to it is optional,
//  and it's for "progress questions answers struggles achievements solutions" · "feed acomplishments challenges
//  advice" · "its the users story to tell".
//
//  REM: no new iCloud record type: a Lobby post is a CrewMessage (kind .post) on the board crewID "lobby", its
//  details as JSON in the text (as Events and the timeline do). Only posts CloudKit says the sender wrote count.
//  Your own: delete it. Someone else's: coaches and he remove it (MessageRemoval), as on the Events board.
//  REM: the level is the one each person picks for themselves (FitnessLevel, Settings and the Lobby's top row) —
//  "the user can overide". The readiness test, when it's built, suggests it; it never sets it behind their back.
//  Nothing from Apple Health goes into a post (his rule: no Health data is shared unless the member chooses).
//

import CloudKit
import PhotosUI
import SwiftUI

/// Where a person puts themselves. Each post carries its poster's level, so the feed can match.
enum FitnessLevel: String, CaseIterable, Identifiable, Codable {
    case starter, steady, strong, elite
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var blurb: String {
        switch self {
        case .starter: "Just getting going: walks, light moves"
        case .steady: "Working out most weeks"
        case .strong: "Training hard and often"
        case .elite: "Competing or close to it"
        }
    }
}

/// What a Lobby post is about.
enum LobbyTopic: String, CaseIterable, Identifiable, Codable {
    case accomplishment, progress, question, struggle, advice, solution
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .accomplishment: "trophy.fill"
        case .progress: "chart.line.uptrend.xyaxis"
        case .question: "questionmark.bubble.fill"
        case .struggle: "figure.fall"
        case .advice: "lightbulb.fill"
        case .solution: "checkmark.bubble.fill"
        }
    }
}

struct LobbyPostDetails: Codable, Equatable {
    var topic = LobbyTopic.progress.rawValue
    var level = FitnessLevel.starter.rawValue
    var text = ""
    var youtube: String? = nil
    var photoID: String? = nil
}

struct LobbyPost: Identifiable {
    let message: CrewMessage
    let details: LobbyPostDetails
    var id: String { message.id }
    var level: FitnessLevel { FitnessLevel(rawValue: details.level) ?? .starter }
    var topic: LobbyTopic { LobbyTopic(rawValue: details.topic) ?? .progress }
}

extension CrewSettings {
    /// Your FitnessLevel raw value; unset = Starter until you pick.
    static let fitnessLevel = "fitnessLevel"
    /// The Lobby's filter: "mine" (your level, the default) or "all".
    static let lobbyFilter = "lobbyFilter"
}

// MARK: - iCloud

extension CrewCloud {
    static let lobbyBoard = "lobby"

    func postToLobby(_ details: LobbyPostDetails, photo: UIImage?, senderName: String) async -> Bool {
        await connect()
        var details = details
        if let photo {
            if await ContentFilter.isSensitive(photo) { return false }
            guard let id = await postPhotoID(photo, crewID: Self.lobbyBoard, senderName: senderName) else { return false }
            details.photoID = id
        }
        guard let json = try? JSONEncoder().encode(details), let text = String(data: json, encoding: .utf8) else { return false }
        return await send(text, crewID: Self.lobbyBoard, kind: .post, senderName: senderName)
    }

    /// Every Lobby post, newest first, minus blocked people and posts a coach removed.
    func lobbyPosts() async -> [LobbyPost] {
        await connect()
        let query = CKQuery(recordType: "CrewMessage", predicate: NSPredicate(format: "crewID == %@", Self.lobbyBoard))
        guard let (results, _) = try? await db.records(matching: query, resultsLimit: 300) else { return [] }
        let removed = await removedMessages(crewID: Self.lobbyBoard, leaderID: nil)
        return results.compactMap { try? $0.1.get() }
            .compactMap { record -> LobbyPost? in
                guard let message = Self.message(from: record), message.kind == .post, writer(of: record) == message.senderID,
                      !removed.contains(message.id), !Blocklist.ids.contains(message.senderID),
                      let details = try? JSONDecoder().decode(LobbyPostDetails.self, from: Data(message.text.utf8)) else { return nil }
                return LobbyPost(message: message, details: details)
            }
            .sorted { $0.message.sentAt > $1.message.sentAt }
    }
}

// MARK: - The Lobby

struct LobbyView: View {
    @AppStorage(CrewSettings.name) private var myName = ""
    @AppStorage(CrewSettings.fitnessLevel) private var myLevel = FitnessLevel.starter.rawValue
    @AppStorage(CrewSettings.lobbyFilter) private var filter = "mine"
    @State private var posts: [LobbyPost] = []
    @State private var loaded = false
    @State private var composing = false
    @State private var removing: CrewMessage?
    @State private var profileOf: ProfileTarget?
    @State private var viewingPhoto: String?
    @State private var failed = false

    private var level: FitnessLevel { FitnessLevel(rawValue: myLevel) ?? .starter }
    /// His recording: beginners see beginner posts; each level sees its own. "All levels" shows everything.
    private var shown: [LobbyPost] { filter == "all" ? posts : posts.filter { $0.level == level } }

    var body: some View {
        List {
            Section {
                Picker(selection: $myLevel) {
                    ForEach(FitnessLevel.allCases) { Text($0.title).font(AppFont.body).tag($0.rawValue) }
                } label: {
                    Text("Your level").font(AppFont.bodyBold)
                }
                Picker(selection: $filter) {
                    Text("\(level.title) posts").font(AppFont.body).tag("mine")
                    Text("All levels").font(AppFont.body).tag("all")
                } label: {
                    Text("Showing").font(AppFont.bodyBold)
                }
                if CrewCloud.shared.can(.post) {
                    Button { composing = true } label: {
                        Label("Share to the Lobby", systemImage: "square.and.pencil").font(AppFont.bodyBold)
                    }
                }
            } footer: {
                Text("\(level.blurb). You see posts from people at your level; pick your level to match how you train. Sharing is always your choice.")
                    .font(AppFont.body)
            }
            Section {
                if !loaded {
                    HStack(spacing: 12) { ProgressView(); Text("Loading…").font(AppFont.body) }
                } else if shown.isEmpty {
                    Text(filter == "all" ? "Nothing shared yet." : "Nothing shared at \(level.title) yet. Try All levels.").font(AppFont.body)
                }
                ForEach(shown) { post in row(post) }
                if failed { Text("That didn't go through. Check iCloud in Settings and try again.").font(AppFont.body) }
            }
        }
        .navigationTitle("Lobby")
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $composing) {
            LobbyComposer(level: level) { details, photo in
                let me = myName.trimmingCharacters(in: .whitespaces)
                let sent = await CrewCloud.shared.postToLobby(details, photo: photo, senderName: me.isEmpty ? "A crew member" : me)
                if sent { await load() }
                return sent
            }
        }
        .sheet(item: $profileOf) { ProfileView(target: $0) }
        .sheet(item: Binding(get: { viewingPhoto.map(PhotoRef.init) }, set: { viewingPhoto = $0?.id })) { TimelinePhotoViewer(photoID: $0.id) }
        .confirmationDialog("Remove this post?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { message in
            Button("Remove Post", role: .destructive) {
                Task {
                    failed = !(await CrewCloud.shared.removeMessage(message))
                    await load()
                }
            }
        }
    }

    private func row(_ post: LobbyPost) -> some View {
        let mine = post.message.senderID == CrewCloud.shared.myID
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Label(post.topic.title, systemImage: post.topic.symbol).font(AppFont.bodyBold)
                Text("· \(post.level.title)").font(AppFont.body).foregroundStyle(.secondary)
            }
            if !post.details.text.isEmpty { Text(post.details.text).font(AppFont.body) }
            if let photoID = post.details.photoID {
                TimelinePhotoThumb(photoID: photoID) { viewingPhoto = photoID }
            }
            if let link = post.details.youtube, let id = YouTubeLink.videoID(link) {
                YouTubeCard(videoID: id)
            }
            HStack(spacing: 6) {
                Text(mine ? "You" : post.message.senderName).font(AppFont.body)
                VerifiedSeal(memberID: post.message.senderID)
                Text("· \(post.message.sentAt.formatted(date: .abbreviated, time: .shortened))").font(AppFont.body).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if !mine {
                Button { profileOf = ProfileTarget(id: post.message.senderID, name: post.message.senderName) } label: {
                    Label("View Profile", systemImage: "person.crop.circle")
                }
            }
            if mine || GodMode.isOn {
                Button(role: .destructive) { removing = post.message } label: {
                    Label("Remove Post", systemImage: "trash")
                }
            }
        }
    }

    private func load() async {
        posts = await CrewCloud.shared.lobbyPosts()
        loaded = true
    }
}

// MARK: - Sharing to the Lobby

private struct LobbyComposer: View {
    @Environment(\.dismiss) private var dismiss
    let level: FitnessLevel
    let post: (LobbyPostDetails, UIImage?) async -> Bool

    @State private var topic = LobbyTopic.progress
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $topic) {
                        ForEach(LobbyTopic.allCases) { Label($0.title, systemImage: $0.symbol).font(AppFont.body).tag($0) }
                    } label: {
                        Text("About").font(AppFont.bodyBold)
                    }
                    TextField("Tell your story", text: $text, axis: .vertical).font(AppFont.body).lineLimit(3...8)
                } footer: {
                    Text("Shared with \(level.title)-level members, and anyone who views all levels.").font(AppFont.body)
                }
                Section {
                    TextField("YouTube link", text: $link)
                        .font(AppFont.body).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if let id = YouTubeLink.videoID(trimmedLink) { YouTubeCard(videoID: id) }
                    if linkIsBad { Text("That isn't a YouTube video link.").font(AppFont.body) }
                }
                if CrewCloud.shared.can(.photos) {
                    Section {
                        if let photo {
                            Image(uiImage: photo).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
                            Button(role: .destructive) { self.photo = nil } label: {
                                Label("Remove Photo", systemImage: "trash").font(AppFont.bodyBold)
                            }
                        } else {
                            PhotosPicker(selection: $picked, matching: .images) {
                                Label("Choose Photo", systemImage: "photo.on.rectangle").font(AppFont.bodyBold)
                            }
                        }
                    }
                }
                if failed {
                    Section { Text("It didn't post. The photo may not be allowed, or iCloud didn't answer. Try again.").font(AppFont.body) }
                }
            }
            .navigationTitle("Share to the Lobby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.font(AppFont.body) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share") {
                        sending = true
                        failed = false
                        let details = LobbyPostDetails(topic: topic.rawValue, level: level.rawValue, text: trimmedText,
                                                       youtube: trimmedLink.isEmpty ? nil : trimmedLink)
                        Task {
                            if await post(details, photo) { dismiss() } else { failed = true }
                            sending = false
                        }
                    }
                    .font(AppFont.bodyBold).disabled(!canPost)
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
