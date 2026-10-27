//
//  RepCrewTVApp.swift
//  Rep Crew TV
//
//  The Apple TV board: read-only, for a room's screen. His design, 2026-10-27 — see TVBoardView.swift and
//  the APPLE TV BOARD section of Rep Crew/RepCrew_DeveloperNotes.swift.
//
//  REM: "signed in then it is" — the board is whoever is signed in to the Apple TV. The User Management
//  entitlement (Runs as Current User, RepCrewTV.entitlements) makes iCloud follow the Apple TV's current
//  user, so switching users in Control Center switches whose board this is.
//

import SwiftUI

@main
struct RepCrewTVApp: App {
    var body: some Scene {
        WindowGroup {
            TVBoardView()
        }
    }
}
