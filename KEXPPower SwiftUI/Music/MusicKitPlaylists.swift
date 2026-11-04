//
//  MusicKitPlaylists.swift
//  KEXPPowerExampleSwiftUI
//

import MusicKit
import OSLog
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
        do {
            let playlist = try await MusicLibrary.shared.createPlaylist(name: name)
            return PlaylistSummary(id: playlist.id.rawValue, name: playlist.name)
        } catch {
            await logFailure("creating a playlist", error)
            throw error
        }
        #endif
    }

    func add(_ song: CatalogSong, to playlist: PlaylistSummary) async throws {
        #if os(macOS)
        throw MusicKitPlaylistError.notSupportedOnThisPlatform
        #else
        var stage = "finding the song in the catalog"
        do {
            let catalogRequest = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(song.id))
            guard let catalogSong = try await catalogRequest.response().items.first else {
                throw MusicKitPlaylistError.songUnavailable
            }

            stage = "finding the playlist in the library"
            var libraryRequest = MusicLibraryRequest<Playlist>()
            libraryRequest.filter(matching: \.id, equalTo: MusicItemID(playlist.id))
            guard let libraryPlaylist = try await libraryRequest.response().items.first else {
                throw MusicKitPlaylistError.playlistUnavailable
            }

            stage = "adding the song to the playlist"
            _ = try await MusicLibrary.shared.add(catalogSong, to: libraryPlaylist)
        } catch {
            await logFailure(stage, error)
            throw error
        }
        #endif
    }

    /// Records what MusicKit actually said, and the account state that usually explains it, because MusicKit's own
    /// description of these failures is often just "An unknown error occurred".
    private func logFailure(_ stage: String, _ error: any Error) async {
        let logger = Logger()
        let authorization = String(describing: MusicAuthorization.currentStatus)
        var account = "subscription unknown"
        do {
            let subscription = try await MusicSubscription.current
            account = "can play catalog: \(subscription.canPlayCatalogContent), can become subscriber: "
                + "\(subscription.canBecomeSubscriber), cloud library: \(subscription.hasCloudLibraryEnabled)"
        } catch {
            account = "subscription lookup failed: \(String(reflecting: error))"
        }
        let message = "MusicKit failed while \(stage): \(String(reflecting: error)); authorization \(authorization); \(account)"
        logger.error("\(message, privacy: .public)")
    }
}
