//
//  Events.swift
//  Rep Crew
//
//  The Events board. His idea, 2026-10-24: "events could be something to where if a crew member had an
//  event going in the future they could list it like on a grocery store bulletin board and interested
//  crew members could put in their apple calendars". Built at his word 2026-10-25: "i just want all of
//  my ideas i have told you coded in the app".
//
//  REM: an event is a CrewMessage (kind .event) on the board crewID "events", its details as JSON in the
//  text. The crewID index every phone already queries by finds them, so no new iCloud record type or index.
//  Builds before this never ask for crewID "events", so they never see one.
//  REM: Add to Calendar uses Apple's own event editor (EventKitUI). It runs outside the app, so Rep Crew
//  never asks for calendar access and never reads your calendar; you choose the calendar and tap Add.
//  REM: posting needs the same ability as crew messages (Access → Post crew messages). Your own event:
//  delete it. Someone else's: coaches and he can remove it (a MessageRemoval, as for messages).
//

import EventKit
import EventKitUI
import PhotosUI
import SwiftUI

/// What the board shows, saved as JSON in the message text.
struct CrewEventDetails: Codable, Equatable {
    var title: String
    var startsAt: Date
    var endsAt: Date
    var location = ""
    var notes = ""
    /// REM: his word, 2026-10-25: crew media "anywhere in the app", and "they can also upload their own
    /// from camera roll incase they have an event poster". One or the other: a Crew Media name, or the
    /// ID of a CrewPhoto posted on the events board. Optional, so events posted before decode unchanged
    /// and builds before this ignore both.
    var media: String? = nil
    var posterID: String? = nil
}

struct CrewEvent: Identifiable {
    let message: CrewMessage
    let details: CrewEventDetails

    var id: String { message.id }
    var isPast: Bool { details.endsAt < .now }

    /// "Sat, Nov 7 · 9:00 – 11:00 AM", or both dates when it runs past one day.
    var whenText: String {
        let start = details.startsAt, end = details.endsAt
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) + " · "
                + (start..<max(end, start)).formatted(.interval.hour().minute())
        }
        return start.formatted(date: .abbreviated, time: .shortened) + " – " + end.formatted(date: .abbreviated, time: .shortened)
    }
}

extension CrewCloud {
    static let eventsBoard = "events"

    /// Every event on the board, soonest first.
    func events() async -> [CrewEvent] {
        await boardMessages(crewID: Self.eventsBoard)
            .filter { $0.kind == .event }
            .compactMap { message in
                guard let details = try? JSONDecoder().decode(CrewEventDetails.self, from: Data(message.text.utf8)) else { return nil }
                return CrewEvent(message: message, details: details)
            }
            .sorted { $0.details.startsAt < $1.details.startsAt }
    }

    func postEvent(_ details: CrewEventDetails, senderName: String) async -> Bool {
        guard let data = try? JSONEncoder().encode(details), let text = String(data: data, encoding: .utf8) else { return false }
        return await send(text, crewID: Self.eventsBoard, kind: .event, senderName: senderName)
    }
}

// MARK: - The board

struct EventsView: View {
    private var cloud = CrewCloud.shared
    @State private var events: [CrewEvent] = []
    @State private var loaded = false
    @State private var posting = false

