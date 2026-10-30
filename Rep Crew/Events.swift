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
//  REM: GET-TOGETHERS. His word, 2026-10-29: Smitty's park meetups, "not just parks because that sounds bad" ·
//  "get togethers sounds better" · "yes code it". A Get-Together is an event with kind "getTogether": a place
//  picked by searching Apple Maps (MKLocalSearch: no location permission, nothing about where you are is read),
//  shown on a map with Directions, and Going / Not Going so the crew sees who's coming.
//  REM: Going / Not Going is one CrewMessage per person per event (kind .rsvp, record "rsvp.<event>.<member>",
//  board "rsvp.<event>"), saved over each time you change it, like the points card. Only a record CloudKit says
//  its member wrote counts. Builds before 208 never ask for an rsvp board, so they never see one.
//

import CloudKit
import EventKit
import EventKitUI
import MapKit
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
    /// "getTogether" for a Get-Together; nil for any other event. Optional, so older events decode unchanged.
    var kind: String? = nil
    /// The place picked from Apple Maps, when there is one.
    var latitude: Double? = nil
    var longitude: Double? = nil

    static let getTogether = "getTogether"
    var isGetTogether: Bool { kind == Self.getTogether }
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
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

struct EventRSVP: Identifiable {
    static let going = "going"
    static let notGoing = "notGoing"
    let id: String
    let name: String
    let going: Bool
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

    // MARK: Going / Not Going

    static func rsvpBoard(_ event: CrewEvent) -> String { "rsvp.\(event.id)" }

    /// Everyone's answer for one event, minus blocked people and answers someone else wrote.
    func rsvps(for event: CrewEvent) async -> [EventRSVP] {
        await connect()
        let query = CKQuery(recordType: "CrewMessage", predicate: NSPredicate(format: "crewID == %@", Self.rsvpBoard(event)))
        guard let (results, _) = try? await db.records(matching: query, resultsLimit: CKQueryOperation.maximumResults) else { return [] }
        let blocked = Blocklist.ids
        return results.compactMap { try? $0.1.get() }.compactMap { record in
            guard let message = Self.message(from: record), message.kind == .rsvp, writer(of: record) == message.senderID,
                  !blocked.contains(message.senderID) else { return nil }
            return EventRSVP(id: message.senderID, name: message.senderName, going: message.text == EventRSVP.going)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Your answer, saved over your last one.
    func setRSVP(_ going: Bool, for event: CrewEvent, name: String) async -> Bool {
        await connect()
        guard let myID else { return false }
        let record = CKRecord(recordType: "CrewMessage", recordID: CKRecord.ID(recordName: "rsvp.\(event.id).\(myID)"))
        record["crewID"] = Self.rsvpBoard(event)
        record["text"] = going ? EventRSVP.going : EventRSVP.notGoing
        record["senderID"] = myID
        record["senderName"] = name
        record["kind"] = CrewMessage.Kind.rsvp.rawValue
        record["toID"] = CrewMessage.everyone
        record["sentAt"] = Date.now
        record["title"] = "🙋 \(name)"
        do {
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            return true
        } catch {
            status = "Couldn't save your answer: \(error.localizedDescription)"
            return false
        }
    }

    func postEvent(_ details: CrewEventDetails, senderName: String) async -> Bool {
        guard let data = try? JSONEncoder().encode(details), let text = String(data: data, encoding: .utf8) else { return false }
        return await send(text, crewID: Self.eventsBoard, kind: .event, senderName: senderName)
    }

    /// Edit Event: your own event's record gets the new details. Same record, so its place on the board stays.
    func updateEvent(_ event: CrewEvent, to details: CrewEventDetails) async -> Bool {
        await connect()
        guard event.message.senderID == myID,
              let data = try? JSONEncoder().encode(details), let text = String(data: data, encoding: .utf8) else { return false }
        do {
            let record = try await db.record(for: CKRecord.ID(recordName: event.message.id))
            record["text"] = text
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
            return true
        } catch {
            status = "Couldn't save your event: \(error.localizedDescription)"
            return false
        }
    }
}

// MARK: - The board

struct EventsView: View {
    private var cloud = CrewCloud.shared
    @State private var events: [CrewEvent] = []
    @State private var loaded = false
    @State private var posting = false
    @State private var postingGetTogether = false

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
                Text("Post a Get-Together, a race or a class for the crew. Anyone interested can add it to their calendar.")
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
                    Menu {
                        Button { postingGetTogether = true } label: {
                            Label("Get-Together", systemImage: "figure.2")
                        }
                        Button { posting = true } label: {
                            Label("Other Event", systemImage: "pin.fill")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(AppFont.heading)
                    }
                    .accessibilityLabel("Post an event")
                }
            }
        }
        .sheet(isPresented: $posting, onDismiss: { Task { await load() } }) { PostEventView() }
        .sheet(isPresented: $postingGetTogether, onDismiss: { Task { await load() } }) { PostEventView(getTogether: true) }
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
                    if event.details.isGetTogether {
                        Label("Get-Together", systemImage: "figure.2").font(AppFont.body).foregroundStyle(.tint)
                    }
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

struct EventDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let event: CrewEvent
    let onRemove: () -> Void
    @State private var addingToCalendar = false
    @State private var note: String?
    @State private var confirmingRemove = false
    @State private var editing = false
    @State private var rsvps: [EventRSVP] = []
    @State private var saving = false
    @AppStorage(CrewSettings.name) private var myName = ""

