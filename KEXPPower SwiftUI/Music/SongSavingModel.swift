//
//  SongSavingModel.swift
//  KEXPPowerExampleSwiftUI
//

import KEXPPower
import Observation
import StationKit
import StationKitAdapterKEXP

/// Where one play is in being saved to the listener's playlists.
enum SaveState: Equatable {
    /// Nothing has been tried.
    case idle
    /// Being matched and added.
    case saving
    /// Dealt with: the names of the playlists it was added to, and of those it could not be added to. Both empty
    /// means it was already in every playlist asked for.
    case saved(playlists: [String], failedPlaylists: [String])
    /// Only a text match was found; waiting for the listener to say whether it is the right song.
    case confirming(CatalogSong)
    /// Apple Music has nothing plausible for it.
    case notFound
    /// Apple Music could not be reached.
    case unavailable
    /// The listener has not allowed access to their Apple Music library.
    case needsPermission

    /// The SF Symbol for the button.
    var symbolName: String {
        switch self {
        case .idle: "plus.circle"
        case .saving: "ellipsis.circle"
        case .saved(_, let failed): failed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle"
        case .confirming: "questionmark.circle"
        case .notFound: "xmark.circle"
        case .unavailable: "wifi.exclamationmark"
        case .needsPermission: "lock.circle"
        }
    }

    /// What VoiceOver says for the button.
    var accessibilityLabel: String {
        switch self {
        case .idle: "Add to playlist"
        case .saving: "Adding to playlist"
        case .saved(let added, let failed):
            switch (added.isEmpty, failed.isEmpty) {
            case (true, true): "Already in your playlists"
            case (false, true): "Added to \(added.formatted(.list(type: .and)))"
            case (true, false): "Could not add to \(failed.formatted(.list(type: .and)))"
            case (false, false):
                "Added to \(added.formatted(.list(type: .and))); could not add to \(failed.formatted(.list(type: .and)))"
            }
        case .confirming: "Confirm the match"
        case .notFound: "No match found in Apple Music"
        case .unavailable: "Apple Music is unavailable"
        case .needsPermission: "Allow access to Apple Music"
        }
    }
}

/// Follows each play through being saved, and offers the playlists to choose from.
@MainActor
@Observable
final class SongSavingModel {
    typealias Save = @Sendable (Track, PlaylistSummary?) async -> SaveOutcome
    typealias Confirm = @Sendable (CatalogSong, PlaylistSummary?) async -> SaveOutcome
    typealias LoadPlaylists = @Sendable () async throws -> [PlaylistSummary]
    typealias CreatePlaylist = @Sendable (String) async throws -> PlaylistSummary

    /// The playlists the listener can also add to, known once access has been given.
    private(set) var playlistChoices: [PlaylistSummary] = []
    private var states: [Int: SaveState] = [:]
    @ObservationIgnored private var pendingExtras: [Int: PlaylistSummary] = [:]
    @ObservationIgnored private let saveTrack: Save
    @ObservationIgnored private let confirmSong: Confirm
    @ObservationIgnored private let loadPlaylists: LoadPlaylists
    @ObservationIgnored private let createPlaylist: CreatePlaylist

    /// - Parameters:
    ///   - save: Saves a track, optionally to a second playlist.
    ///   - confirm: Saves a song the listener confirmed.
    ///   - loadPlaylists: The listener's playlists.
    ///   - createPlaylist: Makes a new playlist.
    init(
        save: @escaping Save, confirm: @escaping Confirm, loadPlaylists: @escaping LoadPlaylists,
        createPlaylist: @escaping CreatePlaylist = { _ in throw CancellationError() }
    ) {
        saveTrack = save
        confirmSong = confirm
        self.loadPlaylists = loadPlaylists
        self.createPlaylist = createPlaylist
    }

    /// The model for the app: a saver and the library it saves into.
    convenience init(saver: SongSaver, playlists: any PlaylistService) {
        self.init(
            save: { await saver.save($0, alsoTo: $1) },
            confirm: { await saver.confirm($0, alsoTo: $1) },
            loadPlaylists: { try await playlists.playlists() },
            createPlaylist: { try await playlists.createPlaylist(named: $0) })
    }

    /// Whether a play is a song that can be saved: not an airbreak, and with a title and an id.
    static func canSave(_ play: Play?) -> Bool {
        guard let play else { return false }
        return play.id != nil && KEXPMapping.track(from: play) != nil
    }

    /// Where a play is in being saved.
    func state(for play: Play) -> SaveState {
        play.id.flatMap { states[$0] } ?? .idle
    }

    /// Saves a play to the default playlist, and to a second one if given.
    /// - Parameters:
    ///   - play: The play to save; airbreaks and plays without an id are ignored.
    ///   - extra: A second playlist to add it to as well.
    func save(_ play: Play, alsoTo extra: PlaylistSummary? = nil) async {
        guard Self.canSave(play), let id = play.id, let track = KEXPMapping.track(from: play) else { return }
        guard states[id] != .saving else { return }
        states[id] = .saving
        let outcome = await saveTrack(track, extra)
        apply(outcome, to: id, extra: extra)
        if outcome != .notAuthorized { await refreshPlaylistChoices() }
    }

    /// Makes a playlist with a name and saves a play to it as well as to the default one.
    /// - Parameters:
    ///   - play: The play to save.
    ///   - name: The new playlist's name; blank names are ignored.
    func save(_ play: Play, toNewPlaylistNamed name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let id = play.id, KEXPMapping.track(from: play) != nil else { return }
        do {
            let made = try await createPlaylist(trimmed)
            await save(play, alsoTo: made)
        } catch {
            states[id] = .unavailable
        }
    }

    /// Saves the song the listener confirmed after a text match.
    func confirm(_ song: CatalogSong, for play: Play, alsoTo extra: PlaylistSummary? = nil) async {
        guard let id = play.id else { return }
        let second = extra ?? pendingExtras[id]
        states[id] = .saving
        let outcome = await confirmSong(song, second)
        apply(outcome, to: id, extra: second)
    }

    /// The listener said the suggested song is not the right one.
    func dismissConfirmation(for play: Play) {
        guard let id = play.id, case .confirming = states[id] else { return }
        states[id] = nil
        pendingExtras[id] = nil
    }

    /// The playlists to offer, or none if the library cannot be read.
    func playlists() async -> [PlaylistSummary] {
        do {
            return try await loadPlaylists()
        } catch {
            return []
        }
    }

    private func refreshPlaylistChoices() async {
        playlistChoices = await playlists()
    }

    private func apply(_ outcome: SaveOutcome, to id: Int, extra: PlaylistSummary?) {
        pendingExtras[id] = nil
        switch outcome {
        case .finished(_, let added, let failed):
            states[id] = .saved(playlists: added.map(\.name), failedPlaylists: failed.map(\.name))
        case .alreadySaved:
            states[id] = .saved(playlists: [], failedPlaylists: [])
        case .needsConfirmation(let song):
            states[id] = .confirming(song)
            pendingExtras[id] = extra
        case .notFound: states[id] = .notFound
        case .unavailable: states[id] = .unavailable
        case .notAuthorized: states[id] = .needsPermission
        }
    }
}
