//
//  PermissionSetup.swift
//  Rep Crew
//
//  One screen, once, between the application and Home: what Notifications and Health are for,
//  each with its own Allow button that brings up Apple's pop-up, and a check mark once it's on.
//
//  REM: his yes, 2026-11-06 (amber sheet line 001.10, "yes build the rep crew setup screen"). From
//  his screenshots of another fitness app (IMG_0775): "why Health, why Motion, why photos, each with
//  a check mark once granted, before Apple's pop-up appears." Rep Crew uses no Motion, so it's two rows.
//  REM: why these two and not Camera, Photos or Contacts (line 001.5): those are already asked the
//  moment you tap Take Photo, Save to Photos or Save to Contacts, which is when the reason is plain.
//  REM: why Notifications moved here (line 001.2): Home used to raise Apple's pop-up on the first
//  visit, while it was still syncing, before a single message had come in. A "no" then meant crew
//  messages, welcome letters and reminders never reached the lock screen, and nothing said why.
//  REM: Health reading can't get a check mark (line 001.4). Apple tells an app whether it may SAVE to
//  Health, never whether it may READ: for privacy, a "no" just looks like no data. So the row checks
//  saving and says so plainly about reading, rather than show a check mark that might be false.
//

import HealthKit
import SwiftUI
import UserNotifications

extension CrewSettings {
    /// The setup screen was finished on this phone (Continue tapped). It never shows again after that.
    static let permissionSetupDone = "permissionSetupDone"
}

struct PermissionSetupView: View {
    @AppStorage(CrewSettings.permissionSetupDone) private var done = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var notifications: UNAuthorizationStatus = .notDetermined
    @State private var healthSaving: HKAuthorizationStatus = .notDetermined
    @State private var asking = false

    private var healthHere: Bool { HKHealthStore.isHealthDataAvailable() }
    /// "iPad" on an iPad (the Mediaworks iPad catch, build 243: "It says 'on this iPhone' i am on an ipad").
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Before you start").font(AppFont.title)
                    .accessibilityAddTraits(.isHeader)
                Text("Rep Crew asks for two things. Here's what each one is for. You can change either one later in Settings.")
                    .font(AppFont.body)

                row(icon: "bell.badge.fill",
                    title: "Notifications",
                    why: "Crew messages, welcome letters and your rep reminders show up on your lock screen.",
                    state: notificationState,
                    allow: "Allow Notifications",
                    action: askNotifications)

                if healthHere {
                    row(icon: "heart.fill",
                        title: "Apple Health",
                        why: "Saves each set as a workout, and reads your workouts, steps, distance, heart rate and water to check off your challenges. It stays on this \(device) unless you choose to share it with your crew.",
                        state: healthState,
                        allow: "Allow Health",
                        action: askHealth)
                    if healthSaving != .notDetermined {
                        Text("Apple doesn't tell any app whether it may read your Health data, to protect your privacy. If your workouts don't show up, open the Health app, tap your picture, then Apps, then Rep Crew.")
                            .font(AppFont.body).foregroundStyle(.secondary)
                    }
                }

                Button { done = true } label: {
                    Text("Continue").font(AppFont.bodyBold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
            .padding(24)
        }
        .disabled(asking)
        // Back from Settings or Health: show what changed there.
        .task(id: scenePhase) { if scenePhase == .active { await refresh() } }
    }

    // MARK: Rows

    private enum RowState {
        case notAsked
        case on(String)
        case off(String)
    }

    private var notificationState: RowState {
        switch notifications {
        case .notDetermined: .notAsked
        case .denied: .off("Off. Turn it on in Settings, Notifications, Rep Crew.")
        default: .on("On")
        }
    }

    private var healthState: RowState {
        switch healthSaving {
        case .notDetermined: .notAsked
        case .sharingAuthorized: .on("Saving your sets is on")
        default: .off("Saving your sets is off. Turn it on in the Health app, your picture, Apps, Rep Crew.")
        }
    }

