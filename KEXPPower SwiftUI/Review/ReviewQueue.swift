//
//  ReviewQueue.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import Observation
import StationKit

/// The songs whose Apple Music match was only a text guess, kept until the listener says yes or no.
///
/// A guess is never added on its own, and it is not lost when the app quits or the listener is driving: it waits here.
@MainActor
@Observable
final class ReviewQueue {
    /// A song to hold, with the links to the two covers to save.
    struct Held {
        let playID: Int
        let playedTitle: String
        let playedArtist: String
        let playedAlbum: String?
        let playedArtworkURL: URL?
        let candidate: CatalogSong
        let candidateArtworkURL: URL?
        let extraPlaylist: PlaylistSummary?
    }

    /// Held songs, newest first.
    private(set) var entries: [ReviewEntry]

    @ObservationIgnored private let store: any ReviewStore
    @ObservationIgnored private let artwork: ReviewArtworkStore
    @ObservationIgnored private let capacity: Int
    @ObservationIgnored private let isSaved: @MainActor (Int) -> Bool

    /// - Parameters:
    ///   - store: Where entries are kept between launches.
    ///   - artwork: Where the covers are kept.
    ///   - capacity: The most entries to hold; the oldest go first. At least one.
    ///   - isSaved: Whether a play is already in the listener's playlists, so it is not held.
    init(
        store: any ReviewStore, artwork: ReviewArtworkStore, capacity: Int = 200,
        isSaved: @escaping @MainActor (Int) -> Bool = { _ in false }
    ) {
        self.store = store
        self.artwork = artwork
        self.capacity = max(1, capacity)
        self.isSaved = isSaved
        entries = store.load()
    }

    /// How many songs are waiting.
    var count: Int { entries.count }

    /// Whether a play is already held.
    func contains(_ playID: Int) -> Bool {
        entries.contains { $0.id == playID }
    }

    /// Holds a song. The entry is saved first, and the covers are fetched afterwards, so a slow or failed download
    /// never delays or loses the song.
    /// - Returns: `false` if it was not held because it was already held or already saved.
    @discardableResult
    func enqueue(_ song: Held) async -> Bool {
        guard !contains(song.playID), !isSaved(song.playID) else { return false }
        let entry = ReviewEntry(
            id: song.playID, playedTitle: song.playedTitle, playedArtist: song.playedArtist, playedAlbum: song.playedAlbum,
            candidateID: song.candidate.id, candidateTitle: song.candidate.title, candidateArtist: song.candidate.artist,
            candidateAlbum: song.candidate.album, extraPlaylistID: song.extraPlaylist?.id,
            extraPlaylistName: song.extraPlaylist?.name, heldAt: Date(), playedArtworkFile: nil, candidateArtworkFile: nil)
        entries.insert(entry, at: 0)
        trimToCapacity()
        store.save(entries)

        async let played = artwork.save(from: song.playedArtworkURL, as: "\(song.playID)-played.jpg")
        async let candidate = artwork.save(from: song.candidateArtworkURL, as: "\(song.playID)-candidate.jpg")
        let files = await (played, candidate)
        // Removed while the covers were downloading (rejected, or pushed out by newer entries): keep nothing.
        guard let index = entries.firstIndex(where: { $0.id == song.playID }) else {
            artwork.remove([files.0, files.1])
            return true
        }
        entries[index].playedArtworkFile = files.0
        entries[index].candidateArtworkFile = files.1
        store.save(entries)
        return true
    }

    /// Saves an entry through `save`, and removes it if that saved the song.
    /// - Parameters:
    ///   - entry: The entry the listener accepted.
    ///   - save: Adds it to the listener's playlists, answering whether it is now saved.
    func add(_ entry: ReviewEntry, save: (ReviewEntry) async -> Bool) async {
        guard await save(entry) else { return }
        remove(entry)
    }

    /// The listener said the suggestion is not the right song.
    func reject(_ entry: ReviewEntry) {
        remove(entry)
    }

    /// Where a saved cover is, or `nil` if the entry has none.
    func artworkFileURL(_ name: String?) -> URL? {
        name.map { artwork.fileURL(for: $0) }
    }

    /// Deletes saved covers that belong to no entry; run at launch.
    func sweepOrphans() {
        let names = entries.flatMap { [$0.playedArtworkFile, $0.candidateArtworkFile] }.compactMap { $0 }
        artwork.sweep(keeping: Set(names))
    }

    private func remove(_ entry: ReviewEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let removed = entries.remove(at: index)
        artwork.remove([removed.playedArtworkFile, removed.candidateArtworkFile])
        store.save(entries)
    }

    private func trimToCapacity() {
        while entries.count > capacity {
            let dropped = entries.removeLast()
            artwork.remove([dropped.playedArtworkFile, dropped.candidateArtworkFile])
        }
    }
}
