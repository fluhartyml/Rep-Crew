//
//  RepCrewApp.swift
//  Rep Crew
//

import SwiftUI
import SwiftData

@main
struct RepCrewApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Challenge.self, ExerciseGoal.self, RepEntry.self, CrewMember.self])
    }
}

/// Text sizes. 18 pt is the floor for every piece of text in the app.
enum AppFont {
    static let body = Font.system(size: 18)
    static let bodyBold = Font.system(size: 18, weight: .semibold)
    static let heading = Font.system(size: 22, weight: .semibold)
    static let title = Font.system(size: 28, weight: .bold)
    static let bigNumber = Font.system(size: 34, weight: .bold, design: .rounded)
}
