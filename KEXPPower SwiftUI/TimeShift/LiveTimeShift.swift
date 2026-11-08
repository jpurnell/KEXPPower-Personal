//
//  LiveTimeShift.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// Something that can offer the player a live stream with a rewind window.
@MainActor
protocol LiveShifting: AnyObject {
    /// How many seconds of the stream are kept.
    var window: TimeInterval { get }
    /// Starts recording the live stream and serving it locally.
    /// - Returns: The address to play, or `nil` if it could not be made ready, in which case the direct stream is played.
    func start() async -> URL?
    /// Stops recording and serving, and forgets what was kept.
    func stop() async
}

/// Records the live stream and serves the last few minutes of it on this device, so the player can treat it as an HLS
/// stream it can pause and rewind.
@MainActor
final class LiveTimeShift: LiveShifting {
    private let relay: LiveRelay
    private let recorder: LiveRecorder
    private let server: LocalHLSServer
    private let firstAudio: TimeInterval
    private let timeout: TimeInterval
    private var address: URL?
    let window: TimeInterval

    /// - Parameters:
    ///   - source: Where the live stream comes from.
    ///   - window: How many seconds to keep.
    ///   - firstAudio: How many seconds must be recorded before the player is pointed at it.
    ///   - timeout: How long to wait for that, in seconds, before giving up.
    init(source: any LiveByteSource, window: TimeInterval, firstAudio: TimeInterval = 4, timeout: TimeInterval = 15) {
        let relay = LiveRelay(windowDuration: window)
        self.relay = relay
        recorder = LiveRecorder(
            source: source, relay: relay, report: { DiagnosticLog.app.record("TimeShift", "recorder: \($0)") })
        server = LocalHLSServer(relay: relay)
        self.window = window
        self.firstAudio = firstAudio
        self.timeout = timeout
    }

    func start() async -> URL? {
        if let address { return address }
        await recorder.start()
        let deadline = Date().addingTimeInterval(timeout)
        while await relay.bufferedDuration < firstAudio {
            guard Date() < deadline, !Task.isCancelled else {
                DiagnosticLog.app.record("TimeShift", "no audio in time; playing the stream directly")
                await recorder.stop()
                return nil
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        do {
            let url = try await server.start()
            address = url
            DiagnosticLog.app.record("TimeShift", "ready at \(url.absoluteString)")
            return url
        } catch {
            DiagnosticLog.app.record("TimeShift", "server failed: \(error.localizedDescription); playing directly")
            await recorder.stop()
            return nil
        }
    }

    func stop() async {
        server.stop()
        await recorder.stop()
        address = nil
    }
}
