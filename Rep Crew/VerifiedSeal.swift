//
//  VerifiedSeal.swift
//  Rep Crew
//
//  His words, 2026-10-25: "i was thinking verified users could get a blue seal next to their name like on X not
//  twitter" · on the color: "how about drab olive green".
//
//  REM: verified = level 11 and up (Verified new user, the first range that can join and start), so the seal
//  appears for everyone the app trusts to take part, from an approval or an application with an email.
//  Apple's checkmark.seal.fill, in olive drab rather than X's blue, so it reads as Rep Crew's own badge.
//  A member's level is read once per launch and kept (CrewCloud.knownLevels), so a long list costs one read each.
//

import SwiftUI

extension Color {
    /// Olive drab, #6B8E23: dark enough to read as drab on white, light enough to see on black.
    static let oliveDrab = Color(red: 0x6B / 255, green: 0x8E / 255, blue: 0x23 / 255)
}

extension CrewCloud {
    /// Someone's level, read from iCloud the first time and kept for the rest of the launch.
    func knownLevel(of memberID: String) async -> Int {
        if memberID == myID { return effectiveLevel }
        if let level = knownLevels[memberID] { return level }
        let level = await memberAccess(memberID).level
        knownLevels[memberID] = level
        return level
    }
}

/// The olive seal after a verified member's name. Nothing while their level is unknown or below 11.
struct VerifiedSeal: View {
    let memberID: String
    var size: CGFloat = 18
    @State private var verified = false

    var body: some View {
        Group {
            if verified {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: size))
                    .foregroundStyle(Color.oliveDrab)
                    .accessibilityLabel("Verified")
            }
        }
        .task(id: memberID) {
            verified = await CrewCloud.shared.knownLevel(of: memberID) >= CrewCloud.approvedLevel
        }
    }
}
