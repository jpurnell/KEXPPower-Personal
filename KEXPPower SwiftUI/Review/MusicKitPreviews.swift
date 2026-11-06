//
//  MusicKitPreviews.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import MusicKit

/// Finds the 30-second preview Apple Music offers for a song.
enum MusicKitPreviews {
    /// The preview link for an Apple Music song id, or `nil` if the song has none or cannot be looked up.
    static func url(forSongID id: String) async -> URL? {
        let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(id))
        guard let response = try? await request.response() else { return nil }
        return response.items.first?.previewAssets?.first?.url
    }
}
