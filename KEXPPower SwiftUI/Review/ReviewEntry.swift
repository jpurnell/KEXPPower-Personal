//
//  ReviewEntry.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import StationKit

/// One song held for the listener to check: what KEXP played, and the Apple Music version it was matched to by text.
struct ReviewEntry: Codable, Equatable, Identifiable, Sendable {
    /// The KEXP play this came from; one entry per play.
    let id: Int
    let playedTitle: String
    let playedArtist: String
    let playedAlbum: String?
    let candidateID: String
    let candidateTitle: String
    let candidateArtist: String
    let candidateAlbum: String?
    /// The second playlist the listener chose when pressing add, if any, so confirming adds to it as well.
    let extraPlaylistID: String?
    let extraPlaylistName: String?
    let heldAt: Date
    /// File names in the review artwork folder, `nil` when the picture could not be fetched.
    var playedArtworkFile: String?
    var candidateArtworkFile: String?

    /// The Apple Music suggestion, as the saver expects it.
    var candidate: CatalogSong {
        CatalogSong(id: candidateID, title: candidateTitle, artist: candidateArtist, album: candidateAlbum)
    }

    /// The second playlist to add to, when one was chosen.
    var extraPlaylist: PlaylistSummary? {
        guard let extraPlaylistID, let extraPlaylistName else { return nil }
        return PlaylistSummary(id: extraPlaylistID, name: extraPlaylistName)
    }
}

/// Where the queue keeps its entries between launches.
@MainActor
protocol ReviewStore {
    /// The saved entries, or none if nothing is saved or what is saved cannot be read.
    func load() -> [ReviewEntry]
    /// Replaces what is saved.
    func save(_ entries: [ReviewEntry])
}
