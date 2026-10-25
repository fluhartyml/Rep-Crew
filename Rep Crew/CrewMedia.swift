//
//  CrewMedia.swift
//  Rep Crew
//
//  Crew Media: built-in pictures anyone can use wherever the app picks a picture. His idea,
//  2026-10-25: "i want to have many images so the crew members can select any of them to use as media
//  anywhere in the app even if they want to use one as an avatar". He makes them in Image Playground
//  and names each file with "a unique name that could be used as a caption".
//
//  REM: the pictures are PNGs in the "Crew Media" folder, copied byte for byte from his Desktop folder
//  "Crew App Media". The file name is the caption: "Open Water Swim.png" shows as "Open Water Swim".
//  REM: the list below names every file. A new picture goes in the folder AND in `names`, so a missing
//  file is caught by `all` skipping it instead of a blank tile.
//  REM: a picked picture is handed back as a UIImage, so it goes down the same road as a photo: your
//  profile photo, the challenge photo board, an event. His word: "they can also upload their own from
//  camera roll incase they have an event poster" — Choose Photo stays next to it everywhere.
//

import SwiftUI
import UIKit

struct CrewMediaItem: Identifiable, Hashable {
    let name: String
    var id: String { name }

    var image: UIImage? {
        let url = Bundle.main.url(forResource: name, withExtension: "png")
            ?? Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Crew Media")
        return url.flatMap { UIImage(contentsOfFile: $0.path(percentEncoded: false)) }
    }
}

enum CrewMedia {
    /// Alphabetical, the same order as his folder in Finder.
    private static let names = [
        "Bathroom Challenge", "Dumbbells", "Exercise", "Female", "Jumping Jacks", "Kettlebells",
        "Male", "Male 2", "Open Water Swim", "Pull Ups", "Running", "Running Man", "Weight Lifting",
    ]

    static let all: [CrewMediaItem] = names.map(CrewMediaItem.init(name:)).filter { $0.image != nil }

    static func item(named name: String?) -> CrewMediaItem? {
        guard let name else { return nil }
        return all.first { $0.name == name }
    }
}

/// "Choose from Media" — one row, like Take Photo and Choose Photo (two buttons in one List row both fire).
struct ChooseFromMediaButton: View {
    let onPick: (CrewMediaItem, UIImage) -> Void
    @State private var choosing = false

    var body: some View {
        Button { choosing = true } label: {
            Label("Choose from Media", systemImage: "square.grid.2x2.fill").font(AppFont.bodyBold)
        }
        .sheet(isPresented: $choosing) {
            CrewMediaPicker { item, image in
                choosing = false
                onPick(item, image)
            }
        }
    }
}

/// The gallery: every picture with its caption under it. Tap one to use it.
struct CrewMediaPicker: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (CrewMediaItem, UIImage) -> Void

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(CrewMedia.all) { item in
                        Button {
                            if let image = item.image { onPick(item, image) }
                        } label: {
                            VStack(spacing: 8) {
                                if let image = item.image {
                                    Image(uiImage: image).resizable().scaledToFit()
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                Text(item.name).font(AppFont.body).multilineTextAlignment(.center)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.name)
                    }
                }
                .padding()
            }
            .navigationTitle("Crew Media")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.font(AppFont.bodyBold)
                }
            }
        }
    }
}
