//
//  AppSection.swift
//  KEXPPowerExampleSwiftUI
//

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
