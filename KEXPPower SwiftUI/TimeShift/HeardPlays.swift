//
//  HeardPlays.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import KEXPPower

/// Which plays the listener has heard, when they are behind live: the song shown as playing should be the one in their ears,
/// not the one on the air.
enum HeardPlays {
    /// - Parameters:
    ///   - plays: The station's recent plays, newest first.
    ///   - lag: How far behind the broadcast the audio being heard is, in seconds. Within the few seconds the stream is
    ///     always late, or if it is not a usable number, the listener is live and nothing changes.
    ///   - now: The time of day.
    /// - Returns: The plays that had aired by the moment being heard, newest first. A play whose air time cannot be read is
    ///   kept, not guessed at. If lag reaches back past every play, the oldest is returned: the nearest honest answer.
    static func plays(_ plays: [Play], behind lag: TimeInterval, now: Date) -> [Play] {
        guard lag.isFinite, lag >= LiveWindow.liveSlack else { return plays }
        let heardAt = now.addingTimeInterval(-lag)
        let heard = plays.drop { play in
            guard let aired = airDate(of: play) else { return false }
            return aired > heardAt
        }
        if heard.isEmpty, let oldest = plays.last { return [oldest] }
        return Array(heard)
    }

    private static func airDate(of play: Play) -> Date? {
        guard let text = play.airdate else { return nil }
        if let date = ISO8601DateFormatter().date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}