    @ViewBuilder
    private func row(icon: String, title: String, why: String, state: RowState, allow: String,
                     action: @escaping () async -> Void) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon).font(AppFont.heading).foregroundStyle(.tint).frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(AppFont.heading)
                Text(why).font(AppFont.body)
                switch state {
                case .notAsked:
                    Button { Task { asking = true; await action(); await refresh(); asking = false } } label: {
                        Text(allow).font(AppFont.bodyBold)
                    }
                    .buttonStyle(.bordered)
                    .tint(ButtonGreen.text) // REM: contrast fix 11-06, see ButtonGreen
                case .on(let words):
                    Label(words, systemImage: "checkmark.circle.fill")
                        .font(AppFont.bodyBold).foregroundStyle(.green)
                case .off(let words):
                    Label(words, systemImage: "xmark.circle.fill")
                        .font(AppFont.body).foregroundStyle(.secondary)
                    if title == "Notifications", let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        Button { openURL(url) } label: { Text("Open Settings").font(AppFont.bodyBold) }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }

    // MARK: Asking

    private func askNotifications() async {
        await CrewNotifications.requestPermission()
    }

    private func askHealth() async {
        // The same one question SetTimer and the Health list ask, so Apple shows it once, not twice.
        try? await HealthSets.store.requestAuthorization(toShare: HealthSets.shareTypes, read: HealthSets.readTypes)
    }

    private func refresh() async {
        notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if healthHere { healthSaving = HealthSets.store.authorizationStatus(for: HKObjectType.workoutType()) }
    }
}

// MARK: - Settings: take a permission back (amber 002.2)

/// One Access row in Settings: whether the permission is on, and a button that works in every state.
/// REM: his rule 2026-11-06, line 002.2, every app: "in settings you should always be able to change your mind
/// REM: and take back a permission." Not asked yet → Apple's pop-up. Answered → Apple lets no app flip its own
/// REM: permission, so the button opens the place you flip it: Settings → Notifications → Rep Crew, or the Health app.
/// REM: Health READING has no on/off an app can see (line 001.4), so the Health row reports saving only, and says so.
struct PermissionAccessRow: View {
    enum Kind { case notifications, health }
    let kind: Kind

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var notifications: UNAuthorizationStatus = .notDetermined
    @State private var healthSaving: HKAuthorizationStatus = .notDetermined
    @State private var asking = false

    private var notAsked: Bool {
        kind == .notifications ? notifications == .notDetermined : healthSaving == .notDetermined
    }
    private var isOn: Bool {
        switch kind {
        case .notifications: notifications == .authorized || notifications == .provisional || notifications == .ephemeral
        case .health: healthSaving == .sharingAuthorized
        }
    }
    private var words: String {
        switch kind {
        case .notifications:
            notAsked ? "Not asked yet" : isOn ? "Notifications are on" : "Notifications are off"
        case .health:
            notAsked ? "Not asked yet" : isOn ? "Saving your sets is on" : "Saving your sets is off"
        }
    }
    private var buttonTitle: String { kind == .notifications ? "Access Notifications" : "Access Health" }
    private var footnote: String {
        switch kind {
        case .notifications:
            notAsked ? "Tap Access Notifications and Apple asks whether Rep Crew may notify you."
                     : "Tap Access Notifications to change it in the Settings app, under Notifications, Rep Crew."
        case .health:
            notAsked ? "Tap Access Health and Apple asks what Rep Crew may save and read."
                     : "Tap Access Health to open the Health app, then tap your picture, Apps, Rep Crew. Apple never tells an app whether it may read your Health data."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(words, systemImage: isOn ? "checkmark.circle.fill" : notAsked ? "questionmark.circle" : "xmark.circle.fill")
                .font(AppFont.bodyBold)
                .foregroundStyle(isOn ? Color.green : Color.secondary)
                .accessibilityIdentifier(kind == .notifications ? "notificationsStatus" : "healthStatus")
            Button { Task { await tap() } } label: {
                Text(buttonTitle).font(AppFont.bodyBold)
            }
            .buttonStyle(.bordered)
            .tint(ButtonGreen.text) // REM: contrast fix 11-06, see ButtonGreen
            .disabled(asking)
            .accessibilityIdentifier(kind == .notifications ? "accessNotifications" : "accessHealth")
            Text(footnote).font(AppFont.body).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        // Back from Settings or Health: show what changed there.
        .task(id: scenePhase) { if scenePhase == .active { await refresh() } }
    }

    private func tap() async {
        if notAsked {
            asking = true
            switch kind {
            case .notifications: await CrewNotifications.requestPermission()
            case .health: try? await HealthSets.store.requestAuthorization(toShare: HealthSets.shareTypes, read: HealthSets.readTypes)
            }
            await refresh()
            asking = false
            return
        }
        let address = kind == .notifications ? UIApplication.openNotificationSettingsURLString : "x-apple-health://"
        if let url = URL(string: address) { openURL(url) }
    }

    private func refresh() async {
        notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if HKHealthStore.isHealthDataAvailable() {
            healthSaving = HealthSets.store.authorizationStatus(for: HKObjectType.workoutType())
        }
    }
}
