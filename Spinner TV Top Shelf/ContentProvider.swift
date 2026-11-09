//
//  ContentProvider.swift
//  Spinner TV Top Shelf
//

import Foundation
import OSLog
import StationKit
import StationKitAdapterKEXP
import TVServices

/// Fills Spinner's Top Shelf with what KEXP is playing: a row of covers, the song on the air first.
///
/// It asks KEXP itself rather than reading what the app saved, so the shelf is current when the app is not running.
/// Each of the three questions may fail on its own; with no answers at all it returns `nil`, and tvOS shows the
/// static Top Shelf image.
final class ContentProvider: TVTopShelfContentProvider {
    private static let logoURL = URL(string: "https://kexp.org/static/assets/img/kexp_logo.jpg")
    private static let logger = Logger(subsystem: "com.JPEnterprises.Spinner.topshelf", category: "ContentProvider")

    /// Runs on the caller's executor, as the superclass method does, so the content it returns never crosses an
    /// isolation boundary; the network requests inside run concurrently on their own.
    nonisolated(nonsending) override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        let station = KEXPStation()
        async let nowPlaying = Self.attempt("what is playing") { try await station.nowPlaying() }
        async let recent = Self.attempt("the recent songs") { try await station.recentTracks(limit: TopShelfRow.maximumTiles) }
        async let program = Self.attempt("the show") { try await station.currentProgram() }
        let row = TopShelfRow.make(
            nowPlaying: await nowPlaying, recent: await recent ?? [], program: await program ?? nil,
            fallbackArtwork: Self.logoURL)
        guard !row.tiles.isEmpty else { return nil }

        let items = row.tiles.map(Self.item(for:))
        let collection = TVTopShelfItemCollection(items: items)
        collection.title = row.title
        return TVTopShelfSectionedContent(sections: [collection])
    }

    /// One square cover: Select opens Spinner, Play starts the live stream.
    private static func item(for tile: TopShelfTile) -> TVTopShelfSectionedItem {
        let item = TVTopShelfSectionedItem(identifier: tile.id)
        item.title = tile.title
        item.imageShape = .square
        item.setImageURL(tile.artworkURL, for: [.screenScale1x, .screenScale2x])
        if let url = SpinnerLink.open.url { item.displayAction = TVTopShelfAction(url: url) }
        if let url = SpinnerLink.playLive.url { item.playAction = TVTopShelfAction(url: url) }
        return item
    }

    /// Runs one request, logging and returning `nil` if it fails, so one failure does not empty the shelf.
    private static func attempt<T: Sendable>(_ what: String, _ request: @Sendable () async throws -> T) async -> T? {
        do {
            return try await request()
        } catch {
            let message = "Top Shelf could not fetch \(what): \(error.localizedDescription)"
            logger.error("\(message, privacy: .public)")
            return nil
        }
    }
}
