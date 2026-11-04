//
//  AppSection.swift
//  KEXPPowerExampleSwiftUI
//

/// The places the app is divided into: a sidebar on the Mac and iPad, tabs on the iPhone.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case live
    case archive
    case playlists

    var id: String { rawValue }

    /// The section the app opens on.
    static let defaultSection = AppSection.live

    var title: String {
        switch self {
        case .live: "Live"
        case .archive: "Archive"
        case .playlists: "Playlists"
        }
    }

    /// The SF Symbol shown beside the title.
    var systemImage: String {
        switch self {
        case .live: "dot.radiowaves.left.and.right"
        case .archive: "clock.arrow.circlepath"
        case .playlists: "music.note.list"
        }
    }

    /// Whether the section is built yet.
    var isAvailable: Bool { self == .live }

    /// What to tell the listener about a section that is not built yet, or `nil` once it is.
    var comingSoonMessage: String? {
        switch self {
        case .live: nil
        case .archive: "Listen to a show from the last two weeks, from any point in it."
        case .playlists: "Save the songs you hear to a KEXP playlist in Apple Music."
        }
    }
}
