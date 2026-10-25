//
//  PhoneLink.swift
//  Rep Crew Watch
//
//  The iPhone sends today's goals (application context); the Watch sends back each finished
//  set (transferUserInfo, which is queued and delivered even if the iPhone app is closed).
//  Keys match WatchBridge.swift on the iPhone.
//

import Foundation
import Observation
import WatchConnectivity

struct WatchGoal: Identifiable, Hashable {
    let id: String
    let challenge: String
    let name: String
    let done: Int
    let target: Int
    /// "reps", "steps", "minutes", "miles" or "laps" (the iPhone's ExerciseUnit), and stored counts per unit:
    /// miles travel in tenths, so 25 is 2.5 miles. An older iPhone build sends neither: reps.
    var unit: String = "reps"
    var scale: Int = 1

    /// "2.5", "4,200".
    func amount(_ count: Int) -> String {
        scale > 1 ? (Double(count) / Double(scale)).formatted(.number.precision(.fractionLength(0...1))) : count.formatted()
    }
}

@MainActor @Observable
final class PhoneLink: NSObject, WCSessionDelegate {
    static let shared = PhoneLink()

    private(set) var goals: [WatchGoal] = []

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Sends one set's reps to the iPhone.
    func send(goalID: String, reps: Int, at date: Date) {
        WCSession.default.transferUserInfo(["goalID": goalID, "reps": reps, "at": date.timeIntervalSince1970])
    }

    private func load(_ context: [String: Any]) {
        let list = context["goals"] as? [[String: Any]] ?? []
        goals = list.compactMap { item in
            guard let id = item["id"] as? String, let name = item["name"] as? String else { return nil }
            return WatchGoal(id: id, challenge: item["challenge"] as? String ?? "", name: name,
                             done: item["done"] as? Int ?? 0, target: item["target"] as? Int ?? 0,
                             unit: item["unit"] as? String ?? "reps", scale: max(item["scale"] as? Int ?? 1, 1))
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in self.load(context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor in self.load(context) }
    }
}
