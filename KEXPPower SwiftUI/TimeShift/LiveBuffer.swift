//
//  LiveBuffer.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// The ID3 tag that begins each segment of packed-audio HLS: one `PRIV` frame, owned by Apple's
/// `com.apple.streaming.transportStreamTimestamp`, holding where the segment's first sample is on a 90 kHz clock.
///
/// A raw AAC segment has no clock of its own, so without this the player cannot place it. The tag is ID3v2.4 with sizes in
/// the format's seven-bit "synchsafe" bytes; every size here is small enough that they equal plain big-endian numbers.
enum ID3Timestamp {
    private static let owner = Array("com.apple.streaming.transportStreamTimestamp".utf8) + [0]

    /// - Parameter presentationTime: Ticks of a 90 kHz clock. Thirty-three bits are kept, as in a transport stream.
    static func tag(presentationTime: UInt64) -> Data {
        let time = presentationTime & ((1 << 33) - 1)
        let payload = owner + (0..<8).reversed().map { UInt8((time >> (8 * UInt64($0))) & 0xFF) }
        let frame = Array("PRIV".utf8) + synchsafe(payload.count) + [0, 0] + payload
        return Data(Array("ID3".utf8) + [0x04, 0x00, 0x00] + synchsafe(frame.count) + frame)
    }

    /// A number as four seven-bit bytes, most significant first.
    private static func synchsafe(_ value: Int) -> [UInt8] {
        [UInt8((value >> 21) & 0x7F), UInt8((value >> 14) & 0x7F), UInt8((value >> 7) & 0x7F), UInt8(value & 0x7F)]
    }
}

/// The last few minutes of the live stream, as segments in memory, with the HLS playlist that describes them.
///
/// This is what gives a live stream that has no rewind window one: the player is pointed at a playlist that lists the
/// retained segments, and so can pause, go back, and return to the newest. Everything here is a value and is tested
/// without a network or a player.
struct LiveBuffer {
    /// One segment as it is served.
    struct Entry: Equatable, Sendable {
        let sequence: Int
        let duration: TimeInterval
        /// The time of day the segment's audio was received.
        let startDate: Date
        /// Whether a break in the stream (a dropped connection) lies between this segment and the one before it.
        let isDiscontinuity: Bool
        /// The timestamp tag, then the segment's frames.
        let data: Data

        /// Where the playlist says to fetch it.
        var uri: String { "segment\(sequence).aac" }
    }

    private static let defaultWindow: TimeInterval = 600
    private static let ticksPerSecond = 90_000.0
    private static let uriPrefix = "segment"
    private static let uriSuffix = ".aac"

    private let window: TimeInterval
    private(set) var entries: [Entry] = []
    private var nextSequence = 0
    /// How much audio has ever been appended, which is the clock the timestamp tags run on.
    private var mediaClock: TimeInterval = 0
    /// How many segments that began a new run have been dropped off the front.
    private var droppedDiscontinuities = 0

    /// - Parameter windowDuration: How much to keep, in seconds. The buffer keeps at least this much, and drops the oldest
    ///   whole segments beyond it. A value that is not a positive finite number reads as ten minutes.
    init(windowDuration: TimeInterval) {
        window = windowDuration.isFinite && windowDuration > 0 ? windowDuration : Self.defaultWindow
    }

    /// How much audio is held, in seconds.
    var totalDuration: TimeInterval { entries.reduce(0) { $0 + $1.duration } }

    /// How many bytes would be served for everything held.
    var byteCount: Int { entries.reduce(0) { $0 + $1.data.count } }

    /// Adds the newest segment and drops the oldest beyond the window.
    /// - Parameters:
    ///   - segment: What the segmenter cut.
    ///   - startDate: When its audio was received.
    ///   - isDiscontinuity: `true` if the stream broke before it, so the player should expect the audio to jump.
    mutating func append(_ segment: ADTSSegmenter.Segment, startDate: Date, isDiscontinuity: Bool = false) {
        let ticks = Self.ticks(of: mediaClock)
        entries.append(Entry(
            sequence: nextSequence, duration: segment.duration, startDate: startDate, isDiscontinuity: isDiscontinuity,
            data: ID3Timestamp.tag(presentationTime: ticks) + segment.data))
        nextSequence += 1
        mediaClock += segment.duration
        var total = totalDuration
        while entries.count > 1, total - entries[0].duration >= window {
            let dropped = entries.removeFirst()
            total -= dropped.duration
            if dropped.isDiscontinuity { droppedDiscontinuities += 1 }
        }
    }

    /// The bytes of one segment, if it is still held.
    func data(forSequence sequence: Int) -> Data? {
        entries.first { $0.sequence == sequence }?.data
    }

    /// The live playlist: no end marker, so the player keeps asking for it.
    func playlist() -> String {
        let longest = entries.map(\.duration).max() ?? 2
        let target = longest.isFinite && longest > 0 && longest < 3_600 ? Int(longest.rounded(.up)) : 2
        var lines = [
            "#EXTM3U", "#EXT-X-VERSION:3", "#EXT-X-TARGETDURATION:\(target)",
            "#EXT-X-MEDIA-SEQUENCE:\(entries.first?.sequence ?? 0)",
        ]
        if droppedDiscontinuities > 0 { lines.append("#EXT-X-DISCONTINUITY-SEQUENCE:\(droppedDiscontinuities)") }
        let dates = ISO8601DateFormatter()
        dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        dates.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let seconds = FloatingPointFormatStyle<Double>.number
            .locale(Locale(identifier: "en_US_POSIX")).precision(.fractionLength(3)).grouping(.never)
        for (index, entry) in entries.enumerated() {
            if entry.isDiscontinuity { lines.append("#EXT-X-DISCONTINUITY") }
            // The time of day goes on the first segment and after each break; the player counts on from there.
            if index == 0 || entry.isDiscontinuity {
                lines.append("#EXT-X-PROGRAM-DATE-TIME:\(dates.string(from: entry.startDate))")
            }
            lines.append("#EXTINF:\(entry.duration.formatted(seconds)),")
            lines.append(entry.uri)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The segment number a request path names, or `nil` for anything that is not `segment<number>.aac`.
    static func sequence(inPath path: String) -> Int? {
        let name = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard name.hasPrefix(uriPrefix), name.hasSuffix(uriSuffix) else { return nil }
        let digits = name.dropFirst(uriPrefix.count).dropLast(uriSuffix.count)
        guard !digits.isEmpty, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else { return nil }
        return Int(digits)
    }

    /// Seconds of audio as ticks of the 90 kHz clock; zero for a number that cannot be one.
    private static func ticks(of seconds: TimeInterval) -> UInt64 {
        let ticks = seconds * ticksPerSecond
        guard ticks.isFinite, ticks >= 0, ticks < 1e15 else { return 0 }
        return UInt64(ticks.rounded())
    }
}
