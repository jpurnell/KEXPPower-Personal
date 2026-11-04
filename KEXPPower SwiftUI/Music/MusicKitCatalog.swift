//
//  MusicKitCatalog.swift
//  KEXPPowerExampleSwiftUI
//

import MusicKit
import StationKit

/// The Apple Music catalog, as StationKit's ``CatalogLookup``.
struct MusicKitCatalog: CatalogLookup {
    func song(isrc: String) async throws -> CatalogSong? {
        let request = MusicCatalogResourceRequest<Song>(matching: \.isrc, equalTo: isrc)
        let response = try await request.response()
        return response.items.first.map(CatalogSong.init)
    }

    func search(title: String, artist: String, album: String?) async throws -> [CatalogSong] {
        var request = MusicCatalogSearchRequest(term: "\(title) \(artist)", types: [Song.self])
        request.limit = 10
        let response = try await request.response()
        return response.songs.map(CatalogSong.init)
    }
}

private extension CatalogSong {
    init(_ song: Song) {
        self.init(id: song.id.rawValue, title: song.title, artist: song.artistName, album: song.albumTitle)
    }
}
