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

    /// Challenges and reps stay on this phone. The app has iCloud turned on for the crew's
    /// shared space (CrewCloud), and without `.none` SwiftData would try to sync this store
    /// through iCloud too, fail, and open empty — build 12 did exactly that.
    private let container: ModelContainer = {
        let schema = Schema([Challenge.self, ExerciseGoal.self, RepEntry.self, CrewMember.self, HealthMatch.self])
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: config)
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
