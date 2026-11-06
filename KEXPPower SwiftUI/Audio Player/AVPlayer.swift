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
    final class PlayerController {

        // MARK: - State

        private(set) var isPlaying = false

        /// Called with the new value whenever the player starts or stops playing.
        @ObservationIgnored var onPlayingChange: (@MainActor (Bool) -> Void)?

        @ObservationIgnored private(set) var player: AVPlayer?
        /// The live stream's address, kept so the player can return to it after an archived show.
        @ObservationIgnored private var liveLink: URL?
        /// Whether the player holds an archived show's file instead of the live stream.
        private(set) var isPlayingArchive = false
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
            let player = AVPlayer(url: link)
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
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            isPlayingArchive = true
            await seekArchive(to: offset)
            player.play()
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
            guard let player, let liveLink else { return }
            let item = AVPlayerItem(url: liveLink)
            item.preferredForwardBufferDuration = 300
            player.replaceCurrentItem(with: item)
            isPlayingArchive = false
            playPlayer()
        }
    }
