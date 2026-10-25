//
//  WatchBridge.swift
//  Rep Crew
//
//  The iPhone side of the Watch link. Sends today's goals to the Watch (application context,
//  latest only) and logs each set the Watch sends back (transferUserInfo) as a RepEntry. The
//  Watch already saved that set to Health, so nothing is saved twice. Keys match
//  Rep Crew Watch/PhoneLink.swift.
//

import Foundation
import SwiftData
import WatchConnectivity

@MainActor
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    private var container: ModelContainer?

    func start(_ container: ModelContainer) {
        self.container = container
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Today's goals in running challenges. A goal's ID is its SwiftData identifier, so a set
    /// from the Watch lands on exactly that goal.
    func sendGoals(_ challenges: [Challenge]) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        let goals: [[String: Any]] = challenges.filter(\.isActive).flatMap { challenge in
            challenge.sortedGoals.compactMap { goal -> [String: Any]? in
                guard let id = Self.encode(goal.persistentModelID) else { return nil }
                return ["id": id, "challenge": challenge.title, "name": goal.name,
                        "done": goal.total(on: .now), "target": goal.dailyTarget,
                        "unit": goal.unit.rawValue, "scale": goal.unit.scale]
            }
        }
        try? WCSession.default.updateApplicationContext(["goals": goals, "sent": Date.now.timeIntervalSince1970])
    }

    private func logSet(_ info: [String: Any]) {
        guard let container, let id = (info["goalID"] as? String).flatMap(Self.decode),
              let reps = info["reps"] as? Int, reps > 0 else { return }
        let context = container.mainContext
        guard let goal = context.model(for: id) as? ExerciseGoal else { return }
        let at = (info["at"] as? TimeInterval).map(Date.init(timeIntervalSince1970:)) ?? .now
        let entry = RepEntry(count: reps, loggedAt: at)
        entry.goal = goal
        context.insert(entry)
        try? context.save()
    }

    private static func encode(_ id: PersistentIdentifier) -> String? {
        (try? JSONEncoder().encode(id)).map { $0.base64EncodedString() }
    }

    private static func decode(_ text: String) -> PersistentIdentifier? {
        Data(base64Encoded: text).flatMap { try? JSONDecoder().decode(PersistentIdentifier.self, from: $0) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let info = userInfo
        Task { @MainActor in self.logSet(info) }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
