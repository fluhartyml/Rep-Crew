//
//  RepCrew_DeveloperNotes.swift
//  Rep Crew
//
//  Developer Notes — Persistent Memory for AI Assistants
//  Created: 2026 OCT 22 (Claude Code)
//

// ============================================================================
// MARK: - PROJECT IDENTITY
// ============================================================================
//
//  Name:           Rep Crew
//  Subtitle:       Daily Accountability (App Store subtitle, 20 of 30 characters)
//  Bundle ID:      com.nightgard.RepCrew
//  Platform:       iOS — iPhone only to start
//  Version:        1.0
//  Deployment:     iOS 17.0+ (his ask: "as low as we can to start. but not too low" —
//                  17 is the floor for SwiftData and @Observable)
//  Language:       Swift 5.0, SwiftUI, SwiftData
//  App Store ID:   (not submitted — name not yet reserved in App Store Connect)
//  Location:       /Users/michaelfluharty/Developer.complex/Rep Crew/
//  Built with:     Xcode 27.1 (27A9275)

// ============================================================================
// MARK: - WHAT IT IS
// ============================================================================
//
//  A bodyweight-workout challenge app for a group of friends. The idea came from a
//  friend of Michael's on FaceTime, 2026-10-22: one person sends a challenge like
//  "100 push-ups and 100 air squats a day for 14 days", the others accept, everyone
//  logs reps through the day and counts down what's left, and the crew gets told
//  when someone completes the day. Aimed at people preparing for military fitness
//  tests and at any group of friends keeping each other accountable.
//  Mentioned for later: strength log, ring goals, 2-mile run, chat.

// ============================================================================
// MARK: - ROADMAP
// ============================================================================
//
//  1. ✅ Solo challenges on one iPhone — create a challenge (days, start date, daily
//        goal per exercise), log reps (+1/+5/+10/other, undo), see what's left today,
//        day-by-day record, About with build number.
//  2. ⬜ Friends — invite, accept, see each other's progress (iCloud).
//  3. ⬜ "Completed today" notifications to the crew.
//  4. ⬜ Later ideas from the call: strength log, rings, 2-mile run, chat.

// ============================================================================
// MARK: - HOUSE RULES THAT APPLY HERE
// ============================================================================
//
//  • 18 pt minimum text — use AppFont, never .caption/.footnote/.body.
//  • Build number = git commit count, via Scripts/post-commit. Run
//    Scripts/install-hooks.sh on every clone. Never hand-stamp.
//  • No placeholders or dead buttons — every control does something real.
//  • Every setting persists across launches (@AppStorage), never plain @State.