    var body: some View {
        List {
            let upcoming = events.filter { !$0.isPast }
            let past = events.filter(\.isPast).reversed().prefix(20)
            Section {
                if !loaded {
                    ProgressView()
                } else if upcoming.isEmpty {
                    Text(cloud.can(.post) ? "Nothing on the board yet. Tap + to post an event." : "Nothing on the board yet.")
                        .font(AppFont.body)
                }
                ForEach(upcoming) { event in row(event) }
            } header: {
                Text("Coming up").font(AppFont.bodyBold).textCase(nil)
            } footer: {
                Text("Post a meetup, a race or a class for the crew. Anyone interested can add it to their calendar.")
                    .font(AppFont.body)
            }
            if !past.isEmpty {
                Section {
                    ForEach(Array(past)) { event in row(event) }
                } header: {
                    Text("Past").font(AppFont.bodyBold).textCase(nil)
                }
            }
        }
        .navigationTitle("Events")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if cloud.can(.post) {
                    Button { posting = true } label: {
                        Image(systemName: "plus.circle.fill").font(AppFont.heading)
                    }
                    .accessibilityLabel("Post an event")
                }
            }
        }
        .sheet(isPresented: $posting, onDismiss: { Task { await load() } }) { PostEventView() }
        .refreshable { await load() }
        .task { await load() }
    }

    private func row(_ event: CrewEvent) -> some View {
        NavigationLink {
            EventDetailView(event: event) { Task { await load() } }
        } label: {
            HStack(spacing: 12) {
                if event.details.media != nil || event.details.posterID != nil {
                    EventPicture(details: event.details)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.details.title).font(AppFont.bodyBold)
                    Text(event.whenText).font(AppFont.body)
                    Text(event.details.location.isEmpty ? "Posted by \(event.message.senderName)"
                                                        : "\(event.details.location) · \(event.message.senderName)")
                        .font(AppFont.body).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func load() async {
        events = await cloud.events()
        loaded = true
    }
}

// MARK: - One event

private struct EventDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let event: CrewEvent
    let onRemove: () -> Void
    @State private var addingToCalendar = false
    @State private var note: String?
    @State private var confirmingRemove = false

    private var isMine: Bool { event.message.senderID == CrewCloud.shared.myID }

    var body: some View {
        List {
            if event.details.media != nil || event.details.posterID != nil {
                Section {
                    EventPicture(details: event.details, fit: true)
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets())
                }
            }
            Section {
                Text(event.details.title).font(AppFont.title).fixedSize(horizontal: false, vertical: true)
                Label(event.whenText, systemImage: "calendar").font(AppFont.body)
                if !event.details.location.isEmpty {
                    Label(event.details.location, systemImage: "mappin.and.ellipse").font(AppFont.body)
                }
                Text("Posted by \(isMine ? "you" : event.message.senderName)").font(AppFont.body).foregroundStyle(.secondary)
            }
            if !event.details.notes.isEmpty {
                Section {
                    Text(event.details.notes).font(AppFont.body).textSelection(.enabled)
                } header: {
                    Text("Details").font(AppFont.bodyBold).textCase(nil)
                }
            }
            if !event.isPast {
                Section {
                    Button { addingToCalendar = true } label: {
                        Label("Add to Calendar", systemImage: "calendar.badge.plus").font(AppFont.bodyBold)
                    }
                    if let note { Text(note).font(AppFont.body) }
                } footer: {
                    Text("You pick the calendar and can change anything before you add it.").font(AppFont.body)
                }
            }
            if isMine || GodMode.isOn {
                Section {
                    Button(role: .destructive) { confirmingRemove = true } label: {
                        Label(isMine ? "Delete Event" : "Remove Event", systemImage: "trash").font(AppFont.bodyBold)
                    }
                }
            }
        }
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $addingToCalendar) {
            CalendarEventEditor(details: event.details) { added in
                addingToCalendar = false
                if added { note = "Added to your calendar." }
            }
            .ignoresSafeArea()
        }
        .confirmationDialog(isMine ? "Delete this event?" : "Remove this event for everyone?", isPresented: $confirmingRemove,
                            titleVisibility: .visible) {
            Button(isMine ? "Delete Event" : "Remove Event", role: .destructive) {
                Task {
                    if await CrewCloud.shared.removeMessage(event.message) {
                        // Your own poster goes with your event. Removing someone else's event hides
                        // the event, and the poster only ever shows on it.
                        if isMine, let posterID = event.details.posterID, let myID = CrewCloud.shared.myID {
                            _ = await CrewCloud.shared.removePhoto(CrewPhoto(id: posterID, crewID: CrewCloud.eventsBoard, senderID: myID,
                                                                             senderName: "", takenAt: .now, thumb: nil))
                        }
                        onRemove()
                        dismiss()
                    } else {
                        note = "That didn't go through. Check Settings → iCloud and try again."
                    }
                }
            }
        }
    }
}

/// An event's picture: its Crew Media, or its poster from iCloud. A poster the on-device filter flags
/// stays off the screen, as on the photo board.
private struct EventPicture: View {
    let details: CrewEventDetails
    var fit = false
    @State private var poster: UIImage?

    var body: some View {
        Group {
            if let image = CrewMedia.item(named: details.media)?.image ?? poster {
                if fit {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            } else {
                Image(systemName: "photo").font(AppFont.heading).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: fit ? 200 : 64)
                    .background(Color.secondary.opacity(0.15))
            }
        }
        .accessibilityHidden(true)
        .task(id: details.posterID) {
            guard details.media == nil, let id = details.posterID,
                  let image = await CrewCloud.shared.fullPhoto(id), !(await ContentFilter.isSensitive(image)) else { return }
            poster = image
        }
    }
}

/// Apple's own Add Event screen, filled in. It runs outside the app, so it needs no calendar access.
private struct CalendarEventEditor: UIViewControllerRepresentable {
    let details: CrewEventDetails
    let finished: (Bool) -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = details.title
        event.startDate = details.startsAt
        event.endDate = details.endsAt
        event.location = details.location.isEmpty ? nil : details.location
        event.notes = details.notes.isEmpty ? nil : details.notes
        let editor = EKEventEditViewController()
        editor.eventStore = store
        editor.event = event
        editor.editViewDelegate = context.coordinator
        return editor
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(finished: finished) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let finished: (Bool) -> Void
        init(finished: @escaping (Bool) -> Void) { self.finished = finished }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            finished(action == .saved)
        }
    }
}