    private var isMine: Bool { event.message.senderID == CrewCloud.shared.myID }
    private var myAnswer: Bool? { rsvps.first { $0.id == CrewCloud.shared.myID }?.going }

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
            if let coordinate = event.details.coordinate {
                Section {
                    Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 800, longitudinalMeters: 800))) {
                        Marker(event.details.location.isEmpty ? event.details.title : event.details.location, coordinate: coordinate)
                    }
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())
                    .accessibilityLabel("Map of \(event.details.location)")
                    Button { openDirections(coordinate) } label: {
                        Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill").font(AppFont.bodyBold)
                    }
                }
            }
            if event.details.isGetTogether {
                rsvpSection
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
                    // REM: his word, 2026-10-25: crew leaders can "modify their events the started". Yours only.
                    if isMine {
                        Button { editing = true } label: {
                            Label("Edit Event", systemImage: "pencil").font(AppFont.bodyBold)
                        }
                    }
                    // The trash can red like the words (his word, 2026-10-25: "yes make the trash can red").
                    Button(role: .destructive) { confirmingRemove = true } label: {
                        Label {
                            Text(isMine ? "Delete Event" : "Remove Event")
                        } icon: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }
                        .font(AppFont.bodyBold)
                    }
                }
            }
        }
        .navigationTitle(event.details.isGetTogether ? "Get-Together" : "Event")
        .navigationBarTitleDisplayMode(.inline)
        .task { if event.details.isGetTogether { rsvps = await CrewCloud.shared.rsvps(for: event) } }
        // Saved changes show after the list reloads, so the page closes back to it.
        .sheet(isPresented: $editing) {
            PostEventView(editing: event) {
                onRemove()
                dismiss()
            }
        }
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

extension EventDetailView {
    /// Going / Not Going, then who's coming. One button per row (two buttons in one List row both fire).
    @ViewBuilder
    var rsvpSection: some View {
        let going = rsvps.filter(\.going)
        Section {
            if !event.isPast {
                Button { Task { await answer(true) } } label: {
                    Label("Going", systemImage: myAnswer == true ? "checkmark.circle.fill" : "circle").font(AppFont.bodyBold)
                }
                .disabled(saving)
                .accessibilityAddTraits(myAnswer == true ? .isSelected : [])
                Button { Task { await answer(false) } } label: {
                    Label("Not Going", systemImage: myAnswer == false ? "xmark.circle.fill" : "circle").font(AppFont.bodyBold)
                }
                .disabled(saving)
                .accessibilityAddTraits(myAnswer == false ? .isSelected : [])
            }
            if going.isEmpty {
                Text("No one has said they're going yet.").font(AppFont.body).foregroundStyle(.secondary)
            } else {
                ForEach(going) { person in
                    Label(person.id == CrewCloud.shared.myID ? "You" : person.name, systemImage: "person.fill").font(AppFont.body)
                }
            }
        } header: {
            Text(going.isEmpty ? "Who's coming" : "Who's coming · \(going.count)").font(AppFont.bodyBold).textCase(nil)
        } footer: {
            Text("Your answer shows to everyone who opens this Get-Together. You can change it any time.").font(AppFont.body)
        }
    }

    func answer(_ going: Bool) async {
        saving = true
        let me = myName.trimmingCharacters(in: .whitespaces)
        if await CrewCloud.shared.setRSVP(going, for: event, name: me.isEmpty ? "A crew member" : me) {
            rsvps = await CrewCloud.shared.rsvps(for: event)
        } else {
            note = "That didn't go through. Check Settings → iCloud and try again."
        }
        saving = false
    }

