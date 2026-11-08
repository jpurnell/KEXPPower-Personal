//
//  LiveRewindProbeView.swift
//  KEXPPowerExampleSwiftUI
//

#if os(iOS) && DEBUG
import AVFoundation
import SwiftUI

/// A debug-only panel for Phase 0 of live rewind: it records the live stream into a `LiveRelay`, serves it from the
/// loopback address, and plays it with a separate `AVPlayer`, to find out on a device what the design only assumes.
///
/// The questions it answers: whether `AVPlayer` accepts the packed-audio playlist and its timestamp tags, how far behind
/// the stream "live" is, whether recording continues with the screen locked, and whether playback rides through a lost
/// connection and jumps the gap. Readings go to the persistent diagnostic log under "LiveProbe".
@MainActor
@Observable
final class LiveRewindProbeModel {
    private static let streamURL = URL(string: "https://kexp.streamguys1.com/kexp160.aac")
    private static let firstSegmentsNeeded: TimeInterval = 6
    private static let logEvery = 5

    private let relay = LiveRelay(windowDuration: 600)
    private let server: LocalHLSServer
    private let diagnostics = DiagnosticLog.app
    private var recorder: LiveRecorder?
    private var ticks = 0

    private(set) var player: AVPlayer?
    private(set) var readout = "Stopped"
    private(set) var lines: [String] = []

    init() {
        server = LocalHLSServer(relay: relay)
    }

    /// Records the stream, waits for a few segments, and plays through the local server.
    func start() async {
        guard player == nil, let stream = Self.streamURL else { return }
        note("starting")
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            note("audio session: \(error.localizedDescription)")
        }
        let recorder = LiveRecorder(source: URLSessionByteSource(url: stream), relay: relay)
        self.recorder = recorder
        await recorder.start()
        for _ in 0..<40 where await relay.bufferedDuration < Self.firstSegmentsNeeded {
            try? await Task.sleep(for: .milliseconds(500))
        }
        note("buffered \(whole(await relay.bufferedDuration)) s before playing")
        do {
            let url = try await server.start()
            note("serving \(url.absoluteString)")
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            self.player = player
            player.play()
        } catch {
            note("server failed: \(error.localizedDescription)")
        }
    }

    /// Stops everything and clears the buffer.
    func stop() async {
        note("stopping")
        player?.pause()
        player = nil
        server.stop()
        await recorder?.stop()
        recorder = nil
        readout = "Stopped"
    }

    func skip(by seconds: TimeInterval) {
        guard let player else { return }
        let now = player.currentTime().seconds
        guard now.isFinite else { return }
        note("skip \(whole(seconds)) s from \(whole(now))")
        player.seek(to: CMTime(seconds: now + seconds, preferredTimescale: 600))
    }

    func togglePause() {
        guard let player else { return }
        if player.timeControlStatus == .paused { player.play() } else { player.pause() }
        note(player.timeControlStatus == .paused ? "paused" : "playing")
    }

    /// Seeks to the newest the playlist offers.
    func goLive() {
        guard let player, let end = player.currentItem?.seekableTimeRanges.last?.timeRangeValue.end, end.seconds.isFinite
        else { return }
        note("to the live edge at \(whole(end.seconds))")
        player.seek(to: end)
    }

    /// Reads the player and the buffer; called every second while the panel is up.
    func refresh() async {
        let held = await relay.bufferedDuration
        guard let player, let item = player.currentItem else {
            readout = "Buffered \(whole(held)) s; no player"
            return
        }
        let current = player.currentTime().seconds
        let range = item.seekableTimeRanges.last?.timeRangeValue
        let seekEnd = range?.end.seconds ?? .nan
        let behind = seekEnd.isFinite && current.isFinite ? seekEnd - current : .nan
        let wallBehind = item.currentDate().map { Date().timeIntervalSince($0) } ?? .nan
        let status = ["paused", "waiting", "playing"][min(player.timeControlStatus.rawValue, 2)]
        let failure = item.error.map { " ERROR \($0.localizedDescription)" } ?? ""
        readout = """
            \(status), item \(item.status.rawValue)\(failure)
            buffered \(whole(held)) s
            at \(whole(current)) s, window ends \(whole(seekEnd)) s
            behind the window's end \(whole(behind)) s; behind the clock \(whole(wallBehind)) s
            """
        ticks += 1
        if ticks % Self.logEvery == 0 { diagnostics.record("LiveProbe", readout.replacingOccurrences(of: "\n", with: " | ")) }
    }

    /// A number as a whole number of seconds, or a dash if it is not a number.
    private func whole(_ value: Double) -> String {
        guard value.isFinite, abs(value) < 1e9 else { return "-" }
        return String(Int(value.rounded()))
    }

    private func note(_ text: String) {
        lines.append(text)
        diagnostics.record("LiveProbe", text)
    }
}

/// The panel: start, then try pause, back 15, back 5 minutes and the live edge, and watch the readout.
struct LiveRewindProbeView: View {
    @State private var probe = LiveRewindProbeModel()

    var body: some View {
        List {
            Section("Live rewind probe (debug builds only)") {
                Text("Pause the app's own live stream first, so only one is playing.").font(.caption)
                Button("Start recording and play") { Task { await probe.start() } }
                Button("Stop") { Task { await probe.stop() } }
                Button("Pause / play") { probe.togglePause() }
                Button("Back 15 s") { probe.skip(by: -15) }
                Button("Back 5 minutes") { probe.skip(by: -300) }
                Button("Forward 30 s") { probe.skip(by: 30) }
                Button("To the live edge") { probe.goLive() }
                Text(probe.readout).font(.caption.monospaced())
            }
            Section("Log") {
                ForEach(Array(probe.lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption2.monospaced())
                }
            }
        }
        .task {
            while !Task.isCancelled {
                await probe.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
#endif
