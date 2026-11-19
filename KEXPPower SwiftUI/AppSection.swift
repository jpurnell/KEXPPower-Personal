//
//  AppSection.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import Observation

/// The places the app is divided into: a sidebar on the Mac and iPad, tabs on the iPhone.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case live
    case archive
    case review
    /// The player on its own screen: tvOS only, where a bar beside or beneath each section's content could not be
    /// reached from its list with the remote.
    case nowPlaying

    var id: String { rawValue }

    /// The sections to show. Review holds songs waiting to be added to a playlist, so it is left out where playlists
    /// cannot be saved to (the Mac).
    /// - Parameters:
    ///   - canSaveToPlaylists: Whether this platform can add songs to the listener's playlists.
    ///   - showsNowPlaying: Whether the player has a section of its own (tvOS, once something has played).
    static func visible(canSaveToPlaylists: Bool, showsNowPlaying: Bool = false) -> [AppSection] {
        allCases.filter { section in
            switch section {
            case .review: canSaveToPlaylists
            case .nowPlaying: showsNowPlaying
            case .live, .archive: true
            }
        }
    }

    /// The section the app opens on.
    static let defaultSection = AppSection.live

    var title: String {
        switch self {
        case .live: "Live"
        case .archive: "Archive"
        case .review: "Review"
        case .nowPlaying: "Now Playing"
        }
    }

    /// The SF Symbol shown beside the title.
    var systemImage: String {
        switch self {
        case .live: "dot.radiowaves.left.and.right"
        case .archive: "clock.arrow.circlepath"
        case .review: "tray.full"
        case .nowPlaying: "play.circle"
        }
    }
}

/// Where the app is, as far as a link can move it: the section, a day in the archive, Settings, and a debug panel.
///
/// The views read this and act on it, so a link can reach state that otherwise lives inside a view.
@MainActor @Observable
final class AppNavigation {
    /// The section shown.
    var section: AppSection? = AppSection.defaultSection
    /// A day the archive was asked to open: the start of it in the station's time zone. The Archive takes it once it has its days.
    private(set) var archiveDay: Date?
    /// Whether the Settings sheet is asked for.
    var showingSettings = false
    #if os(iOS) && DEBUG
    /// The debug panel asked for.
    var probe: SpinnerLink.Probe?
    #endif

    /// Moves to a place. Opening the app and playing change nothing: neither is a place.
    /// - Parameter link: The link.
    func go(to link: SpinnerLink) {
        switch link {
        case .open, .playLive: break
        case .live: section = .live
        case .archive: section = .archive
        case .archiveDay(let day):
            section = .archive
            archiveDay = Self.start(of: day)
        case .settings: showingSettings = true
        #if os(iOS) && DEBUG
        case .probe(let probe):
            section = .archive
            self.probe = probe
        #endif
        }
    }

    /// Reads a link that arrived from a notification and moves to it.
    /// - Parameter url: The URL.
    /// - Returns: Whether it was a place this app goes to.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let link = SpinnerLink(notificationURL: url) else { return false }
        go(to: link)
        return true
    }

    /// The day the archive was asked for, once.
    func takeArchiveDay() -> Date? {
        defer { archiveDay = nil }
        return archiveDay
    }

    /// Midnight at the start of `day` in the station's time zone, which is how the archive names a day.
    private static func start(of day: SpinnerLink.Day) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ArchiveTiming.stationTimeZone
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day))
    }
}
