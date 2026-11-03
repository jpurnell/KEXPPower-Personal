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
import OSLog
import UIKit

#if os(iOS) || os(visionOS)

    /// Owns the live-stream `AVPlayer` and reports it to the system through a single publisher.
    ///
    /// `isPlaying` mirrors the player's own `timeControlStatus`; it is never toggled by hand, so a
    /// remote command, an interruption, or a route change cannot leave it out of step.
    @MainActor
    final class PlayerController: ObservableObject {

        // MARK: - State

        @Published private(set) var isPlaying = false

        private(set) var player: AVPlayer?
        let avPlayerViewController = AVPlayerViewController()

        private var snapshot = NowPlayingSnapshot(song: nil, artist: nil, album: nil, imageURI: nil, state: .paused)
        private var currentArtwork: UIImage?
        private var statusObservation: AnyCancellable?

        private let artworkLoader: ArtworkLoader
        private let publisher: any NowPlayingPublishing
        private let logger = Logger(#function)

        init(
            artworkLoader: ArtworkLoader = ArtworkLoader(),
            publisher: any NowPlayingPublishing = LegacyNowPlayingPublisher()
        ) {
            self.artworkLoader = artworkLoader
            self.publisher = publisher
        }

        // MARK: - Setup

        /// Creates the player for a stream and starts reporting it to the system.
        /// - Parameter link: The live-stream URL.
        func initPlayer(link: URL) {
            logger.debug("Initiating PlayerController")

            let player = AVPlayer(url: link)
            player.allowsExternalPlayback = true
            player.currentItem?.preferredForwardBufferDuration = 300
            self.player = player

            avPlayerViewController.player = player
            avPlayerViewController.showsPlaybackControls = true
            // The publisher is the only writer of Now Playing state.
            avPlayerViewController.updatesNowPlayingInfoCenter = false

            statusObservation = player.publisher(for: \.timeControlStatus)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] status in
                    MainActor.assumeIsolated { self?.timeControlStatusChanged(status) }
                }

            publisher.installCommands(
                play: { [weak self] in self?.playPlayer() },
                pause: { [weak self] in self?.pausePlayer() },
                toggle: { [weak self] in self?.playOrPause() })
        }

        private func timeControlStatusChanged(_ status: AVPlayer.TimeControlStatus) {
            isPlaying = status == .playing
            snapshot.state = isPlaying ? .playing : .paused
            publisher.publish(snapshot, artwork: currentArtwork)
        }

        // MARK: - Now Playing

        /// Tells the system, and the on-screen player, what is on the air.
        /// - Parameters:
        ///   - song: The track title, or `nil` during an airbreak.
        ///   - artist: The artist.
        ///   - album: The album.
        ///   - imageURI: Artwork URL.
        func updateNowPlaying(song: String?, artist: String?, album: String?, imageURI: String?) async {
            let next = NowPlayingSnapshot(
                song: song, artist: artist, album: album, imageURI: imageURI,
                state: isPlaying ? .playing : .paused)
            snapshot = next

            let artwork = await artworkLoader.image(for: next.artworkURLString)
            // A newer track arrived while the artwork was loading; leave it to publish.
            guard snapshot.artworkURLString == next.artworkURLString, snapshot.title == next.title else { return }

            currentArtwork = artwork
            player?.currentItem?.externalMetadata = externalMetadata(for: snapshot, artwork: artwork)
            publisher.publish(snapshot, artwork: artwork)
        }

        private func externalMetadata(for snapshot: NowPlayingSnapshot, artwork: UIImage?) -> [AVMetadataItem] {
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
            if let data = artwork?.jpegData(compressionQuality: 0.8) {
                let artworkItem = AVMutableMetadataItem()
                artworkItem.identifier = .commonIdentifierArtwork
                artworkItem.value = data as NSData
                artworkItem.dataType = kCMMetadataBaseDataType_JPEG as String
                items.append(artworkItem)
            }
            return items
        }

        // MARK: - Playback Control

        func playPlayer() {
            try? AVAudioSession.sharedInstance().setActive(true)
            player?.play()
        }

        func pausePlayer() {
            player?.pause()
        }

        func playOrPause() {
            isPlaying ? pausePlayer() : playPlayer()
        }
    }
#endif
