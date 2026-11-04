//
//  AppSongSaver.swift
//  KEXPPowerExampleSwiftUI
//

import StationKit

/// Builds the app's saving model: MusicBrainz for ISRCs, Apple Music for the catalog and the playlists, and a
/// ledger that survives relaunch.
enum AppSongSaver {
    /// The name of the playlist every save goes to.
    static let defaultPlaylistName = "KEXP"

    /// Whether this platform can save songs to playlists. MusicKit writes to the library on iOS, iPadOS and visionOS,
    /// but marks those calls unavailable on macOS, so the Mac must not offer the add button.
    static var canSaveToPlaylists: Bool {
        #if os(macOS)
        false
        #else
        true
        #endif
    }

    /// How the app introduces itself to MusicBrainz, which asks clients for a name, a version and a contact.
    static let userAgent = "Spinner/3.2 (https://github.com/jpurnell)"

    /// The model the add buttons use: the saver and the library it saves into.
    @MainActor
    static func makeModel() -> SongSavingModel {
        let playlists = MusicKitPlaylists()
        let saver = SongSaver(
            resolver: SongResolver(
                isrcSource: MusicBrainzISRCSource(userAgent: userAgent),
                catalog: MusicKitCatalog()),
            playlists: playlists,
            ledger: UserDefaultsSaveLedger(),
            defaultPlaylistName: defaultPlaylistName)
        return SongSavingModel(saver: saver, playlists: playlists)
    }
}
