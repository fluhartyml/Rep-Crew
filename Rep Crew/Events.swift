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
import SwiftUI

/// What the board shows, saved as JSON in the message text.
struct CrewEventDetails: Codable, Equatable {
    var title: String
    var startsAt: Date
    var endsAt: Date
    var location = ""
    var notes = ""
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
            VStack(alignment: .leading, spacing: 4) {
                Text(event.details.title).font(AppFont.bodyBold)
                Text(event.whenText).font(AppFont.body)
                Text(event.details.location.isEmpty ? "Posted by \(event.message.senderName)"
                                                    : "\(event.details.location) · \(event.message.senderName)")
                    .font(AppFont.body).foregroundStyle(.secondary)
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
        if await CrewCloud.shared.postEvent(trimmed, senderName: me.isEmpty ? "A crew member" : me) {
            dismiss()
        } else {
            failed = true
        }
        posting = false
    }
}
