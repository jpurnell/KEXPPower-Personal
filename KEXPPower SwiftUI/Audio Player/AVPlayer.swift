//
//  AVPlayer.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 5/8/24.
//  Copyright © 2024 KEXP. All rights reserved.
//


import AVFoundation
import AVKit
import Combine
import Foundation
import ImageIO
import Observation
import OSLog
import StationKit
import UniformTypeIdentifiers

    /// Owns the live-stream `AVPlayer` and reports it to the system through a single publisher.
    ///
    /// `isPlaying` mirrors the player's own `timeControlStatus`; it is never toggled by hand, so a
    /// remote command, an interruption, or a route change cannot leave it out of step.
    @MainActor
    @Observable
    final class PlayerController: ArchivePlayer {

        // MARK: - State

        private(set) var isPlaying = false

        /// Called with the new value whenever the player starts or stops playing.
        @ObservationIgnored var onPlayingChange: (@MainActor (Bool) -> Void)?

        @ObservationIgnored private(set) var player: AVPlayer?
        /// The live stream's address, kept so the player can return to it after an archived show.
        @ObservationIgnored private var liveLink: URL?
        /// Whether the player holds an archived show's file instead of the live stream.
        private(set) var isPlayingArchive = false
        /// Watches how long going back to live takes; replaced each time, so only the latest request is measured.
        @ObservationIgnored private let liveTimer = TaskHolder()
        /// How far from the end of an archived file the next item is lined up, so it is loaded before it is needed.
        static let handoffLead: TimeInterval = 30
        @ObservationIgnored private var continuation: (@MainActor () async -> ArchiveContinuation)?
        @ObservationIgnored private var onAdvanced: (@MainActor (ArchiveContinuation) async -> Void)?
        @ObservationIgnored private var queued: (item: AVPlayerItem, plan: ArchiveContinuation)?
        @ObservationIgnored private let endWatch = TaskHolder()
        @ObservationIgnored private var itemObservation: AnyCancellable?
        #if !os(macOS)
        let avPlayerViewController = AVPlayerViewController()
        #endif

        private let stationName: String
        private let fallbackArtworkURL: URL?
        @ObservationIgnored private var snapshot: NowPlayingSnapshot
        @ObservationIgnored private var currentArtwork: CGImage?
        @ObservationIgnored private var statusObservation: AnyCancellable?

        private let artworkLoader: ArtworkLoader
        private let publisher: any NowPlayingPublishing
        private let sessionCoordinator = AudioSessionCoordinator()
        private let logger = Logger(#function)

        /// - Parameters:
        ///   - stationName: Shown as the artist when the broadcast names none.
        ///   - fallbackArtworkURL: Artwork used when a broadcast has none, usually the station's logo.
        ///   - artworkLoader: Loads artwork; its allowed domains decide where images may come from.
        ///   - publisher: The single writer of system Now Playing state.
        init(
            stationName: String = "KEXP",
            fallbackArtworkURL: URL? = URL(string: "https://kexp.org/static/assets/img/kexp_logo.jpg"),
            artworkLoader: ArtworkLoader = ArtworkLoader(allowedDomains: ["kexp.org", "archive.org"]),
            publisher: any NowPlayingPublishing = LegacyNowPlayingPublisher()
        ) {
            self.stationName = stationName
            self.fallbackArtworkURL = fallbackArtworkURL
            self.artworkLoader = artworkLoader
            self.publisher = publisher
            self.snapshot = NowPlayingSnapshot(
                .nothing, stationName: stationName, fallbackArtworkURL: fallbackArtworkURL, state: .paused)
        }

        // MARK: - Setup

        /// Creates the player for a stream and starts reporting it to the system.
        /// - Parameter link: The live-stream URL.
        func initPlayer(link: URL) {
            logger.debug("Initiating PlayerController")

            sessionCoordinator.configure()
            liveLink = link
            // A queue player, so the next item can be loaded while the current one is still playing.
            let player = AVQueuePlayer(playerItem: AVPlayerItem(url: link))
            #if !os(visionOS)
            player.allowsExternalPlayback = true
            #endif
            player.currentItem?.preferredForwardBufferDuration = 300
            self.player = player

            #if !os(macOS)
            avPlayerViewController.player = player
            avPlayerViewController.showsPlaybackControls = true
            // The publisher is the only writer of Now Playing state.
            avPlayerViewController.updatesNowPlayingInfoCenter = false
            #endif

            statusObservation = player.publisher(for: \.timeControlStatus)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] status in
                    MainActor.assumeIsolated { self?.timeControlStatusChanged(status) }
                }

            itemObservation = player.publisher(for: \.currentItem)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] item in
                    MainActor.assumeIsolated { self?.currentItemChanged(item) }
                }

            sessionCoordinator.observe { [weak self] action in
                switch action {
                case .resume: self?.playPlayer()
                case .pause: self?.pausePlayer()
                case .none: break
                }
            }

            publisher.installCommands(
                play: { [weak self] in self?.playPlayer() },
                pause: { [weak self] in self?.pausePlayer() },
                toggle: { [weak self] in self?.playOrPause() })
        }

        func timeControlStatusChanged(_ status: AVPlayer.TimeControlStatus) {
            let waitingReason = player?.reasonForWaitingToPlay?.rawValue ?? "none"
            let message = "timeControlStatus \(status.rawValue); waiting reason \(waitingReason)"
            logger.info("\(message, privacy: .public)")
            let wasPlaying = isPlaying
            isPlaying = status == .playing
            if isPlaying != wasPlaying { onPlayingChange?(isPlaying) }
            snapshot.state = isPlaying ? .playing : .paused
            publisher.publish(snapshot, artwork: currentArtwork)
        }

        /// Records how long it takes, after a request to go back to live, for the new item's clock to start moving, which
        /// is when audio is heard, along with the player's state every two seconds until then.
        private func measureLiveStart(of item: AVPlayerItem) {
            liveTimer.task?.cancel()
            liveTimer.task = Task { [weak self] in await self?.watchLiveStart(of: item, requestedAt: Date()) }
        }

        private func watchLiveStart(of item: AVPlayerItem, requestedAt requested: Date) async {
            DiagnosticLog.app.record("Player", "back to live: requested")
            for tick in 1...80 {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let player, player.currentItem === item else { return }
                let seconds = Date().timeIntervalSince(requested).formatted(.number.precision(.fractionLength(1)))
                let position = player.currentTime().seconds
                if position.isFinite, position > 0.1 {
                    DiagnosticLog.app.record("Player", "back to live: audio moving after \(seconds) s")
                    return
                }
                if tick % 4 == 0 {
                    let reason = player.reasonForWaitingToPlay?.rawValue ?? "none"
                    DiagnosticLog.app.record(
                        "Player",
                        "back to live: \(seconds) s, control \(player.timeControlStatus.rawValue), item \(item.status.rawValue), waiting \(reason)")
                }
            }
            DiagnosticLog.app.record("Player", "back to live: gave up watching after 40 s")
        }

        // MARK: - Now Playing

        /// Tells the system, and the on-screen player, what is on the air.
        /// - Parameter nowPlaying: What the station is broadcasting.
        func updateNowPlaying(_ nowPlaying: NowPlaying) async {
            let next = NowPlayingSnapshot(
                nowPlaying, stationName: stationName, fallbackArtworkURL: fallbackArtworkURL,
                state: isPlaying ? .playing : .paused)
            snapshot = next

            var artwork: CGImage?
            if let url = next.artworkURL { artwork = await artworkLoader.image(for: url) }
            // A newer track arrived while the artwork was loading; leave it to publish.
            guard snapshot.artworkURL == next.artworkURL, snapshot.title == next.title else { return }

            currentArtwork = artwork
            #if !os(macOS)
            player?.currentItem?.externalMetadata = externalMetadata(for: snapshot, artwork: artwork)
            #endif
            publisher.publish(snapshot, artwork: artwork)
        }

        #if !os(macOS)
        private func externalMetadata(for snapshot: NowPlayingSnapshot, artwork: CGImage?) -> [AVMetadataItem] {
            func item(_ identifier: AVMetadataIdentifier, _ value: NSCopying & NSObjectProtocol) -> AVMetadataItem {
                let item = AVMutableMetadataItem()
                item.identifier = identifier
                item.value = value
                return item
            }

            var items = [
                item(.commonIdentifierTitle, snapshot.title as NSString),
                item(.commonIdentifierAlbumName, snapshot.album as NSString),
                item(.commonIdentifierArtist, snapshot.artist as NSString),
            ]
            if let artwork, let data = Self.jpegData(from: artwork) {
                let artworkItem = AVMutableMetadataItem()
                artworkItem.identifier = .commonIdentifierArtwork
                artworkItem.value = data as NSData
                artworkItem.dataType = kCMMetadataBaseDataType_JPEG as String
                items.append(artworkItem)
            }
            return items
        }
        #endif

        /// Encodes artwork as JPEG, the form AVFoundation metadata expects, without going through UIKit or AppKit.
        /// - Returns: The JPEG bytes, or `nil` if the image cannot be encoded.
        static func jpegData(from image: CGImage, quality: Double = 0.8) -> Data? {
            ArtworkThumbnail.jpegData(from: image, quality: quality)
        }

        // MARK: - Playback Control

        func playPlayer() {
            sessionCoordinator.activate()
            player?.play()
        }

        func pausePlayer() {
            player?.pause()
        }

        func playOrPause() {
            isPlaying ? pausePlayer() : playPlayer()
        }

        // MARK: - Archive

        /// Plays an archived show's file in place of the live stream, starting at an offset into it.
        ///
        /// The live stream is replaced, not paused beside it: there is one player, as there is one Now Playing state.
        /// - Parameters:
        ///   - url: The archived audio file.
        ///   - offset: Seconds into the file at which to begin.
        func playArchive(url: URL, at offset: TimeInterval) async {
            guard let player else { return }
            sessionCoordinator.activate()
            let item = AVPlayerItem(url: url)
            replaceItems(with: item)
            isPlayingArchive = true
            await seekArchive(to: offset)
            player.play()
            armEndWatch(for: item)
        }

        /// Moves within the archived file being played.
        /// - Parameter seconds: Seconds from the start of the file.
        func seekArchive(to seconds: TimeInterval) async {
            guard let player, isPlayingArchive else { return }
            let target = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
            await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        /// Puts the live stream back and plays it.
        func returnToLive() {
            guard player != nil, let liveLink else { return }
            endWatch.task?.cancel()
            continuation = nil
            onAdvanced = nil
            let item = AVPlayerItem(url: liveLink)
            item.preferredForwardBufferDuration = 300
            replaceItems(with: item)
            isPlayingArchive = false
            playPlayer()
            measureLiveStart(of: item)
        }

        // MARK: - Hand-off at the end of an archived file

        /// Arms (or, with `nil`, disarms) the hand-off at the end of an archived file.
        ///
        /// About `handoffLead` seconds before the file ends, `provide` is asked what comes next and that is lined up
        /// behind the current item, so the player rolls into it without a gap. `advanced` is called once it has.
        func setContinuation(
            _ provide: (@MainActor () async -> ArchiveContinuation)?,
            advanced: (@MainActor (ArchiveContinuation) async -> Void)?
        ) {
            continuation = provide
            onAdvanced = advanced
            if provide == nil { endWatch.task?.cancel() }
        }

        /// Replaces everything the player holds with one item.
        private func replaceItems(with item: AVPlayerItem) {
            guard let queue = player as? AVQueuePlayer else { return }
            queued = nil
            queue.removeAllItems()
            queue.insert(item, after: nil)
        }

        private func armEndWatch(for item: AVPlayerItem) {
            endWatch.task?.cancel()
            endWatch.task = Task { [weak self] in await self?.watchForEnd(of: item) }
        }

        /// Checks each second whether the archived file is within `handoffLead` of its end, and lines up what is next.
        private func watchForEnd(of item: AVPlayerItem) async {
            // Bounded: six hours of one-second checks is longer than any archived file.
            for _ in 0..<21_600 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let player, player.currentItem === item, isPlayingArchive else { return }
                let duration = item.duration.seconds
                let position = player.currentTime().seconds
                guard duration.isFinite, position.isFinite, duration - position <= Self.handoffLead else { continue }
                guard continuation != nil else { continue }
                await queueHandoff(after: item, duration: duration)
                return
            }
        }

        private func queueHandoff(after item: AVPlayerItem, duration: TimeInterval) async {
            guard let queue = player as? AVQueuePlayer, let provide = continuation else { return }
            let plan = await provide()
            guard queue.currentItem === item, queued == nil else { return }
            let next: AVPlayerItem
            switch plan {
            case .show(_, let url):
                next = AVPlayerItem(url: url)
            case .live:
                guard let liveLink else { return }
                next = AVPlayerItem(url: liveLink)
                next.preferredForwardBufferDuration = 300
            }
            queued = (next, plan)
            queue.insert(next, after: item)
            guard
                case .show(_, let url) = plan,
                let previous = (item.asset as? AVURLAsset)?.url,
                let join = ArchiveTiming.joinOffset(previousFile: previous, previousDuration: duration, nextFile: url)
            else {
                DiagnosticLog.app.record("Player", "hand-off: queued \(plan == .live ? "live" : "the next show") with no join offset")
                return
            }
            let sought = await next.seek(to: CMTime(seconds: join, preferredTimescale: 600))
            DiagnosticLog.app.record("Player", "hand-off: queued the next show, joining at \(Int(join)) s, seek \(sought)")
        }

        /// The player moved to its next item: if that is the one lined up, the show has rolled over.
        private func currentItemChanged(_ item: AVPlayerItem?) {
            guard let item, let lined = queued, item === lined.item else { return }
            queued = nil
            switch lined.plan {
            case .show:
                isPlayingArchive = true
                armEndWatch(for: item)
            case .live:
                isPlayingArchive = false
            }
            DiagnosticLog.app.record("Player", "hand-off: rolled into \(lined.plan == .live ? "live" : "the next show")")
            Task { [weak self] in await self?.finishAdvance(lined.plan) }
        }

        private func finishAdvance(_ plan: ArchiveContinuation) async {
            await onAdvanced?(plan)
        }
    }

/// Holds a task and cancels it when its owner goes away.
private final class TaskHolder {
    var task: Task<Void, Never>?

    deinit {
        task?.cancel()
    }
}
