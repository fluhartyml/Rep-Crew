//
//  RepCrewApp.swift
//  Rep Crew
//

import SwiftUI
import SwiftData

@main
struct RepCrewApp: App {
    @UIApplicationDelegateAdaptor(CrewNotifications.self) private var notifications

    init() {
        WatchBridge.shared.start(container)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }

    /// Challenges and reps are kept in the person's own iCloud (the private database), so a
    /// deleted app or a new phone gets them back on sign-in.
    /// REM: his word 2026-10-24, "the challenges should be in the cloud … so when one phone is
    /// removed they still live on". Was `.none` (phone only) since build 12, which synced before the
    /// models were ready for it and opened empty. If iCloud can't open the store, the same file opens
    /// on the phone alone — nothing is lost, it just isn't backed up until iCloud works.
    private let container: ModelContainer = {
        let schema = Schema([Challenge.self, ExerciseGoal.self, RepEntry.self, CrewMember.self, HealthMatch.self])
        let synced = ModelConfiguration(schema: schema, cloudKitDatabase: .private("iCloud.com.accountability.dailyrepcrew"))
        if let container = try? ModelContainer(for: schema, configurations: synced) {
            UserDefaults.standard.set(false, forKey: "storeNotInICloud")
            return container
        }
        UserDefaults.standard.set(true, forKey: "storeNotInICloud")
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none))
        } catch {
            fatalError("Rep Crew couldn't open its data: \(error)")
        }
    }()
}

/// Text sizes. 18 pt is the floor for every piece of text in the app.
enum AppFont {
    static let body = Font.system(size: 18)
    static let bodyBold = Font.system(size: 18, weight: .semibold)
    static let heading = Font.system(size: 22, weight: .semibold)
    static let title = Font.system(size: 28, weight: .bold)
    static let bigNumber = Font.system(size: 34, weight: .bold, design: .rounded)
}
