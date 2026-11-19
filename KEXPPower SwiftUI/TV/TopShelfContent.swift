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

/// The `spinner://` links the app reads: the Top Shelf's, and the ones a notification carries (DeepLinks).
///
/// A link names a place or asks for one thing. **A place navigates and never acts**: a notification can be tapped by accident and a
/// link replayed, so what arrives from one is read with ``init(notificationURL:)``, which refuses every link that acts. The Top
/// Shelf, where the person pressed Play, reads them all with ``init(url:)``.
enum SpinnerLink: Equatable, Sendable {
    /// Opens the app as it was.
    case open
    /// Goes to the Live section, and starts nothing.
    case live
    /// Opens the app and plays the live stream.
    case playLive
    /// Goes to the Archive section.
    case archive
    /// Goes to one day in the archive.
    case archiveDay(Day)
    /// Opens Settings, where the platform has them as a sheet (the Mac's Settings window is its own scene).
    case settings
    #if os(iOS) && DEBUG
    /// Opens one of the debug panels. They are compiled out of a release build, so the link is not read there.
    case probe(Probe)
    #endif

    /// Whether a link goes somewhere or does something.
    enum Kind: Sendable {
        /// Goes to a place.
        case navigate
        /// Does something, such as starting audio.
        case act
    }

    /// A calendar day, as the archive names it: the station's, written year-month-day.
    struct Day: Equatable, Sendable {
        let year: Int
        let month: Int
        let day: Int

        /// - Returns: `nil` if the date does not exist (30 February).
        init?(year: Int, month: Int, day: Int) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
            guard DateComponents(calendar: calendar, year: year, month: month, day: day).isValidDate(in: calendar) else { return nil }
            self.year = year
            self.month = month
            self.day = day
        }

        /// Reads `2026-11-18` and nothing looser: four digits, two, two.
        init?(_ text: some StringProtocol) {
            let parts = text.split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
                  parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
                  let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
            self.init(year: year, month: month, day: day)
        }

        /// `2026-11-18`.
        var text: String { "\(Self.padded(year, to: 4))-\(Self.padded(month, to: 2))-\(Self.padded(day, to: 2))" }

        private static func padded(_ number: Int, to width: Int) -> String {
            let digits = String(number)
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
    }

    #if os(iOS) && DEBUG
    /// The debug panels a link can open.
    enum Probe: String, Sendable {
        case archive
        case live
    }
    #endif

    static let scheme = "spinner"

    /// What the link does: only playing acts.
    var kind: Kind { self == .playLive ? .act : .navigate }

    /// `spinner://open`, `spinner://live`, `spinner://live/play`, `spinner://archive`, `spinner://archive/2026-11-18`,
    /// `spinner://settings`.
    var url: URL? {
        let rest: String
        switch self {
        case .open: rest = "open"
        case .live: rest = "live"
        case .playLive: rest = "live/play"
        case .archive: rest = "archive"
        case .archiveDay(let day): rest = "archive/\(day.text)"
        case .settings: rest = "settings"
        #if os(iOS) && DEBUG
        case .probe(let probe): rest = "probe/\(probe.rawValue)"
        #endif
        }
        return URL(string: "\(Self.scheme)://\(rest)")
    }

    /// Reads any link; `nil` for another scheme or a place this app does not know. For a link the Top Shelf made.
    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        let path = url.path()
        switch (url.host(), path) {
        case ("open", ""): self = .open
        case ("live", ""): self = .live
        case ("live", "/play"): self = .playLive
        case ("archive", ""): self = .archive
        case ("archive", _) where path.hasPrefix("/"):
            guard let day = Day(path.dropFirst()) else { return nil }
            self = .archiveDay(day)
        case ("settings", ""): self = .settings
        #if os(iOS) && DEBUG
        case ("probe", _) where path.hasPrefix("/"):
            guard let probe = Probe(rawValue: String(path.dropFirst())) else { return nil }
            self = .probe(probe)
        #endif
        default: return nil
        }
    }

    /// Reads a link that arrived from a notification: a place, never an action.
    init?(notificationURL url: URL) {
        guard let link = SpinnerLink(url: url), link.kind == .navigate else { return nil }
        self = link
    }
}
