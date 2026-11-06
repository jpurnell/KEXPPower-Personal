//
//  ReviewView.swift
//  KEXPPowerExampleSwiftUI
//

import StationKit
import SwiftUI

/// The songs waiting to be checked: each shows what KEXP played and the Apple Music version it might be, with both
/// covers so the right version can be picked out on sight, and lets the listener hear the Apple Music one.
struct ReviewView: View {
    let model: ResultRetriever

    @Environment(SongSavingModel.self) private var saving
    @State private var preview: ReviewPreviewModel

    init(model: ResultRetriever) {
        self.model = model
        _preview = State(initialValue: ReviewPreviewModel(
            audio: AVPreviewAudio(),
            previewURL: { await MusicKitPreviews.url(forSongID: $0) },
            pauseStream: { await AppModelRegistry.setPlayback(false) }))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let queue = saving.reviewQueue, !queue.entries.isEmpty {
                    List(queue.entries) { entry in
                        ReviewRow(entry: entry, queue: queue, preview: preview)
                    }
                    .listStyle(.plain)
                } else {
                    ContentUnavailableView(
                        "Nothing to review", systemImage: "tray",
                        description: Text("Songs the app is not sure about wait here until you check them."))
                }
            }
            .navigationTitle("Review")
            .onDisappear { preview.stop() }
        }
    }
}

private struct ReviewRow: View {
    let entry: ReviewEntry
    let queue: ReviewQueue
    let preview: ReviewPreviewModel

    @Environment(SongSavingModel.self) private var saving

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                cover(entry.playedArtworkFile, caption: "KEXP played")
                cover(entry.candidateArtworkFile, caption: "Apple Music")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.playedTitle).font(.headline)
                Text(entry.playedArtist).font(.subheadline)
                Text(suggestion).font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(entry.playedTitle) by \(entry.playedArtist). Apple Music suggests \(suggestion)")
            HStack {
                Button(previewLabel, systemImage: previewSymbol) { Task { await preview.toggle(entry.candidateID) } }
                    .disabled(preview.state(for: entry.candidateID) == .unavailable)
                Spacer()
                Button("Not this one", role: .destructive) {
                    saving.releaseHeld(entry)
                    queue.reject(entry)
                }
                Button("Add") { Task { await queue.add(entry) { await saving.confirmHeld($0) } } }
                    .buttonStyle(.borderedProminent)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 6)
    }

    private var suggestion: String {
        [entry.candidateTitle, entry.candidateAlbum].compactMap { $0 }.joined(separator: " — ")
    }

    private var previewLabel: String {
        switch preview.state(for: entry.candidateID) {
        case .idle: "Play"
        case .playing: "Stop"
        case .unavailable: "No preview"
        }
    }

    private var previewSymbol: String {
        preview.state(for: entry.candidateID) == .playing ? "stop.fill" : "play.fill"
    }

    private func cover(_ file: String?, caption: String) -> some View {
        VStack(spacing: 4) {
            Group {
                if let url = queue.artworkFileURL(file) {
                    AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { Color.secondary.opacity(0.2) }
                } else {
                    Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.secondary.opacity(0.1))
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
