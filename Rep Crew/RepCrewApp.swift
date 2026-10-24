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
enum AppFont {
    static let body = Font.system(size: 18)
    static let bodyBold = Font.system(size: 18, weight: .semibold)
    static let heading = Font.system(size: 22, weight: .semibold)
    static let title = Font.system(size: 28, weight: .bold)
    static let bigNumber = Font.system(size: 34, weight: .bold, design: .rounded)
}
