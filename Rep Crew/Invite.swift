//
//  Invite.swift
//  Rep Crew
//
//  An invitation travels as a text or email. It carries the sender's TestFlight link, so
//  whoever joins can invite the next person without asking for it (Michael's "hot potato").
//  It can also carry a challenge, which the friend gets on their own phone when they join.
//
//  The join link is repcrew://join?d=<base64url JSON>. No server is involved.
//

import Foundation

struct Invite: Codable, Equatable, Identifiable {
    var id: String { url?.absoluteString ?? from }
    var from: String
    var crewNumber: Int
    var testFlight: String
    var challenge: ChallengeInfo?
    /// The sender's iCloud ID, so joining can tell the sender's phone (nil if iCloud wasn't ready).
    var fromID: String?

    struct ChallengeInfo: Codable, Equatable {
        var crewID: String
        var title: String
        var startDay: String   // yyyy-MM-dd, the sender's calendar day
        var days: Int
        var goals: [Goal]
    }

    struct Goal: Codable, Equatable {
        var name: String
        var target: Int
        /// ExerciseUnit's raw value. Missing on invites made before units, which read as reps.
        var unit: String? = nil
    }

    static let scheme = "repcrew"

    // MARK: Link

    var url: URL? {
        guard let json = try? JSONEncoder().encode(self) else { return nil }
        var parts = URLComponents()
        parts.scheme = Self.scheme
        parts.host = "join"
        parts.queryItems = [URLQueryItem(name: "d", value: json.base64URLEncoded)]
        return parts.url
    }

    init(from: String, crewNumber: Int, testFlight: String, challenge: ChallengeInfo?, fromID: String? = nil) {
        self.from = from
        self.crewNumber = crewNumber
        self.testFlight = testFlight
        self.challenge = challenge
        self.fromID = fromID
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme, url.host == "join",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "d" })?.value,
              let data = Data(base64URLEncoded: value),
              let invite = try? JSONDecoder().decode(Invite.self, from: data) else { return nil }
        self = invite
    }

    // MARK: Message

    /// The text the share sheet sends: what the challenge is, then install, then join.
    /// REM: shakedown bug 2 (2026-10-23), "the words aren't blue". Messages never makes a repcrew://
    /// link tappable, so step 2 is done inside the app instead (his "yes do B"). Public challenges
    /// show under Other challenges with Ask to Join; a private one has no way in from the text.
    func message(isPublic: Bool) -> String {
        var lines: [String] = []
        if let challenge {
            let goals = challenge.goals.map { $0.exerciseUnit.goalText($0.target, name: $0.name) }.joined(separator: " and ")
            lines.append("\(from) challenged you on Rep Crew: \(challenge.title). \(goals) a day for \(challenge.days) days, starting \(Self.displayDay(challenge.startDay)).")
        } else {
            lines.append("\(from) invited you to join their crew on Rep Crew.")
        }
        lines.append("")
        lines.append("1. Install Rep Crew with TestFlight: \(testFlight)")
        if let challenge, isPublic {
            lines.append("2. Open Rep Crew, find \(challenge.title) under Other challenges, and tap Ask to Join.")
        } else {
            lines.append("2. Open Rep Crew and sign in.")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Days

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayString(_ date: Date) -> String { dayFormat.string(from: date) }
    static func date(fromDay day: String) -> Date? { dayFormat.date(from: day) }

    private static func displayDay(_ day: String) -> String {
        guard let date = date(fromDay: day) else { return day }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    /// A TestFlight public link looks like https://testflight.apple.com/join/XXXXXXXX
    /// Rep Crew's own public TestFlight link, used whenever Settings has none — so sharing
    /// always carries a working join link. Matches fluharty.me/support/repcrew.
    static let builtInTestFlight = "https://testflight.apple.com/join/twgbfqUS"

    /// The link from Settings if it's a real TestFlight link, else the built-in one.
    static func testFlightLink(_ setting: String) -> String {
        let trimmed = setting.trimmingCharacters(in: .whitespaces)
        return isTestFlightLink(trimmed) ? trimmed : builtInTestFlight
    }

    static func isTestFlightLink(_ text: String) -> Bool {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespaces)) else { return false }
        return url.scheme == "https" && url.host == "testflight.apple.com" && url.path.hasPrefix("/join/")
    }
}

extension Invite.ChallengeInfo {
    init(_ challenge: Challenge) {
        self.init(crewID: challenge.crewID,
                  title: challenge.title,
                  startDay: Invite.dayString(challenge.startDate),
                  days: challenge.days,
                  goals: challenge.sortedGoals.map { Invite.Goal(name: $0.name, target: $0.dailyTarget, unit: $0.unit == .reps ? nil : $0.unit.rawValue) })
    }
}

/// Keys for the settings every crew member keeps.
enum CrewSettings {
    static let name = "yourName"
    static let testFlight = "testFlightLink"
    static let crewNumber = "crewNumber"
    static let hasJoined = "hasJoinedACrew"
    /// Crew IDs of challenges you declined, newline-separated, so they aren't offered again.
    static let declined = "declinedCrewIDs"
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded text: String) {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
