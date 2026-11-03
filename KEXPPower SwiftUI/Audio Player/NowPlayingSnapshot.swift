//
//  NowPlayingSnapshot.swift
//  KEXPPowerExampleSwiftUI
//

import MediaPlayer
import UIKit

/// What the system should be told about playback: pure data, no framework state.
struct NowPlayingSnapshot: Equatable, Sendable {
    enum PlaybackState: Equatable, Sendable {
        case playing
        case paused
    }

    static let kexpLogoURLString = "https://kexp.org/static/assets/img/kexp_logo.jpg"

    var title: String
    var artist: String
    var album: String
    var artworkURLString: String
    var isLive = true
    var state: PlaybackState

    /// - Parameters:
    ///   - song: The track title; an airbreak has none.
    ///   - artist: The artist; defaults to the station.
    ///   - album: The album; defaults to empty.
    ///   - imageURI: Artwork URL; defaults to the KEXP logo.
    ///   - state: Whether playback is running.
    init(song: String?, artist: String?, album: String?, imageURI: String?, state: PlaybackState) {
        self.title = Self.nonEmpty(song) ?? "Airbreak"
        self.artist = Self.nonEmpty(artist) ?? "KEXP"
        self.album = Self.nonEmpty(album) ?? ""
        self.artworkURLString = Self.nonEmpty(imageURI) ?? Self.kexpLogoURLString
        self.state = state
    }

    /// The dictionary for `MPNowPlayingInfoCenter`.
    /// - Parameter artwork: Loaded artwork; omitted from the result when `nil`.
    func nowPlayingInfo(artwork: UIImage?) -> [String: Any] {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyAlbumTitle: album,
            MPNowPlayingInfoPropertyIsLiveStream: isLive,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0,
        ]
        if let artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        }
        return info
    }

    private static func nonEmpty(_ string: String?) -> String? {
        guard let string, !string.isEmpty else { return nil }
        return string
    }
}
