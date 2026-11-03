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
    private(set) var isPlaying = false
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
    @ObservationIgnored private let polling = PollingTask()

    init() {
        snapshot = NowPlayingSnapshot(.nothing, stationName: "KEXP", fallbackArtworkURL: logoURL, state: .paused)
    }

    /// Prepares playback and starts following what is on the air.
    func start() {
        guard player == nil else { return }
        sessionCoordinator.configure()

        let streams = station.streams
        guard let stream = streams.first(where: { $0.id == "64" }) ?? streams.first else {
            notice = "No stream available"
            return
        }
        let player = AVPlayer(url: stream.url)
        self.player = player

        statusObservation = player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                MainActor.assumeIsolated { self?.timeControlStatusChanged(status) }
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
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    /// Starts playback, asking the system for a route first when one is needed.
    func play() {
        Task { [weak self] in await self?.startPlayback() }
    }

    private func startPlayback() async {
        guard await sessionCoordinator.activateForPlayback() else {
            notice = "Choose an audio output to listen"
            return
        }
        notice = nil
        player?.play()
    }

    /// Pauses playback.
    func pause() {
        player?.pause()
    }

    /// Plays when paused and pauses when playing.
    func toggle() {
        isPlaying ? pause() : play()
    }

    private func timeControlStatusChanged(_ status: AVPlayer.TimeControlStatus) {
        isPlaying = status == .playing
        snapshot.state = isPlaying ? .playing : .paused
        publisher.publish(snapshot, artwork: currentArtwork)
    }

    private func refresh() async {
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
            guard snapshot.artworkURL == next.artworkURL, snapshot.title == next.title else { return }
            currentArtwork = artwork
            publisher.publish(snapshot, artwork: artwork)
        } catch {
            let message = "Refresh failed: \(error.localizedDescription)"
            logger.error("\(message, privacy: .public)")
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
