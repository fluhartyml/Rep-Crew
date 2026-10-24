//
//  BuildStamp.swift
//  Rep Crew
//
//  ⚠️ THE VALUES BELOW ARE REWRITTEN BY `Scripts/stamp-build.sh`. Do not hand-edit them.
//
//  Every build that reaches a device names its commit: the build number is the git commit
//  count, and Scripts/post-commit restamps it after every commit. Install the hook with
//  Scripts/install-hooks.sh — git never copies hooks on clone.

import Foundation

enum BuildStamp {
    /// Short SHA of HEAD when this build was stamped. "+" suffix = uncommitted changes.
    static let commit = "942e74e"

    /// Branch HEAD was on when this build was stamped.
    static let branch = "main"

    /// Local time the stamp was generated — effectively the build time.
    static let built = "2026-10-24 08:05"

    /// True when this binary was never stamped.
    static var isStamped: Bool { commit != "unstamped" }

    /// The build number — `CURRENT_PROJECT_VERSION`, which is the git commit count.
    /// Read from the bundle so there is only one source for it.
    static var number: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }
}
