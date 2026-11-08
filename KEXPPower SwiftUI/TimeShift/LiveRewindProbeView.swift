//
//  LiveRewindProbeView.swift
//  KEXPPowerExampleSwiftUI
//

#if os(iOS) && DEBUG
import AVFoundation
import Network
import SwiftUI
import UIKit

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
    private static let logEvery = 2

    private let relay = LiveRelay(windowDuration: 600)
    private let server: LocalHLSServer
    private let appPlayer: PlayerController
    private var heartbeat: Task<Void, Never>?
    private let diagnostics = DiagnosticLog.app
    private var recorder: LiveRecorder?
    private var ticks = 0
    private var observers: [any NSObjectProtocol] = []
    private var pathMonitor: NWPathMonitor?

    private(set) var player: AVPlayer?
    private(set) var readout = "Stopped"
    private(set) var lines: [String] = []

    init(appPlayer: PlayerController) {
        self.appPlayer = appPlayer
        server = LocalHLSServer(relay: relay)
    }

    isolated deinit {
        heartbeat?.cancel()
    }

    /// Records the stream, waits for a few segments, and plays through the local server.
    func start() async {
        guard player == nil, let stream = Self.streamURL else { return }
        note("starting; the app's own player was \(appPlayer.isPlaying ? "playing" : "not playing")")
        if appPlayer.isPlaying { appPlayer.pausePlayer() }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            note("audio session: \(error.localizedDescription)")
        }
        let log = diagnostics
        let recorder = LiveRecorder(
            source: URLSessionByteSource(url: stream), relay: relay,
            report: { log.record("LiveProbe", "recorder: \($0)") })
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
            observe(item, player)
            player.play()
            startHeartbeat()
        } catch {
            note("server failed: \(error.localizedDescription)")
        }
    }

    /// Stops everything and clears the buffer.
    func stop() async {
        note("stopping")
        player?.pause()
        player = nil
        stopObserving()
        heartbeat?.cancel()
        heartbeat = nil
        server.stop()
        await recorder?.stop()
        recorder = nil
        readout = "Stopped"
    }

    /// Writes down what the system tells the player and the app, so a gap or a stall can be explained afterwards.
    private func observe(_ item: AVPlayerItem, _ player: AVPlayer) {
        let center = NotificationCenter.default
        let log = diagnostics
        func watch(_ name: Notification.Name, _ object: Any?, _ text: @escaping @Sendable (Notification) -> String) {
            observers.append(center.addObserver(forName: name, object: object, queue: .main) { note in
                log.record("LiveProbe", "event: \(text(note))")
            })
        }
        watch(.AVPlayerItemPlaybackStalled, item) { _ in "playback stalled" }
        watch(.AVPlayerItemFailedToPlayToEndTime, item) { note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
            return "failed to play to end: \(error?.localizedDescription ?? "unknown")"
        }
        watch(.AVPlayerItemTimeJumped, item) { _ in "time jumped" }
        watch(.AVPlayerItemNewErrorLogEntry, item) { _ in
            "error log: \(item.errorLog()?.events.last?.errorComment ?? "-") (\(item.errorLog()?.events.last?.errorStatusCode ?? 0))"
        }
        watch(.AVPlayerItemNewAccessLogEntry, item) { _ in
            let last = item.accessLog()?.events.last
            return "access log: \(last?.numberOfMediaRequests ?? 0) requests, \(last?.numberOfStalls ?? 0) stalls, "
                + "\(last?.numberOfServerAddressChanges ?? 0) server changes, \(last?.downloadOverdue ?? 0) overdue"
        }
        watch(UIApplication.didEnterBackgroundNotification, nil) { _ in "app in background" }
        watch(UIApplication.willEnterForegroundNotification, nil) { _ in "app to foreground" }
        watch(AVAudioSession.interruptionNotification, nil) { note in
            "audio interruption \(note.userInfo?[AVAudioSessionInterruptionTypeKey] ?? "?")"
        }
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { path in
            log.record("LiveProbe", "network: \(path.status) \(path.isExpensive ? "expensive" : "")")
        }
        monitor.start(queue: .main)
        note("watching events")
    }

    /// Logs from the model, not the screen, so it carries on while the screen is locked (the panel's own timer stops).
    private func startHeartbeat() {
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                await self?.beat()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// One reading, and whether the app's own player has started on its own.
    private func beat() async {
        await refresh()
        diagnostics.record("LiveProbe", "heartbeat: \(appPlayer.isPlaying ? "app player PLAYING" : "app player idle")")
    }

    private func stopObserving() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        pathMonitor?.cancel()
        pathMonitor = nil
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
    @State private var probe: LiveRewindProbeModel

    init(appPlayer: PlayerController) {
        _probe = State(initialValue: LiveRewindProbeModel(appPlayer: appPlayer))
    }

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
        .onDisappear { Task { await probe.stop() } }
        .task {
            while !Task.isCancelled {
                await probe.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
#endif
