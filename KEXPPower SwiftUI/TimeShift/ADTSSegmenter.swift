//
//  ADTSSegmenter.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// Cuts a live stream of ADTS AAC (the raw framing Icecast serves) into short segments, each beginning and ending on a
/// frame boundary, so each can be played on its own as a piece of an HLS stream.
///
/// Bytes go in as they arrive, in whatever sizes the network gives them. A frame is placed only once the header of the
/// frame after it has been seen, because an `0xFF 0xF?` pair can occur inside audio, and joining a stream in the middle
/// of a frame means the first bytes are not a frame at all. The segmenter holds no audio-format knowledge beyond the
/// ADTS header: the frame's length, and its sampling rate for its duration.
struct ADTSSegmenter {
    /// A run of whole frames.
    struct Segment: Equatable, Sendable {
        /// The frames' bytes, back to back.
        let data: Data
        /// How long they play, in seconds.
        let duration: TimeInterval
        /// How many frames there are.
        let frameCount: Int
    }

    /// An ADTS header with a usable length and rate.
    private struct Header {
        let length: Int
        let duration: TimeInterval
    }

    private enum Parse {
        case frame(Header)
        case invalid
        case needsMoreBytes
    }

    private static let defaultTarget: TimeInterval = 2
    private static let samplesPerFrame = 1_024.0
    /// The sampling frequencies an ADTS header's four-bit index names.
    private static let sampleRates: [Double] = [
        96_000, 88_200, 64_000, 48_000, 44_100, 32_000, 24_000, 22_050, 16_000, 12_000, 11_025, 8_000, 7_350,
    ]

    private let target: TimeInterval
    private var buffer: [UInt8] = []
    private var pending: [UInt8] = []
    private var pendingDuration: TimeInterval = 0
    private var pendingFrames = 0

    /// - Parameter targetDuration: How long a segment should be, in seconds; a segment ends at the first frame boundary at
    ///   or after it. A value that is not a positive finite number reads as two seconds.
    init(targetDuration: TimeInterval = 2) {
        target = targetDuration.isFinite && targetDuration > 0 ? targetDuration : Self.defaultTarget
    }

    /// Takes more of the stream.
    /// - Parameter bytes: The next bytes, in any size.
    /// - Returns: The segments that are now complete, oldest first; usually none or one.
    mutating func append(_ bytes: Data) -> [Segment] {
        buffer.append(contentsOf: bytes)
        return consume(isFinal: false)
    }

    /// Ends the stream (the connection dropped, or the listener stopped): hands over the frames still waiting.
    /// - Returns: A short last segment, or `nil` if no whole frame is waiting. A frame cut off by the end is dropped.
    mutating func flush() -> Segment? {
        _ = consume(isFinal: true)
        buffer.removeAll()
        return takePending()
    }

    // MARK: Framing

    private mutating func consume(isFinal: Bool) -> [Segment] {
        var segments: [Segment] = []
        var position = 0
        scan: while position < buffer.count {
            switch Self.parse(buffer, at: position) {
            case .invalid:
                position = Self.nextCandidate(in: buffer, after: position)
            case .needsMoreBytes:
                if isFinal { position = buffer.count }
                break scan
            case .frame(let header):
                let end = position + header.length
                // A frame is believed once the next header follows it. At the very end there may be nothing to check.
                let lookahead = end + 2 <= buffer.count
                if !lookahead, !isFinal { break scan }
                if !lookahead, end > buffer.count {
                    position = buffer.count
                    break scan
                }
                if lookahead, !Self.isSync(buffer, at: end) {
                    // Not a frame after all: its claimed end is not the start of another.
                    position += 1
                    continue
                }
                pending.append(contentsOf: buffer[position..<end])
                pendingDuration += header.duration
                pendingFrames += 1
                position = end
                if !isFinal, pendingDuration >= target, let segment = takePending() { segments.append(segment) }
            }
        }
        buffer.removeFirst(position)
        return segments
    }

    private mutating func takePending() -> Segment? {
        guard pendingFrames > 0 else { return nil }
        let segment = Segment(data: Data(pending), duration: pendingDuration, frameCount: pendingFrames)
        pending.removeAll(keepingCapacity: true)
        pendingDuration = 0
        pendingFrames = 0
        return segment
    }

    /// Whether two bytes at a position open an ADTS header: twelve set bits, and layer zero.
    private static func isSync(_ bytes: [UInt8], at index: Int) -> Bool {
        bytes[index] == 0xFF && (bytes[index + 1] & 0xF6) == 0xF0
    }

    private static func parse(_ bytes: [UInt8], at index: Int) -> Parse {
        guard bytes[index] == 0xFF else { return .invalid }
        guard index + 7 <= bytes.count else { return .needsMoreBytes }
        guard (bytes[index + 1] & 0xF6) == 0xF0 else { return .invalid }
        let protectionAbsent = bytes[index + 1] & 0x01 == 1
        let rateIndex = Int((bytes[index + 2] >> 2) & 0x0F)
        guard rateIndex < sampleRates.count, sampleRates[rateIndex] > 0 else { return .invalid }
        let length = (Int(bytes[index + 3] & 0x03) << 11) | (Int(bytes[index + 4]) << 3) | Int(bytes[index + 5] >> 5)
        let headerLength = protectionAbsent ? 7 : 9
        guard length >= headerLength else { return .invalid }
        return .frame(Header(length: length, duration: samplesPerFrame / sampleRates[rateIndex]))
    }

    /// The next place a header could begin after a position: the next `0xFF`, or the end if there is none.
    private static func nextCandidate(in bytes: [UInt8], after index: Int) -> Int {
        var next = index + 1
        while next < bytes.count, bytes[next] != 0xFF { next += 1 }
        return next
    }
}
