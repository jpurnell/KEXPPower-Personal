//
//  WatchPlayer.swift
//  Spinner Watch
//

import AVFoundation
import Combine
import Observation
import OSLog
import StationKit
import StationKitAdapterKEXP

/// Plays the live stream on the watch and tells the system what is on the air.
///
/// `isPlaying` mirrors the player's own `timeControlStatus`, so a remote command or an interruption
/// cannot leave it out of step. The watch asks for the lower-bitrate stream to spare battery and cellular data.
@MainActor
@Observable
final class WatchPlayer {
    /// How far the stream is from being playable. A fresh launch can take a while on a cold watch network.
    enum Connection: Equatable {
        case connecting
        case ready
        case failed
    }

    private(set) var isPlaying = false
    private(set) var connection = Connection.connecting
    /// True from the tap until audio is actually playing, which takes a few seconds on a live stream.
    private(set) var isBuffering = false
    private(set) var artwork: CGImage?
    /// The system output volume, 0...1, as the Digital Crown changes it.
    private(set) var volume: Float = 0
    private(set) var title = "KEXP"
    private(set) var artist = ""
    private(set) var notice: String?

    @ObservationIgnored private let station = KEXPStation()
    @ObservationIgnored private let sessionCoordinator = AudioSessionCoordinator()
    @ObservationIgnored private let publisher: any NowPlayingPublishing = LegacyNowPlayingPublisher()
    @ObservationIgnored private let artworkLoader = ArtworkLoader(allowedDomains: ["kexp.org", "archive.org"])
    @ObservationIgnored private let logger = Logger(subsystem: "com.JPEnterprises.Spinner", category: "WatchPlayer")
    @ObservationIgnored private let logoURL = URL(string: "https://kexp.org/static/assets/img/kexp_logo.jpg")

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var snapshot: NowPlayingSnapshot
    @ObservationIgnored private var currentArtwork: CGImage?
    @ObservationIgnored private var statusObservation: AnyCancellable?
    @ObservationIgnored private var itemObservation: AnyCancellable?
    @ObservationIgnored private var volumeObservation: AnyCancellable?
    @ObservationIgnored private let polling = PollingTask()

    init() {
        snapshot = NowPlayingSnapshot(.nothing, stationName: "KEXP", fallbackArtworkURL: logoURL, state: .paused)
    }

    /// Prepares playback and starts following what is on the air.
    func start() {
        guard player == nil else { return }
        sessionCoordinator.configure()
        makePlayer()

        let session = AVAudioSession.sharedInstance()
        volume = session.outputVolume
        volumeObservation = session.publisher(for: \.outputVolume)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                MainActor.assumeIsolated { self?.volumeChanged(to: value) }
            }

        sessionCoordinator.observe { [weak self] action in
            switch action {
            case .resume: self?.play()
            case .pause: self?.pause()
            case .none: break
            }
        }
        publisher.installCommands(
            play: { [weak self] in self?.play() },
            pause: { [weak self] in self?.pause() },
            toggle: { [weak self] in self?.toggle() })

