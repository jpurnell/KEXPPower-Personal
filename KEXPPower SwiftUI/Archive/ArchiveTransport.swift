//
//  ArchiveTransport.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// The arithmetic behind an archived show's player controls: where in the show the listener is, and where a skip or a
/// scrub should land.
///
/// Archive files begin before their show and run past it, so the scrubber covers the show alone: from where the show
/// begins in the file to where the next show begins (or the end of the file, if that comes first). Everything here is
/// in two kinds of time, kept apart by name: *file time* is seconds into the audio file, and *show time* is seconds
/// into the show. There is no player in this type, so it is tested without one.
struct ArchiveTransport: Equatable, Sendable {
    /// Where a skip or scrub lands.
    enum Target: Equatable, Sendable {
        /// At this file time, inside the show.
        case within(TimeInterval)
        /// At or past the show's end: the player goes on to the next show, or to live.
        case end
    }

    /// File time at which the show begins.
    let lowerBound: TimeInterval
    /// File time at which the show ends.
    let upperBound: TimeInterval

    /// - Parameters:
    ///   - offset: Seconds into the file at which the show begins; a negative offset reads as the start of the file.
    ///   - showLength: How long the show runs (the next show's start minus this show's), or `nil` if unknown, in
    ///     which case the show runs to the end of the file.
    ///   - fileDuration: The length of the file so far.
    init(offset: TimeInterval, showLength: TimeInterval?, fileDuration: TimeInterval) {
        guard offset.isFinite, fileDuration.isFinite, showLength?.isFinite ?? true else {
            lowerBound = 0
            upperBound = 0
            return
        }
        let start = max(0, offset)
        let end = min(fileDuration, showLength.map { start + $0 } ?? fileDuration)
        guard end > start else {
            lowerBound = 0
            upperBound = 0
            return
        }
        lowerBound = start
        upperBound = end
    }

    /// How long the show is, in seconds; zero when there is nothing to play.
    var length: TimeInterval { upperBound - lowerBound }

    /// Whether the range is empty: the numbers were not usable, or the show lies outside the file.
    var isEmpty: Bool { length <= 0 }

    // MARK: Position

    /// How far into the show a moment in the file is, held between the show's start and its end.
    /// - Parameter fileTime: Seconds into the file.
    func elapsed(atFileTime fileTime: TimeInterval) -> TimeInterval {
        guard !isEmpty, fileTime.isFinite else { return 0 }
        let into = fileTime - lowerBound
        if into <= 0 { return 0 }
        if into >= length { return length }
        return into
    }

    /// How much of the show is left after a moment in the file.
    /// - Parameter fileTime: Seconds into the file.
    func remaining(atFileTime fileTime: TimeInterval) -> TimeInterval {
        guard !isEmpty else { return 0 }
        return length - elapsed(atFileTime: fileTime)
    }

    /// How far through the show a moment in the file is, from 0 to 1, for a scrubber.
    /// - Parameter fileTime: Seconds into the file.
    func fraction(atFileTime fileTime: TimeInterval) -> Double {
        guard !isEmpty else { return 0 }
        return elapsed(atFileTime: fileTime) / length
    }

    /// The elapsed time as a clock reading, such as `1:02:05`.
    func elapsedText(atFileTime fileTime: TimeInterval) -> String {
        ArchiveTiming.positionText(elapsed(atFileTime: fileTime))
    }

    /// The time left as a clock reading with a minus sign, such as `-57:55`.
    func remainingText(atFileTime fileTime: TimeInterval) -> String {
        "-" + ArchiveTiming.positionText(remaining(atFileTime: fileTime))
    }

    // MARK: Moving

    /// A finite file time held inside the show.
    private func held(_ fileTime: TimeInterval) -> TimeInterval {
        if fileTime <= lowerBound { return lowerBound }
        if fileTime >= upperBound { return upperBound }
        return fileTime
    }

    /// Where a skip lands.
    ///
    /// A skip back stops at the start of the show rather than playing the previous show's tail. A skip forward that
    /// reaches the end of the show goes on to what follows.
    /// - Parameters:
    ///   - seconds: How far to skip; negative to go back.
    ///   - fileTime: Where the player is now, in seconds into the file.
    func target(skipping seconds: TimeInterval, from fileTime: TimeInterval) -> Target {
        guard !isEmpty else { return .within(lowerBound) }
        guard fileTime.isFinite else { return .within(lowerBound) }
        guard seconds.isFinite else { return .within(held(fileTime)) }
        let landing = fileTime + seconds
        if landing >= upperBound { return .end }
        return .within(max(landing, lowerBound))
    }

    /// Where a point in the show lands, such as a song's place in it.
    /// - Parameter showTime: Seconds into the show. Before the start reads as the start; at or past the end goes on to
    ///   what follows; one that is not a number reads as the start.
    func target(showTime: TimeInterval) -> Target {
        guard !isEmpty, showTime.isFinite else { return .within(lowerBound) }
        if showTime <= 0 { return .within(lowerBound) }
        if showTime >= length { return .end }
        return .within(lowerBound + showTime)
    }

    /// Where a scrubber dragged to a fraction of the show lands.
    /// - Parameter fraction: 0 for the start of the show, 1 for its end; a value outside that is held to it, and one
    ///   that is not a number reads as the start.
    func target(fraction: Double) -> Target {
        guard !isEmpty else { return .within(lowerBound) }
        guard fraction.isFinite else { return .within(lowerBound) }
        let held = min(max(fraction, 0), 1)
        if held >= 1 { return .end }
        return .within(lowerBound + held * length)
    }
}
