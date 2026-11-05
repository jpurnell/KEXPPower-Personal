//
//  OpenInMusicModel.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import Observation

/// Finds a song in Apple Music and opens it there, for the platforms (the Mac) where the app cannot add songs to a
/// playlist itself: the listener adds it in Music.
///
/// The song is looked up when asked for, not when it scrolls into view, so a long playlist does not send a request per row.
@MainActor
@Observable
final class OpenInMusicModel {
    /// Where the model is in a request.
    enum State: Equatable {
        /// Nothing pending; the last request, if any, opened a song.
        case idle
        /// A lookup is in flight.
        case looking
        /// The last lookup found nothing in Apple Music.
        case notFound
    }

    /// Looks a song up: artist, track, album. Returns the song's page, or `nil` when there is no match.
    typealias Lookup = @MainActor (_ artist: String, _ track: String, _ album: String) async -> URL?

    private(set) var state = State.idle

    private let lookup: Lookup
    private let opener: @MainActor (URL) -> Void

    /// - Parameters:
    ///   - lookup: How to find a song; the default asks Apple Music's catalog search.
    ///   - open: How to show the song's page.
    init(lookup: @escaping Lookup = OpenInMusicModel.catalogLookup, open: @escaping @MainActor (URL) -> Void) {
        self.lookup = lookup
        self.opener = open
    }

    /// Whether there is a song to look for: an airbreak, or a play with a blank artist or title, has none.
    static func canOpen(artist: String?, track: String?) -> Bool {
        isPresent(artist) && isPresent(track)
    }

    /// Looks the song up and opens it in Apple Music; a miss leaves `state` at `.notFound`.
    func open(artist: String?, track: String?, album: String?) async {
        guard let artist, let track, Self.canOpen(artist: artist, track: track), state != .looking else { return }
        state = .looking
        guard let url = await lookup(artist, track, album ?? "") else {
            state = .notFound
            return
        }
        state = .idle
        opener(url)
    }

    /// What VoiceOver says for the button.
    static func accessibilityLabel(track: String, state: State) -> String {
        switch state {
        case .idle: "Open \(track) in Music"
        case .looking: "Looking for \(track) in Apple Music"
        case .notFound: "\(track) was not found in Apple Music"
        }
    }

    /// The default lookup: Apple's catalog search through the app's network layer.
    static let catalogLookup: Lookup = { artist, track, album in
        let found = try? await AppleMusicRetriever().getAppleMusicResult(artist: artist, track: track, album: album)
        return found ?? nil
    }

    private static func isPresent(_ text: String?) -> Bool {
        guard let text else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