        polling.task?.cancel()
        polling.task = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                let succeeded = await self?.refresh() ?? false
                failures = succeeded ? 0 : failures + 1
                // Refresh every 15 s; after a failure retry sooner (3 s, 6 s, 9 s, …) so a cold network recovers quickly.
                try? await Task.sleep(for: .seconds(succeeded ? 15 : min(3 * failures, 15)))
            }
        }
    }

    private func volumeChanged(to value: Float) {
        // The system repeats the notification while the crown turns; only a new level is news.
        guard abs(value - volume) >= 0.001 else { return }
        volume = value
        let message = "Output volume \(value)"
        logger.info("\(message, privacy: .public)")
    }

    /// Creates the player for the stream; also used to start over after a failed connection.
    private func makePlayer() {
        let streams = station.streams
        guard let stream = streams.first(where: { $0.id == "64" }) ?? streams.first else {
            notice = "No stream available"
            connection = .failed
            return
        }
        let player = AVPlayer(url: stream.url)
        self.player = player
        connection = .connecting
        let streamMessage = "Stream \(stream.id) kbps option, \(stream.kind)"
        logger.info("\(streamMessage, privacy: .public)")

        itemObservation = player.currentItem?.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                MainActor.assumeIsolated { self?.itemStatusChanged(status) }
            }

        statusObservation = player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                MainActor.assumeIsolated { self?.timeControlStatusChanged(status) }
            }
    }

    /// What to tell the listener about the connection, or `nil` when the stream is ready.
    var connectionText: String? {
        switch connection {
        case .connecting: "Connecting…"
        case .ready: nil
        case .failed: "Can't reach KEXP. Tap to retry."
        }
    }

    /// Starts playback, asking the system for a route first when one is needed.
    ///
    /// A tap while the stream is still connecting means "play as soon as it is ready".
    func play() {
        if connection == .failed { makePlayer() }
        Task { [weak self] in await self?.startPlayback() }
    }

    private func startPlayback() async {
        isBuffering = true
        let activated = await sessionCoordinator.activateForPlayback()
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ",")
        let sessionMessage = "Activation \(activated ? "succeeded" : "failed"); policy \(session.routeSharingPolicy.rawValue); outputs \(outputs)"
        logger.info("\(sessionMessage, privacy: .public)")
        guard activated else {
            isBuffering = false
            notice = "Choose an audio output to listen"
            return
        }
        notice = nil
        player?.play()
    }

    private func itemStatusChanged(_ status: AVPlayerItem.Status) {
        let error = player?.currentItem?.error
        let message = "Item status \(status.rawValue); error \(error?.localizedDescription ?? "none")"
        logger.info("\(message, privacy: .public)")
        switch status {
        case .readyToPlay:
            connection = .ready
        case .failed:
            connection = .failed
            isBuffering = false
        case .unknown:
            connection = .connecting
        @unknown default:
            connection = .connecting
        }
    }

    /// Pauses playback.
    func pause() {
        isBuffering = false
        player?.pause()
    }

    /// Plays when paused and pauses when playing.
    func toggle() {
        isPlaying || isBuffering ? pause() : play()
    }

    private func timeControlStatusChanged(_ status: AVPlayer.TimeControlStatus) {
        isPlaying = status == .playing
        if isPlaying { isBuffering = false }
        let waitingReason = player?.reasonForWaitingToPlay?.rawValue ?? "none"
        let message = "timeControlStatus \(status.rawValue); waiting reason \(waitingReason)"
        logger.info("\(message, privacy: .public)")
        snapshot.state = isPlaying ? .playing : .paused
        publisher.publish(snapshot, artwork: currentArtwork)
    }

    /// Refreshes what is on the air.
    /// - Returns: Whether the station answered.
    private func refresh() async -> Bool {
        do {
            let nowPlaying = try await station.nowPlaying()
            let next = NowPlayingSnapshot(
                nowPlaying, stationName: "KEXP", fallbackArtworkURL: logoURL,
                state: isPlaying ? .playing : .paused)
            title = next.title
            artist = next.artist
            snapshot = next

            var artwork: CGImage?
            if let url = next.artworkURL { artwork = await artworkLoader.image(for: url) }
            guard snapshot.artworkURL == next.artworkURL, snapshot.title == next.title else { return true }
            currentArtwork = artwork
            self.artwork = artwork
            publisher.publish(snapshot, artwork: artwork)
            return true
        } catch {
            let message = "Refresh failed: \(error.localizedDescription)"
            logger.error("\(message, privacy: .public)")
            return false
        }
    }
}

/// Holds the refresh loop and cancels it when the owner goes away.
private final class PollingTask {
    var task: Task<Void, Never>?

    deinit {
        task?.cancel()
    }
}
