//
//  RepReminders.swift
//  Rep Crew
//
//  Reminders of the reps you still have to go today. His word, 2026-10-29: "should it do reminders or
//  notifications of reps you still have left … the notification should be set by the user on how much
//  it naggs the user" → "yes code it".
//
//  REM: these are local notifications this phone schedules for itself; nothing goes through iCloud and
//  nobody else sees them. Each one names what's left at the moment it was scheduled, so every time your
//  reps change (or the app comes back to the front) the whole set is thrown away and scheduled again.
//  Once today's goals are met, today's reminders are gone; tomorrow's stay.
//  iOS holds at most 64 pending local notifications, so only today and the next two days are scheduled.
//

import SwiftUI
import UserNotifications

enum RepReminders {
    /// How often you get nagged. Off by default: nothing pings you until you choose it.
    enum Frequency: String, CaseIterable, Identifiable {
        case off, daily, fewHours, hourly

        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: "Off"
            case .daily: "Once a day"
            case .fewHours: "Every 3 hours"
            case .hourly: "Every hour until done"
            }
        }

        /// Hours between reminders inside your window; nil when off.
        var spacing: Int? {
            switch self {
            case .off: nil
            case .daily: 24
            case .fewHours: 3
            case .hourly: 1
            }
        }
    }

    static let frequencyKey = "repReminderFrequency"
    /// The hours reminders may come, 0–23: from the start of `fromKey` through the start of `untilKey`.
    static let fromKey = "repReminderFrom"
    static let untilKey = "repReminderUntil"
    static let defaultFrom = 9
    static let defaultUntil = 20

    private static let prefix = "rep-reminder-"
    private static let daysAhead = 3

    static var frequency: Frequency {
        Frequency(rawValue: UserDefaults.standard.string(forKey: frequencyKey) ?? "") ?? .off
    }

    static var window: (from: Int, until: Int) {
        let defaults = UserDefaults.standard
        let from = defaults.object(forKey: fromKey) as? Int ?? defaultFrom
        let until = defaults.object(forKey: untilKey) as? Int ?? defaultUntil
        return (from, max(from, until))
    }

    /// The hours of the day a reminder fires, in your window.
    static func hours(for frequency: Frequency) -> [Int] {
        guard let spacing = frequency.spacing else { return [] }
        let (from, until) = window
        return Array(stride(from: from, through: until, by: spacing))
    }

    /// "100 push-ups and 2 miles of walking to go today." Nil when nothing is left on `date`.
    @MainActor
    static func message(for challenges: [Challenge], on date: Date) -> String? {
        let today = Calendar.current.isDateInToday(date)
        let left = challenges
            .filter { !$0.isClosed && $0.dayNumber(on: date) != nil && $0.isScheduled(on: date) }
            .flatMap(\.sortedGoals)
            .compactMap { goal -> String? in
                // Today counts what's logged; a later day starts from the whole goal.
                if today && goal.isMet(on: date) { return nil }
                let count = today ? goal.remaining(on: date) : goal.dailyTarget
                return count > 0 ? goal.unit.goalText(count, name: goal.name) : nil
            }
        guard !left.isEmpty else { return nil }
        // Tomorrow's text can't know what you'll log, so it says what the day asks of you.
        return ListFormatter.localizedString(byJoining: left) + (today ? " to go today." : " to do today.")
    }

    /// Throws away every rep reminder and schedules them again from what's left now.
    @MainActor
    static func reschedule(_ challenges: [Challenge]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        let hours = hours(for: frequency)
        guard !hours.isEmpty else { return }
        let cal = Calendar.current
        let now = Date.now
        for offset in 0..<daysAhead {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)),
                  let body = message(for: challenges, on: day) else { continue }
            for hour in hours {
                guard let fire = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day), fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Reps to go"
                content.body = body
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)
                try? await center.add(UNNotificationRequest(identifier: "\(prefix)\(offset)-\(hour)", content: content, trigger: trigger))
            }
        }
    }
}

/// Settings → Notifications → Reminders.
struct RepRemindersSection: View {
    let challenges: [Challenge]
    @AppStorage(RepReminders.frequencyKey) private var frequency = RepReminders.Frequency.off.rawValue
    @AppStorage(RepReminders.fromKey) private var from = RepReminders.defaultFrom
    @AppStorage(RepReminders.untilKey) private var until = RepReminders.defaultUntil

    var body: some View {
        Section {
            Picker(selection: $frequency) {
                ForEach(RepReminders.Frequency.allCases) { Text($0.title).font(AppFont.body).tag($0.rawValue) }
            } label: {
                Text("Remind me").font(AppFont.body)
            }
            if frequency != RepReminders.Frequency.off.rawValue {
                hourPicker("From", selection: $from, range: 0...23)
                hourPicker("Until", selection: $until, range: from...23)
            }
        } header: {
            Text("Reps to go").font(AppFont.bodyBold).textCase(nil)
        } footer: {
            Text("A reminder of what's left today. They stop once today's goals are met.").font(AppFont.body)
        }
        .task(id: "\(frequency).\(from).\(until)") {
            if until < from { until = from }
            if frequency != RepReminders.Frequency.off.rawValue { await CrewNotifications.requestPermission() }
            await RepReminders.reschedule(challenges)
        }
    }

    private func hourPicker(_ title: String, selection: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Picker(selection: selection) {
            ForEach(Array(range), id: \.self) { hour in
                Text(Self.hourText(hour)).font(AppFont.body).tag(hour)
            }
        } label: {
            Text(title).font(AppFont.body)
        }
    }

    /// "9 AM", in the phone's own clock style.
    static func hourText(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}
