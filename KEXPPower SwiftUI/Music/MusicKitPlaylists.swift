//
//  MusicKitPlaylists.swift
//  KEXPPowerExampleSwiftUI
//

import MusicKit
import StationKit

/// Why a song could not be added to a playlist.
enum MusicKitPlaylistError: Error {
    /// The catalog no longer has the song.
    case songUnavailable
    /// The playlist is no longer in the listener's library.
    case playlistUnavailable
    /// MusicKit cannot write to the library on this platform (it can on iOS, iPadOS and visionOS, not on macOS).
    case notSupportedOnThisPlatform
}

/// The listener's Apple Music library, as StationKit's ``PlaylistService``.
struct MusicKitPlaylists: PlaylistService {
    func requestAccess() async -> PlaylistAccess {
        switch await MusicAuthorization.request() {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }

    func playlists() async throws -> [PlaylistSummary] {
        var request = MusicLibraryRequest<Playlist>()
        request.limit = 500
        let response = try await request.response()
        return response.items.map { PlaylistSummary(id: $0.id.rawValue, name: $0.name) }
    }

    func createPlaylist(named name: String) async throws -> PlaylistSummary {
        #if os(macOS)
        throw MusicKitPlaylistError.notSupportedOnThisPlatform
        #else
        let playlist = try await MusicLibrary.shared.createPlaylist(name: name)
        return PlaylistSummary(id: playlist.id.rawValue, name: playlist.name)
        #endif
    }

    func add(_ song: CatalogSong, to playlist: PlaylistSummary) async throws {
        #if os(macOS)
        throw MusicKitPlaylistError.notSupportedOnThisPlatform
        #else
        let catalogRequest = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(song.id))
        guard let catalogSong = try await catalogRequest.response().items.first else {
            throw MusicKitPlaylistError.songUnavailable
        }

        var libraryRequest = MusicLibraryRequest<Playlist>()
        libraryRequest.filter(matching: \.id, equalTo: MusicItemID(playlist.id))
        guard let libraryPlaylist = try await libraryRequest.response().items.first else {
            throw MusicKitPlaylistError.playlistUnavailable
        }

        _ = try await MusicLibrary.shared.add(catalogSong, to: libraryPlaylist)
        #endif
    }
}
