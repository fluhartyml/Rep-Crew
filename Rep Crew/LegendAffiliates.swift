//
//  LegendAffiliates.swift
//  Rep Crew
//
//  Head Coach → Legend Affiliates: the systems on the linchpin, and putting Rep Crew on it or taking it off.
//  REM: his words, 2026-11-01: "dont we need the crew app to prove compatibility among two systems?" · "sounds good".
//  REM: head coach only for now. It's the proof that two systems meet on the network; crew members see nothing new.
//  REM: on screen it's "system", never "board" (his word, 2026-11-01: "that is 70's this is the 20's").

import SwiftUI

struct LegendAffiliatesView: View {
    @AppStorage(CrewSettings.crewName) private var crewName = ""
    @AppStorage(CrewSettings.name) private var myName = ""
    @State private var affiliates: [Linchpin.Affiliate] = []
    @State private var loaded = false
    @State private var working = false
    @State private var problem: String?

    private var myID: String? { CrewCloud.shared.myID }
    private var mySystemID: String? { myID.map(Linchpin.systemID(headCoach:)) }
    private var listed: Bool { affiliates.contains { $0.id == mySystemID } }
    private var shownName: String { CrewCloud.displayName(crewName) }

    var body: some View {
        Form {
            Section {
                Text(listed ? "\(shownName) is on the network." : "\(shownName) isn't on the network.")
                    .font(AppFont.bodyBold)
                Button {
                    Task { await toggle() }
                } label: {
                    Text(listed ? "Take This System Off the Network" : "Put This System on the Network")
                        .font(AppFont.bodyBold)
                }
                .disabled(working || !loaded || myID == nil)
                if let problem { Text(problem).font(AppFont.body).foregroundStyle(.red) }
            } header: {
                Text("This System").font(AppFont.bodyBold).textCase(nil)
            } footer: {
                Text("Every Legend system can see the Legend Affiliates list. It shows your crew's name, a line about Rep Crew and your name, nothing else. Your crew's challenges, reps and messages never go there.")
                    .font(AppFont.body)
            }

            Section {
                if !loaded {
                    ProgressView()
                } else if affiliates.isEmpty {
                    Text("No Legend Affiliates yet.").font(AppFont.body).foregroundStyle(.secondary)
                } else {
                    ForEach(affiliates) { system in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(system.name.isEmpty ? "Unnamed system" : system.name).font(AppFont.bodyBold)
                            if system.id == mySystemID {
                                Text("This system").font(AppFont.body).foregroundStyle(.secondary)
                            }
                            if !system.tagline.isEmpty { Text(system.tagline).font(AppFont.body) }
                            if !system.sysopHandle.isEmpty {
                                Text("Sysop: \(system.sysopHandle)").font(AppFont.body).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Legend Affiliates").font(AppFont.bodyBold).textCase(nil)
            }
        }
        .navigationTitle("Legend Affiliates")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        await CrewCloud.shared.connect()
        do {
            affiliates = try await Linchpin.affiliates()
            problem = nil
        } catch {
            problem = "Couldn't reach the network. Check Settings → iCloud."
        }
        loaded = true
    }

    private func toggle() async {
        guard let myID, GodMode.isOwner else { return }
        working = true
        defer { working = false }
        do {
            if listed {
                try await Linchpin.unlist(headCoach: myID)
            } else {
                let name = myName.trimmingCharacters(in: .whitespaces)
                try await Linchpin.list(headCoach: myID, name: shownName, handle: name.isEmpty ? "Head Coach" : name)
            }
            await load()
        } catch {
            problem = "Couldn't save it. Check Settings → iCloud."
        }
    }
}
