//
//  NowPlayingSummary.swift
//  KEXPPowerExampleSwiftUI
//

import KEXPPower

/// The two lines that identify what is on the air: used by the mini player, and later by the widget's small size.
struct NowPlayingSummary: Equatable {
    /// Shown when the station is between songs.
    static let airbreakTitle = "Airbreak"
    /// Shown as the artist when the broadcast names none.
    static let stationName = "KEXP"

    let title: String
    let artist: String

    /// - Parameter play: What is on the air; `nil` before the first play has loaded.
    init(_ play: Play?) {
        title = Self.trimmed(play?.song) ?? Self.airbreakTitle
        artist = Self.trimmed(play?.artist) ?? Self.stationName
    }

    /// The text without surrounding whitespace, or `nil` if nothing is left.
    private static func trimmed(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
