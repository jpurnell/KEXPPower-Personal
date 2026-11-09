//
//  AppModelRegistry+Intents.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// What Siri and Shortcuts ask of the app, each answered with the sentence to speak.
///
/// An intent can launch the app in the background before any window exists, so every entry point begins by checking the
/// app has made its model, and says so if it has not.
extension AppModelRegistry {
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

    /// The song on the air, or the one heard from an archived show, as a sentence.
    static func whatsPlaying() -> String {
        guard let model else { return notReady }
        let player = model.playerController
        if let archive, let show = archive.nowPlayingShow {
            let song = archive.heardTrack.map { IntentSpeech.Song(title: $0.title, artist: $0.displayArtist) }
            return IntentSpeech.whatsPlaying(
                song: song, show: show.programName, hosts: show.hostNames, isPlaying: player.isPlaying, fromArchive: true)
        }
        let summary = NowPlayingSummary(model.play)
        let song = summary.title == NowPlayingSummary.airbreakTitle
            ? nil : IntentSpeech.Song(title: summary.title, artist: summary.artist)
        return IntentSpeech.whatsPlaying(
            song: song, show: model.show.programName, hosts: model.show.hostNames ?? [],
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
}
