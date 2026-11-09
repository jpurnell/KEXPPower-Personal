//
//  TopShelfContent.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import StationKit

/// One album cover in the Apple TV Top Shelf.
struct TopShelfTile: Equatable, Sendable {
    /// The track's id, which the Top Shelf uses to tell its items apart.
    let id: String
    /// "Song · Artist": a Top Shelf item has one line of text.
    let title: String
    /// The cover, or the station's logo when the song has none.
    let artworkURL: URL?
    /// Whether this is the song on the air now.
    let isOnAir: Bool
}

/// What KEXP is playing, as the row of covers the Top Shelf shows: the song on the air, then the last several.
struct TopShelfRow: Equatable, Sendable {
    /// Above the covers: "Now on KEXP", with the show and host when known.
    let title: String
    let tiles: [TopShelfTile]

    /// The most covers in the row; the Top Shelf shows about five at a time, and a few more to scroll to.
    static let maximumTiles = 10

    /// - Parameters:
    ///   - nowPlaying: What is on the air, or `nil` if it could not be fetched.
    ///   - recent: The latest songs, newest first; it may include the one on the air.
    ///   - program: The show on the air, if known.
    ///   - fallbackArtwork: The cover for a song that has none.
    /// - Returns: The row; with nothing known it has no tiles, and the Top Shelf shows its static image.
    static func make(nowPlaying: NowPlaying?, recent: [Track], program: ProgramInfo?, fallbackArtwork: URL?) -> TopShelfRow {
        var seen = Set<String>()
        var tiles: [TopShelfTile] = []
        let onAir = nowPlaying?.track
        for track in [onAir].compactMap({ $0 }) + recent where tiles.count < maximumTiles && seen.insert(track.id).inserted {
            let artist = track.displayArtist
            tiles.append(TopShelfTile(
                id: track.id,
                title: artist.isEmpty ? track.title : "\(track.title) · \(artist)",
                artworkURL: track.artworkURL ?? fallbackArtwork,
                isOnAir: track.id == onAir?.id))
        }
        return TopShelfRow(title: title(for: program), tiles: tiles)
    }

    private static func title(for program: ProgramInfo?) -> String {
        guard let program else { return "Now on KEXP" }
        guard let host = program.host, !host.isEmpty else { return "Now on KEXP · \(program.title)" }
        return "Now on KEXP · \(program.title) with \(host)"
    }
}

/// The `spinner://` links the Top Shelf opens the app with.
enum SpinnerLink: Equatable, Sendable {
    /// Opens the app as it was.
    case open
    /// Opens the app and plays the live stream.
    case playLive

    static let scheme = "spinner"

    /// `spinner://open` or `spinner://live/play`.
    var url: URL? {
        switch self {
        case .open: URL(string: "\(Self.scheme)://open")
        case .playLive: URL(string: "\(Self.scheme)://live/play")
        }
    }

    /// Reads a link back; `nil` for another scheme or a path this app does not know.
    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        switch (url.host(), url.path()) {
        case ("open", ""): self = .open
        case ("live", "/play"): self = .playLive
        default: return nil
        }
    }
}
