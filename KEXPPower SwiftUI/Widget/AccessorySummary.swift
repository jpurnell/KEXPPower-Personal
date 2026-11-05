//
//  AccessorySummary.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import StationKit

/// The words a watch complication shows for what is on the air, kept apart from WidgetKit so they can be tested.
///
/// Accessory widgets are small and monochrome, so they carry text and a symbol and no artwork.
struct AccessorySummary: Equatable, Sendable {
    let title: String
    let artist: String
    let isPlaying: Bool
    /// A line like "Last played 3:36 PM" ("As of" for something that is not a song); never "live".
    let timeLine: String

    /// - Parameters:
    ///   - snapshot: What is on the air; an airbreak or a song with no artist shows the station as the artist.
    ///   - isPlaying: Whether the stream is playing.
    init(_ snapshot: WidgetSnapshot, isPlaying: Bool) {
        title = snapshot.title
        artist = snapshot.artist
        self.isPlaying = isPlaying
        let formatted = (snapshot.airDate ?? snapshot.fetchedAt).formatted(date: .omitted, time: .shortened)
        timeLine = snapshot.isSong ? "Last played \(formatted)" : "As of \(formatted)"
    }

    /// Title and artist on one line, for the inline complication.
    var inlineText: String { "\(title) – \(artist)" }

    /// What a tap does: the label of the complication's button.
    var actionLabel: String { isPlaying ? "Pause KEXP" : "Play KEXP" }

    /// The symbol of that action.
    var symbolName: String { isPlaying ? "pause.fill" : "play.fill" }

    /// What VoiceOver reads for the complication.
    var accessibilityLabel: String { "\(title) by \(artist), \(isPlaying ? "playing" : "paused")" }
}
