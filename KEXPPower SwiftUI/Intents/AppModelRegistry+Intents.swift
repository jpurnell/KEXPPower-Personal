//
//  AppModelRegistry+Intents.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import StationKit

/// What Siri and Shortcuts ask of the app, each answered with the sentence to speak.
///
/// An intent can launch the app in the background before any window exists, so every entry point begins by checking the
/// app has made its model, and says so if it has not.
extension AppModelRegistry {
    private static let diagnostics = DiagnosticLog.app

    /// Spoken when an intent arrives before the app has made its player.
    static let notReady = "Spinner is not ready. Try again in a moment."

    /// Plays the live stream; from an archived show, goes back to live first.
    static func playLive() async -> String {
        guard model != nil else { return notReady }
        if archive?.nowPlayingShow != nil { archive?.returnToLive() }
        await setPlayback(true)
        return "Playing KEXP live."
    }

    /// Pauses whatever plays.
    static func pause() -> String {
        guard let model else { return notReady }
        if model.playerController.isPlaying { model.playerController.pausePlayer() }
        return "Paused."
    }

    /// Spoken when the station's playlist has not loaded, so no song can be named.
    static let playlistUnavailable = "KEXP's playlist could not be reached. Try again in a moment."

    /// The song on the air, or the one heard from an archived show, as a sentence. A cold launch has no playlist yet, so
    /// this waits for the first one.
    static func whatsPlaying() async -> String {
        guard let model else { return notReady }
        if archive?.nowPlayingShow == nil { await model.firstResults() }
        let said = nowPlayingSentence()
        diagnostics.record("Siri", "whats playing: \(said)")
        return said
    }

    /// The sentence for what is playing now, from what has loaded: the station's own play, never a placeholder.
    static func nowPlayingSentence() -> String {
        guard let model else { return notReady }
        let player = model.playerController
        if let archive, let show = archive.nowPlayingShow {
            let song = archive.heardTrack.map { IntentSpeech.Song(title: $0.title, artist: $0.displayArtist) }
            return IntentSpeech.whatsPlaying(
                song: song, show: show.programName, hosts: show.hostNames, isPlaying: player.isPlaying, fromArchive: true)
        }
        guard let play = model.plays.first else { return playlistUnavailable }
        let summary = NowPlayingSummary(play)
        let song = summary.title == NowPlayingSummary.airbreakTitle
            ? nil : IntentSpeech.Song(title: summary.title, artist: summary.artist)
        let isShowKnown = model.show.programName != ResultRetriever.retrievingName
        return IntentSpeech.whatsPlaying(
            song: song, show: isShowKnown ? model.show.programName : nil, hosts: isShowKnown ? model.show.hostNames ?? [] : [],
            isPlaying: player.isPlaying, fromArchive: false)
    }

    /// Catches up to live from a rewind or an archived show.
    static func backToLive() async -> String {
        guard let model else { return notReady }
        if archive?.nowPlayingShow != nil {
            archive?.returnToLive()
            return "Back to live."
        }
        guard model.playerController.isTimeShifted, let window = model.playerController.liveWindow, !window.isLive else {
            return "You are already listening live."
        }
        await model.playerController.goFullyLive()
        return "Back to live."
    }

    /// Goes back by the rewind step, if live is playing through the recording.
    /// - Parameter window: The rewind window in Settings.
    static func rewind(window: RewindWindow = ListeningSettings.current().window) async -> String {
        guard let model else { return notReady }
        let player = model.playerController
        if let refusal = IntentSpeech.rewindRefusal(
            window: window, isLiveShifted: player.isTimeShifted, isArchive: player.isPlayingArchive)
        {
            return refusal
        }
        let minutes = Int((player.rewindStep / 60).rounded())
        await player.rewindLive()
        return "Back \(minutes) minutes."
    }

    #if !os(macOS)
    /// Adds the song heard to the listener's playlist, waiting for the first playlist on a cold launch.
    static func addSong() async -> String {
        guard model != nil, saving != nil else { return notReady }
        if archive?.nowPlayingShow == nil { await model?.firstResults() }
        return await addLoadedSong()
    }

    /// Adds the song heard from what has loaded. A text match is held for review instead of asked about, as in the car,
    /// because nobody can answer a prompt by voice. Before the playlist has loaded there is no song to add: the
    /// placeholder shown meanwhile is not the one on the air.
    static func addLoadedSong() async -> String {
        guard let model, let saving else { return notReady }
        if let archive, archive.nowPlayingShow != nil {
            guard let track = archive.heardTrack, SongSavingModel.canSave(track) else { return noSongToAdd }
            await saving.save(track, holdingGuesses: true)
            return IntentSpeech.saved(saving.state(for: track), title: track.title)
        }
        guard let play = model.plays.first, SongSavingModel.canSave(play) else { return noSongToAdd }
        await saving.save(play, holdingGuesses: true)
        let said = IntentSpeech.saved(saving.state(for: play), title: NowPlayingSummary(play).title)
        diagnostics.record("Siri", "add song: \(said)")
        return said
    }

    /// Spoken when there is no song to add: between songs, or before the first of an archived show.
    static let noSongToAdd = "No song is playing to add."
    #endif

    // MARK: Archived shows

    /// Loads the archive unless it is loaded, so a list that failed or is still loading is tried again.
    private static func loadedArchiveShows() async -> [StationKit.ArchiveShow] {
        guard let archive else { return [] }
        if archive.phase != .loaded { await archive.load() }
        return archive.tiles.flatMap(\.shows)
    }

    /// The shows a spoken phrase means, newest first, at most five. Dates are read in the zone times are shown in.
    /// - Parameter phrase: What the listener said, such as "afternoon show from november 4th".
    static func showsMatching(_ phrase: String) async -> [StationKit.ArchiveShow] {
        let shows = await loadedArchiveShows()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shownZone
        let found = ShowMatching.matches(phrase, in: shows, limit: 5, calendar: calendar)
        diagnostics.record("Siri", "show match '\(phrase)': \(found.count) of \(shows.count) shows")
        return found
    }

    /// The newest shows to offer when nothing has been said, without the one on the air, which is not an archive yet.
    static func suggestedShows() async -> [StationKit.ArchiveShow] {
        let shows = await loadedArchiveShows()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shownZone
        let newest = ShowMatching.matches("", in: shows, limit: 6, calendar: calendar)
        return Array(newest.dropFirst())
    }

    /// Every show the archive holds, for looking one up by its id.
    static func archivedShows() async -> [StationKit.ArchiveShow] {
        await loadedArchiveShows()
    }

    /// Plays an archived show from its start.
    /// - Parameter id: The show's id, as `ShowEntity` carries it.
    static func playShow(id: String) async -> String {
        guard let archive, model != nil else { return notReady }
        guard let show = await archivedShows().first(where: { $0.id == id }) else { return noSuchShow }
        await archive.play(show)
        diagnostics.record("Siri", "play show \(show.id) \(show.programName): started \(archive.nowPlayingShow?.id == show.id)")
        guard archive.nowPlayingShow?.id == show.id else { return archive.notice ?? noSuchShow }
        return "Playing \(show.programName), \(ArchiveTiming.dayAndClock(show.startTime, zone: shownZone))."
    }

    /// Spoken when a show is gone from the archive, or has no audio.
    static let noSuchShow = "That show is no longer available."

    /// The zone times are spoken in, from Settings.
    nonisolated static var shownZone: TimeZone {
        ShowTimeZone.resolve(stored: UserDefaults.standard.string(forKey: ShowTimeZone.storageKey)).zone
    }
}
