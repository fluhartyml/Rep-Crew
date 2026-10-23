//
//  RepCrewWatchApp.swift
//  Rep Crew Watch
//
//  "Start Set" on the wrist. His plan, 2026-10-22 ~20:00: the Watch runs a real strength
//  workout, so Watch measures time and calories, the set lands in Health, and the rings move
//  on their own — "we would never say 'close your rings' or any trade marks". Reps go back to
//  the iPhone, which keeps every challenge. Nothing is invented: time and calories come from
//  the Watch's own workout, reps from what you enter.
//

import SwiftUI

@main
struct RepCrewWatchApp: App {
    var body: some Scene {
        WindowGroup {
            GoalListView()
        }
    }
}

/// Watch text sizes. The 18 pt floor is an iPhone rule; on the Watch, system sizes keep text
/// legible on a 41–49 mm screen, and nothing here is smaller than the system body size.
enum WatchFont {
    static let body = Font.body
    static let bodyBold = Font.body.weight(.semibold)
    static let bigNumber = Font.system(size: 40, weight: .bold, design: .rounded)
}
