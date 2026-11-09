//
//  IntentSpeech.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// The sentences Siri and Shortcuts speak, kept apart from the intents so they can be tested.
///
/// Each is short enough to hear in a car: what happened, and nothing the listener has to remember.
enum IntentSpeech {
    /// A song as it is spoken.
    struct Song: Equatable, Sendable {
        let title: String
        let artist: String
    }

    /// What is on the air, or being heard from the archive.
    /// - Parameters:
    ///   - song: The song, or `nil` between songs and before an archived show's first.
    ///   - show: The show's name, if known.
    ///   - hosts: The show's hosts, possibly none.
    ///   - isPlaying: Whether audio is playing; a paused stream says so.
    ///   - fromArchive: Whether an archived show is playing.
    static func whatsPlaying(song: Song?, show: String?, hosts: [String], isPlaying: Bool, fromArchive: Bool) -> String {
        let showName = clean(show)
        let place = fromArchive ? (showName.map { "from \($0) in the archive" } ?? "from the archive") : "on KEXP"
        let said: String
        if let song, let title = clean(song.title) {
            let artist = clean(song.artist).map { " by \($0)" } ?? ""
            said = "\(title)\(artist), \(place)."
        } else if let showName {
            let names = hosts.compactMap(clean)
            let withHosts = names.isEmpty ? showName : "\(showName) with \(names.formatted(.list(type: .and)))"
            said = fromArchive ? "\(withHosts), from the archive." : "\(withHosts), on KEXP."
        } else {
            return "Nothing is playing."
        }
        return isPlaying ? said : said + " Playback is paused."
    }

    /// What to say after trying to add a song to the playlist.
    /// - Parameters:
    ///   - state: How the save ended.
    ///   - title: The song's title.
    static func saved(_ state: SaveState, title: String) -> String {
        switch state {
        case .idle: return "Nothing was added."
        case .saving: return "Still adding \(title)."
        case .saved(let playlists, let failed):
            switch (playlists.isEmpty, failed.isEmpty) {
            case (true, true): return "\(title) is already in your playlists."
            case (false, true): return "Added \(title) to \(playlists.formatted(.list(type: .and)))."
            case (false, false):
                return "Added \(title) to \(playlists.formatted(.list(type: .and))), but not to \(failed.formatted(.list(type: .and)))."
            case (true, false): return "Could not add \(title) to \(failed.formatted(.list(type: .and)))."
            }
        case .confirming, .heldForReview: return "\(title) is held for review on your phone."
        case .notFound: return "Apple Music has nothing for \(title)."
        case .unavailable: return "Apple Music could not be reached."
        case .needsPermission: return "Allow Spinner to use Apple Music in Settings, then try again."
        }
    }

    /// Why a rewind cannot happen, or `nil` when it can.
    static func rewindRefusal(window: RewindWindow, isLiveShifted: Bool, isArchive: Bool) -> String? {
        if isArchive { return "An archived show is playing. Rewind is for the live stream." }
        if window == .off { return "Rewind is off. Turn on the rewind window in Settings." }
        if !isLiveShifted { return "Live is not ready to rewind yet." }
        return nil
    }

    private static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