    func openDirections(_ coordinate: CLLocationCoordinate2D) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = event.details.location.isEmpty ? event.details.title : event.details.location
        item.openInMaps()
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
    /// Your own event to change (Edit Event), or nil to post a new one.
    var editing: CrewEvent? = nil
    /// Called after an edit saves.
    var saved: () -> Void = {}
    /// Post a Get-Together: the place comes from Apple Maps.
    var getTogether = false
    @State private var findingPlace = false
    @State private var details = CrewEventDetails(title: "", startsAt: PostEventView.nextHour, endsAt: PostEventView.nextHour.addingTimeInterval(3600))
    @State private var posting = false
    @State private var failed = false
    /// Your own picture (camera or camera roll), uploaded as the poster when you tap Post.
    @State private var poster: UIImage?
    @State private var picked: PhotosPickerItem?
    @State private var pictureNote: String?
    /// The name a picked place filled in, so typing over it can be told apart.
    @State private var pickedName = ""

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
                    TextField(details.isGetTogether ? "What, like Saturday Morning Walk" : "What, like Saturday Beach Run",
                              text: $details.title).font(AppFont.body)
                    TextField("Where", text: $details.location).font(AppFont.body)
                        .onChange(of: details.location) { _, new in
                            // Typing over a picked place unpins it, so the map never shows the wrong spot.
                            if new != pickedName { details.latitude = nil; details.longitude = nil }
                        }
                    Button { findingPlace = true } label: {
                        Label(details.coordinate == nil ? "Find the Place on the Map" : "Change the Place",
                              systemImage: "mappin.and.ellipse").font(AppFont.bodyBold)
                    }
                    if let coordinate = details.coordinate {
                        Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 800, longitudinalMeters: 800))) {
                            Marker(details.location, coordinate: coordinate)
                        }
                        .id("\(coordinate.latitude),\(coordinate.longitude)")
                        .frame(height: 180)
                        .listRowInsets(EdgeInsets())
                        .accessibilityHidden(true)
                    }
                } footer: {
                    if details.isGetTogether {
                        Text("Any spot works: a park, a green space, a trail, the beach.").font(AppFont.body)
                    }
                }
                Section {
                    DatePicker("Starts", selection: $details.startsAt, in: min(Date.now, editing?.details.startsAt ?? .now)...,
                               displayedComponents: [.date, .hourAndMinute])
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
                    } else if details.posterID != nil {
                        // The poster already on the event you're editing.
                        EventPicture(details: details, fit: true)
                            .frame(maxWidth: .infinity, maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    // One button per row (two buttons in one List row both fire).
                    ChooseFromMediaButton { item, _ in
                        details.media = item.name
                        details.posterID = nil
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
                    if details.media != nil || poster != nil || details.posterID != nil {
                        Button(role: .destructive) {
                            details.media = nil
                            details.posterID = nil
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
            .navigationTitle(editing == nil ? (details.isGetTogether ? "Post a Get-Together" : "Post an Event")
                                            : (details.isGetTogether ? "Edit Get-Together" : "Edit Event"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let editing, details.title.isEmpty {
                    details = editing.details
                    pickedName = editing.details.coordinate == nil ? "" : editing.details.location
                } else if getTogether && editing == nil {
                    details.kind = CrewEventDetails.getTogether
                }
            }
            .sheet(isPresented: $findingPlace) {
                PlaceSearchView { item in
                    let name = item.name ?? item.placemark.title ?? ""
                    pickedName = name
                    details.location = name
                    details.latitude = item.placemark.coordinate.latitude
                    details.longitude = item.placemark.coordinate.longitude
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.font(AppFont.bodyBold)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Post" : "Save") { Task { await post() } }
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
        if let editing {
            if await CrewCloud.shared.updateEvent(editing, to: trimmed) {
                // A poster you replaced or removed goes, as on Delete Event.
                if let old = editing.details.posterID, old != trimmed.posterID, let myID = CrewCloud.shared.myID {
                    _ = await CrewCloud.shared.removePhoto(CrewPhoto(id: old, crewID: CrewCloud.eventsBoard, senderID: myID,
                                                                     senderName: "", takenAt: .now, thumb: nil))
                }
                dismiss()
                saved()
            } else {
                failed = true
            }
        } else if await CrewCloud.shared.postEvent(trimmed, senderName: me.isEmpty ? "A crew member" : me) {
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

// MARK: - Find a place

/// Search Apple Maps by name or address. Nothing about where you are is read; results come from what you type.
private struct PlaceSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let picked: (MKMapItem) -> Void
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false
    @State private var searched = false

    var body: some View {
        NavigationStack {
            List {
                if searching {
                    HStack(spacing: 12) { ProgressView(); Text("Searching…").font(AppFont.body) }
                } else if searched && results.isEmpty {
                    Text("No places found. Try the name with its town or ZIP code.").font(AppFont.body)
                }
                ForEach(results, id: \.self) { item in
                    Button {
                        picked(item)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name ?? "Place").font(AppFont.bodyBold).foregroundStyle(.primary)
                            if let address = item.placemark.title {
                                Text(address).font(AppFont.body).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Park, green space, trail or address")
            .onSubmit(of: .search) { Task { await search() } }
            .navigationTitle("Find the Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.font(AppFont.bodyBold)
                }
            }
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        searching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        results = (try? await MKLocalSearch(request: request).start())?.mapItems ?? []
        searching = false
        searched = true
    }
}