// MARK: - Post an event

private struct PostEventView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CrewSettings.name) private var myName = ""
    @State private var details = CrewEventDetails(title: "", startsAt: PostEventView.nextHour, endsAt: PostEventView.nextHour.addingTimeInterval(3600))
    @State private var posting = false
    @State private var failed = false
    /// Your own picture (camera or camera roll), uploaded as the poster when you tap Post.
    @State private var poster: UIImage?
    @State private var picked: PhotosPickerItem?
    @State private var pictureNote: String?

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    private static var nextHour: Date {
        let cal = Calendar.current
        let start = cal.date(bySetting: .minute, value: 0, of: .now) ?? .now
        return cal.date(byAdding: .hour, value: 1, to: start) ?? .now
    }

    private var canPost: Bool { !details.title.trimmingCharacters(in: .whitespaces).isEmpty && details.endsAt > details.startsAt }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What, like Saturday Beach Run", text: $details.title).font(AppFont.body)
                    TextField("Where", text: $details.location).font(AppFont.body)
                }
                Section {
                    DatePicker("Starts", selection: $details.startsAt, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                        .font(AppFont.body)
                    DatePicker("Ends", selection: $details.endsAt, in: details.startsAt..., displayedComponents: [.date, .hourAndMinute])
                        .font(AppFont.body)
                }
                .onChange(of: details.startsAt) { old, new in
                    // Keep the same length when the start moves.
                    details.endsAt = new.addingTimeInterval(max(details.endsAt.timeIntervalSince(old), 900))
                }
                Section {
                    TextField("Details, like what to bring", text: $details.notes, axis: .vertical)
                        .font(AppFont.body)
                        .lineLimit(3...8)
                } footer: {
                    Text("Everyone in Rep Crew can see this event and add it to their calendar.").font(AppFont.body)
                }
                Section {
                    if let image = CrewMedia.item(named: details.media)?.image ?? poster {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityHidden(true)
                    }
                    // One button per row (two buttons in one List row both fire).
                    ChooseFromMediaButton { item, _ in
                        details.media = item.name
                        poster = nil
                        pictureNote = nil
                    }
                    PhotosPicker(selection: $picked, matching: .images) {
                        Label("Choose Photo", systemImage: "photo.on.rectangle").font(AppFont.bodyBold)
                    }
                    if cameraAvailable {
                        Button { CameraPresenter.shared.present { image in usePoster(image) } } label: {
                            Label("Take Photo", systemImage: "camera.fill").font(AppFont.bodyBold)
                        }
                    }
                    if details.media != nil || poster != nil {
                        Button(role: .destructive) {
                            details.media = nil
                            poster = nil
                        } label: {
                            Label("Remove Picture", systemImage: "trash").font(AppFont.bodyBold)
                        }
                    }
                    if let pictureNote { Text(pictureNote).font(AppFont.body) }
                } header: {
                    Text("Picture").font(AppFont.bodyBold).textCase(nil)
                } footer: {
                    Text("Optional. Pick one from Crew Media, or add your own, like the event's poster.").font(AppFont.body)
                }
                .onChange(of: picked) { _, item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                            usePoster(image)
                        }
                        picked = nil
                    }
                }
                if failed {
                    Text("That didn't go through. Check Settings → iCloud and try again.").font(AppFont.body)
                }
            }
            .navigationTitle("Post an Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.font(AppFont.bodyBold)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") { Task { await post() } }
                        .font(AppFont.bodyBold)
                        .disabled(!canPost || posting)
                }
            }
        }
    }

    private func post() async {
        posting = true
        var trimmed = details
        trimmed.title = details.title.trimmingCharacters(in: .whitespacesAndNewlines)
        trimmed.location = details.location.trimmingCharacters(in: .whitespacesAndNewlines)
        trimmed.notes = details.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let me = myName.trimmingCharacters(in: .whitespaces)
        if let poster {
            if await ContentFilter.isSensitive(poster) {
                pictureNote = "This picture can't be shared with the crew."
                posting = false
                return
            }
            guard let id = await CrewCloud.shared.postPhotoID(poster, crewID: CrewCloud.eventsBoard,
                                                               senderName: me.isEmpty ? "A crew member" : me) else {
                failed = true
                posting = false
                return
            }
            trimmed.posterID = id
            trimmed.media = nil
        }
        if await CrewCloud.shared.postEvent(trimmed, senderName: me.isEmpty ? "A crew member" : me) {
            dismiss()
        } else {
            failed = true
        }
        posting = false
    }

    private func usePoster(_ image: UIImage) {
        poster = image
        details.media = nil
        pictureNote = nil
    }
}
