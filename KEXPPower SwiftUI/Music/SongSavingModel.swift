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
    /// Only a text match was found, and it was put in the review queue to be checked later, not guessed at.
    case heldForReview

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
        case .heldForReview: "tray.full"
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
        case .heldForReview: "Saved to review later"
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
    /// Where text matches are held for the listener to check later; without one they are asked about at once.
    @ObservationIgnored var reviewQueue: ReviewQueue?
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

    /// The KEXP play a track came from: the adapter names tracks `kexp-<play id>`. Saved state is kept by play, so a
    /// song saved on Live and the same song in the archive are one.
    static func playID(of track: Track) -> Int? {
        guard track.id.hasPrefix("kexp-") else { return nil }
        return Int(track.id.dropFirst("kexp-".count))
    }

    /// Whether a track can be saved: it came from a KEXP play.
    static func canSave(_ track: Track) -> Bool {
        playID(of: track) != nil
    }

    /// Where a play is in being saved.
    func state(for play: Play) -> SaveState {
        play.id.flatMap { states[$0] } ?? .idle
    }

    /// Where a track is in being saved.
    func state(for track: Track) -> SaveState {
        Self.playID(of: track).flatMap { states[$0] } ?? .idle
    }

    /// Whether a play is already in the listener's playlists, so it need not be held for review.
    func isSaved(playID: Int) -> Bool {
        if case .saved = states[playID] { return true }
        return false
    }

    /// Saves a play to the default playlist, and to a second one if given.
    /// - Parameters:
    ///   - play: The play to save; airbreaks and plays without an id are ignored.
    ///   - extra: A second playlist to add it to as well.
    ///   - holdingGuesses: `true` from the car: a text match is put in the review queue instead of asking, because
    ///     nobody can answer a prompt while driving. An exact match is added either way.
    func save(_ play: Play, alsoTo extra: PlaylistSummary? = nil, holdingGuesses: Bool = false) async {
        guard Self.canSave(play), let track = KEXPMapping.track(from: play) else { return }
        await save(track, alsoTo: extra, holdingGuesses: holdingGuesses)
    }

    /// Saves a track to the default playlist, and to a second one if given.
    /// - Parameters:
    ///   - track: The song to save; one that did not come from a KEXP play is ignored.
    ///   - extra: A second playlist to add it to as well.
    ///   - holdingGuesses: As for a play.
    func save(_ track: Track, alsoTo extra: PlaylistSummary? = nil, holdingGuesses: Bool = false) async {
        guard let id = Self.playID(of: track) else { return }
        guard states[id] != .saving else { return }
        states[id] = .saving
        let outcome = await saveTrack(track, extra)
        apply(outcome, to: id, extra: extra)
        if holdingGuesses, case .needsConfirmation(let song) = outcome {
            await holdForReview(song, for: track)
        }
        if outcome != .notAuthorized { await refreshPlaylistChoices() }
    }

    /// Puts a suggested match in the review queue, to be checked later.
    ///
    /// Without a queue the suggestion stays as a question, so it is never lost.
    /// - Parameters:
    ///   - song: Apple Music's suggestion.
    ///   - play: The KEXP play it was matched to.
    func holdForReview(_ song: CatalogSong, for play: Play) async {
        guard let track = KEXPMapping.track(from: play) else { return }
        await holdForReview(song, for: track)
    }

    /// Puts a suggested match for a track in the review queue, to be checked later.
    func holdForReview(_ song: CatalogSong, for track: Track) async {
        guard let id = Self.playID(of: track), let queue = reviewQueue else { return }
        let held = ReviewQueue.Held(
            playID: id, playedTitle: track.title, playedArtist: track.displayArtist, playedAlbum: track.album,
            playedArtworkURL: track.artworkURL, candidate: song,
            extraPlaylist: pendingExtras[id])
        await queue.enqueue(held)
        states[id] = .heldForReview
        pendingExtras[id] = nil
    }

    /// Saves the suggestion for a song in the review queue.
    /// - Returns: Whether the song is now in the listener's playlists; if not it stays in the queue.
    func confirmHeld(_ entry: ReviewEntry) async -> Bool {
        states[entry.id] = .saving
        let outcome = await confirmSong(entry.candidate, entry.extraPlaylist)
        apply(outcome, to: entry.id, extra: entry.extraPlaylist)
        if case .saved = states[entry.id] { return true }
        states[entry.id] = .heldForReview
        return false
    }

    /// The listener rejected a held suggestion; the play can be saved again from scratch.
    func releaseHeld(_ entry: ReviewEntry) {
        states[entry.id] = nil
        pendingExtras[entry.id] = nil
    }

    /// Makes a playlist with a name and saves a play to it as well as to the default one.
    /// - Parameters:
    ///   - play: The play to save.
    ///   - name: The new playlist's name; blank names are ignored.
    func save(_ play: Play, toNewPlaylistNamed name: String) async {
        guard let track = KEXPMapping.track(from: play) else { return }
        await save(track, toNewPlaylistNamed: name)
    }

    /// Makes a playlist with a name and saves a track to it as well as to the default one.
    func save(_ track: Track, toNewPlaylistNamed name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let id = Self.playID(of: track) else { return }
        do {
            let made = try await createPlaylist(trimmed)
            await save(track, alsoTo: made)
        } catch {
            states[id] = .unavailable
        }
    }

    /// Saves the song the listener confirmed after a text match.
    func confirm(_ song: CatalogSong, for play: Play, alsoTo extra: PlaylistSummary? = nil) async {
        guard let id = play.id else { return }
        await confirm(song, playID: id, alsoTo: extra)
    }

    /// Saves the song the listener confirmed for a track after a text match.
    func confirm(_ song: CatalogSong, for track: Track, alsoTo extra: PlaylistSummary? = nil) async {
        guard let id = Self.playID(of: track) else { return }
        await confirm(song, playID: id, alsoTo: extra)
    }

    private func confirm(_ song: CatalogSong, playID id: Int, alsoTo extra: PlaylistSummary?) async {
        let second = extra ?? pendingExtras[id]
        states[id] = .saving
        let outcome = await confirmSong(song, second)
        apply(outcome, to: id, extra: second)
    }

    /// The listener said the suggested song is not the right one.
    func dismissConfirmation(for play: Play) {
        guard let id = play.id else { return }
        dismissConfirmation(playID: id)
    }

    /// The listener said the suggested song for a track is not the right one.
    func dismissConfirmation(for track: Track) {
        guard let id = Self.playID(of: track) else { return }
        dismissConfirmation(playID: id)
    }

    private func dismissConfirmation(playID id: Int) {
        guard case .confirming = states[id] else { return }
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
