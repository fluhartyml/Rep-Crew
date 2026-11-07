//
//  RepCrewApp.swift
//  Rep Crew
//

import CoreData
import SwiftUI
import SwiftData

@main
struct RepCrewApp: App {
    @UIApplicationDelegateAdaptor(CrewNotifications.self) private var notifications

    init() {
        WatchBridge.shared.start(container)
        WidgetSync.listen()   // + taps on the Home Screen widget
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
        #if DEBUG
        initializeCloudKitSchema(at: synced.url)
        #endif
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

#if DEBUG
/// Creates every CD_ record type in the Development iCloud at once, so they can all be deployed to
/// Production together. Debug builds only, once per build number.
/// REM: his "yes build it and install on the 11", 2026-10-24. SwiftData makes a type only when a record
/// of it is first saved, so a Debug run made CD_Challenge, CD_ExerciseGoal and CD_RepEntry but not
/// CD_CrewMember or CD_HealthMatch. Deploying three would leave TestFlight unable to save the other two.
/// This is Apple's documented way (NSPersistentCloudKitContainer.initializeCloudKitSchema) for SwiftData.
private func initializeCloudKitSchema(at url: URL) {
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    let doneKey = "cloudKitSchemaInitializedBuild"
    guard UserDefaults.standard.string(forKey: doneKey) != build,
          let model = NSManagedObjectModel.makeManagedObjectModel(for: [Challenge.self, ExerciseGoal.self, RepEntry.self,
                                                                         CrewMember.self, HealthMatch.self]) else { return }
    autoreleasepool {
        let description = NSPersistentStoreDescription(url: url)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.accountability.dailyrepcrew")
        description.shouldAddStoreAsynchronously = false
        let container = NSPersistentCloudKitContainer(name: "RepCrew", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loaded = true
        container.loadPersistentStores { _, error in if error != nil { loaded = false } }
        guard loaded else { return }
        do {
            try container.initializeCloudKitSchema()
            UserDefaults.standard.set(build, forKey: doneKey)
        } catch {
            print("CloudKit schema not initialized: \(error)")
        }
        if let store = container.persistentStoreCoordinator.persistentStores.first {
            try? container.persistentStoreCoordinator.remove(store)
        }
    }
}
#endif

/// Text sizes. 18 pt is the floor for every piece of text in the app.
/// REM: his rule (feedback_18pt_minimum_font, 11-04): "18 point rule is my personal assistive setting" —
/// 18 pt at the DEFAULT text size, and the person's own text-size setting wins. Until 2026-11-06 these
/// were fixed .system(size:) fonts that never scaled; the shakedown robot's accessibility audit caught it
/// ("Dynamic Type font sizes are unsupported").
/// ⚠️ Don't use Font.custom(name, size:, relativeTo:) for this: no name reaches San Francisco, so it fell
/// back to a serif (Times) — seen in the robot's screenshot 2026-11-06, and the audit never flagged it.
/// A rebuild-on-text-size-change (.id) was tried next and reset every screen to Home — removed.
enum AppFont {
    /// ".AppleSystemUIFont" is the name Core Text gives San Francisco itself, so it resolves (no serif
    /// fallback) and relativeTo: keeps it scaling live with the text size, with no rebuild.
    private static let sf = ".AppleSystemUIFont"
    static let body = Font.custom(sf, size: 18, relativeTo: .body)
    static let bodyBold = Font.custom(sf, size: 18, relativeTo: .body).weight(.semibold)
    static let heading = Font.custom(sf, size: 22, relativeTo: .title3).weight(.semibold)
    static let title = Font.custom(sf, size: 28, relativeTo: .title).weight(.bold)
    /// .largeTitle is 34 pt at the default size, so the rounded numbers keep their look and still scale.
    static let bigNumber = Font.system(.largeTitle, design: .rounded, weight: .bold)
}

/// Deeper greens for buttons that carry text, so the words pass contrast.
/// REM: the shakedown robot's audit (2026-11-06) failed Allow Notifications, Allow Health and I Agree on
/// contrast — the accent green (0.31, 0.56, 0) is too light for text on its own pale tint, and too light
/// behind white text. His word 21:1x: "yes fix the 3 buttons". The accent color itself is unchanged.
enum ButtonGreen {
    /// Behind white text (.borderedProminent): one dark green in both light and dark mode, ~6:1 with white.
    static let filled = Color(red: 0.20, green: 0.42, blue: 0.0)
    /// For green text on a pale tint (.bordered): dark green in light mode, bright green in dark mode.
    static let text = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.45, green: 0.80, blue: 0.20, alpha: 1)
            : UIColor(red: 0.20, green: 0.42, blue: 0.0, alpha: 1)
    })
}
