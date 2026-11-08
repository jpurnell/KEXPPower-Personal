//
//  LiveRelay.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// What a request is answered with: a status, a content type and a body.
struct HLSResponse: Equatable, Sendable {
    let status: Int
    let contentType: String
    let body: Data

    static let notFound = HLSResponse(status: 404, contentType: "text/plain", body: Data("Not found\n".utf8))
}

/// Takes the live stream's bytes as they arrive and answers the player's requests for them.
///
/// The recorder feeds `ingest` and the local server asks `response(forPath:)`; this type is the only place that holds the
/// segmenter and the buffer, so the two never touch the same state from different threads.
actor LiveRelay {
    private static let playlistPath = "/live.m3u8"

    private let windowDuration: TimeInterval
    private let segmentDuration: TimeInterval
    private let now: @Sendable () -> Date
    private var segmenter: ADTSSegmenter
    private var buffer: LiveBuffer
    /// Set when the stream broke; the next segment is marked as following a gap.
    private var breakPending = false

    /// - Parameters:
    ///   - windowDuration: How much audio to keep, in seconds.
    ///   - segmentDuration: How long each segment should be, in seconds.
    ///   - now: The clock, so a test can fix the time of day.
    init(windowDuration: TimeInterval, segmentDuration: TimeInterval = 2, now: @escaping @Sendable () -> Date = { Date() }) {
        self.windowDuration = windowDuration
        self.segmentDuration = segmentDuration
        self.now = now
        segmenter = ADTSSegmenter(targetDuration: segmentDuration)
        buffer = LiveBuffer(windowDuration: windowDuration)
    }

    /// How much audio is held, in seconds.
    var bufferedDuration: TimeInterval { buffer.totalDuration }

    /// Takes the next bytes of the stream.
    func ingest(_ bytes: Data) {
        for segment in segmenter.append(bytes) { place(segment) }
    }

    /// The stream broke: whatever was waiting in the segmenter is kept, and the next audio is marked as following a gap.
    func streamBroke() {
        if let rest = segmenter.flush() { place(rest) }
        segmenter = ADTSSegmenter(targetDuration: segmentDuration)
        // A gap is only a gap if there is audio before it.
        breakPending = !buffer.entries.isEmpty
    }

    /// Forgets everything, as when the listener stops.
    func reset() {
        segmenter = ADTSSegmenter(targetDuration: segmentDuration)
        buffer = LiveBuffer(windowDuration: windowDuration)
        breakPending = false
    }

    /// The answer to a request for `path`.
    func response(forPath path: String) -> HLSResponse {
        if path == Self.playlistPath {
            guard !buffer.entries.isEmpty else { return .notFound }
            return HLSResponse(
                status: 200, contentType: "application/vnd.apple.mpegurl", body: Data(buffer.playlist().utf8))
        }
        guard let sequence = LiveBuffer.sequence(inPath: path), let data = buffer.data(forSequence: sequence) else {
            return .notFound
        }
        return HLSResponse(status: 200, contentType: "audio/aac", body: data)
    }

    private func place(_ segment: ADTSSegmenter.Segment) {
        // The segment was received just now, so it began as long ago as it lasts.
        buffer.append(segment, startDate: now().addingTimeInterval(-segment.duration), isDiscontinuity: breakPending)
        breakPending = false
    }
}
