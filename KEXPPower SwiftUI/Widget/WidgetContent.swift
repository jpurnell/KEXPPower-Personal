//
//  WidgetContent.swift
//  KEXPPowerExampleSwiftUI
//

import CoreGraphics
import Foundation
import ImageIO
import StationKit
import SwiftUI

/// What one widget entry shows: the snapshot, its artwork already shrunk, and the playback state.
struct NowPlayingWidgetContent: Equatable, Sendable {
    var snapshot: WidgetSnapshot
    /// Artwork as JPEG data scaled for a widget, or `nil` to show a placeholder.
    var artwork: Data?
    var isPlaying: Bool
    /// Whether the snapshot is old enough that the widget should say when it is from.
    var isStale: Bool

    /// When the song aired, else when the snapshot was made.
    var time: Date { snapshot.airDate ?? snapshot.fetchedAt }

    /// A line like "Last played 3:36 PM".
    var timeLine: String {
        let formatted = time.formatted(date: .omitted, time: .shortened)
        return snapshot.isSong ? "Last played \(formatted)" : "As of \(formatted)"
    }

    /// Release date and label on one line, either may be missing.
    var releaseLine: String {
        [snapshot.releaseDate, snapshot.labels.first].compactMap { $0 }.joined(separator: " · ")
    }

    /// Sample content for placeholders and previews.
    static let sample = NowPlayingWidgetContent(
        snapshot: WidgetSnapshot(
            nowPlaying: .track(Track(
                id: "sample", title: "Sugar", credits: [Credit(role: .performer, name: "NoSo")],
                album: "When Are You Leaving?", airDate: Date(timeIntervalSince1970: 1_730_000_000),
                comment: "A cover of the Maroon 5 song, recorded at KEXP on a Tuesday afternoon, with the whole band in the room.",
                labels: ["Partisan Records"], releaseDate: "2025-10-10")),
            program: ProgramInfo(title: "The Midday Show", host: "Cheryl Waters"),
            stationName: "KEXP", fallbackArtworkURL: nil, fetchedAt: Date(timeIntervalSince1970: 1_730_000_000)),
        artwork: nil, isPlaying: false, isStale: false)
}

/// Artwork from encoded data, or a neutral placeholder.
struct WidgetArtwork: View {
    let data: Data?

    var body: some View {
        if let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            // The artwork is decoration: the title and artist beside it carry the meaning for VoiceOver.
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .accessibilityHidden(true)
        } else {
            ZStack {
                Rectangle().fill(.quaternary)
                Image(systemName: "music.note")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
        }
    }
}
