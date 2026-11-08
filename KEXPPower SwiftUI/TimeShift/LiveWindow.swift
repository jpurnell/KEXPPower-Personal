//
//  LiveWindow.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// The arithmetic behind the live stream's player controls: how much of the last few minutes is held, where the listener is
/// in it, how far behind live that is, and where a skip or a scrub should land.
///
/// Times are on the player's own clock (the seconds `AVPlayer` reports for the local stream), kept apart from the time of
/// day. There is no player in this type, so it is tested without one, as `ArchiveTransport` is.
struct LiveWindow: Equatable, Sendable {
    /// Where a skip or scrub lands.
    enum Target: Equatable, Sendable {
        /// At this time on the player's clock, inside the window.
        case within(TimeInterval)
        /// At the newest audio: the listener is live again.
        case live
    }

    /// The stream is played about three seconds late even at its newest, so "live" has to allow for that.
    static let liveSlack: TimeInterval = 10
    private static let defaultRewind: TimeInterval = 300

    /// The oldest audio held.
    let start: TimeInterval
    /// The newest audio held.
    let end: TimeInterval
    /// Where the listener is, held to the window.
    let position: TimeInterval
    private let wallClockLag: TimeInterval?

    /// - Parameters:
    ///   - start: The oldest audio held, on the player's clock.
    ///   - end: The newest.
    ///   - position: Where the player is; outside the window reads as its nearest edge.
    ///   - wallClockLag: How far behind the broadcast the audio being heard is, by the clock, if the player can say. When
    ///     the stream has broken, the window is shorter than the delay, so the clock is the true measure. A value that is
    ///     not a usable number is ignored.
    init(start: TimeInterval, end: TimeInterval, position: TimeInterval, wallClockLag: TimeInterval?) {
        self.wallClockLag = wallClockLag.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        guard start.isFinite, end.isFinite, position.isFinite, end > start else {
            self.start = 0
            self.end = 0
            self.position = 0
            return
        }
        self.start = start
        self.end = end
        if position <= start {
            self.position = start
        } else if position >= end {
            self.position = end
        } else {
            self.position = position
        }
    }

    /// How much audio is held, in seconds.
    var length: TimeInterval { end - start }

    /// Whether there is nothing held, or the numbers were not usable.
    var isEmpty: Bool { length <= 0 }

    /// How far through what is held the listener is, from 0 (the oldest) to 1 (the newest), for a scrubber.
    var fraction: Double {
        guard !isEmpty else { return 0 }
        return (position - start) / length
    }

    /// How far behind live the listener is, in seconds.
    var behindLive: TimeInterval { wallClockLag ?? (end - position) }

    /// Whether the listener is hearing what is being broadcast now, give or take the delay the stream always has.
    var isLive: Bool { behindLive < Self.liveSlack }

    /// "Live", or how far behind as a clock reading with a minus sign, such as `-4:32`.
    var behindText: String {
        isLive ? "Live" : "-" + ArchiveTiming.positionText(behindLive)
    }

    /// How far the rewind button goes back: five minutes, or the whole window if the window is shorter.
    /// - Parameter window: The window the listener chose, in seconds; a value that is not a positive number reads as five
    ///   minutes.
    static func rewindStep(forWindow window: TimeInterval) -> TimeInterval {
        guard window.isFinite, window > 0 else { return defaultRewind }
        return window < defaultRewind ? window : defaultRewind
    }

    // MARK: Moving

    /// Where a skip lands. Back stops at the oldest audio held; forward to the newest is live.
    /// - Parameter seconds: How far to skip; negative to go back. One that is not a number goes nowhere.
    func target(skipping seconds: TimeInterval) -> Target {
        guard !isEmpty else { return .live }
        guard seconds.isFinite else { return .within(position) }
        let landing = position + seconds
        if landing >= end { return .live }
        if landing <= start { return .within(start) }
        return .within(landing)
    }

    /// Where a scrubber dragged to a fraction of the window lands.
    /// - Parameter fraction: 0 for the oldest audio, 1 for the newest; a value outside that is held to it, and one that is
    ///   not a number reads as the oldest.
    func target(fraction: Double) -> Target {
        guard !isEmpty else { return .live }
        guard fraction.isFinite else { return .within(start) }
        if fraction >= 1 { return .live }
        if fraction <= 0 { return .within(start) }
        return .within(start + fraction * length)
    }
}
