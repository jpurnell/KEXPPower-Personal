//
//  ReviewPreviewModel.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import Observation

/// Plays a short piece of audio from a link. The app's one uses AVFoundation; a test supplies a fake.
@MainActor
protocol PreviewAudio: AnyObject {
    /// Called when the audio reaches its end by itself.
    var onFinish: (@MainActor () -> Void)? { get set }
    /// Starts playing, replacing anything already playing.
    func play(_ url: URL)
    /// Stops playing.
    func stop()
}

/// Lets the listener hear the Apple Music version of a held song, one at a time.
///
/// Playing a preview pauses the live stream first, and does not start it again: the listener asked to hear a song,
/// and the radio coming back later on its own would be a surprise.
@MainActor
@Observable
final class ReviewPreviewModel {
    /// Where one row is in being previewed.
    enum PreviewState: Equatable {
        case idle
        case playing
        /// Apple Music has no preview for the song.
        case unavailable
    }

    private var playingID: String?
    private var unavailableIDs: Set<String> = []
    @ObservationIgnored private let audio: any PreviewAudio
    @ObservationIgnored private let previewURL: @MainActor (String) async -> URL?
    @ObservationIgnored private let pauseStream: @MainActor () async -> Void

    /// - Parameters:
    ///   - audio: Plays the preview.
    ///   - previewURL: Finds a preview link for an Apple Music song id, or `nil` if it has none.
    ///   - pauseStream: Pauses the live stream before a preview starts.
    init(
        audio: any PreviewAudio, previewURL: @escaping @MainActor (String) async -> URL?,
        pauseStream: @escaping @MainActor () async -> Void
    ) {
        self.audio = audio
        self.previewURL = previewURL
        self.pauseStream = pauseStream
        audio.onFinish = { [weak self] in self?.playingID = nil }
    }

    /// Where a song's preview is.
    func state(for songID: String) -> PreviewState {
        if playingID == songID { return .playing }
        return unavailableIDs.contains(songID) ? .unavailable : .idle
    }

    /// Starts the song's preview, or stops it if it is the one playing.
    func toggle(_ songID: String) async {
        if playingID == songID {
            stop()
            return
        }
        guard let url = await previewURL(songID) else {
            unavailableIDs.insert(songID)
            return
        }
        unavailableIDs.remove(songID)
        await pauseStream()
        audio.play(url)
        playingID = songID
    }

    /// Stops whatever is playing.
    func stop() {
        guard playingID != nil else { return }
        audio.stop()
        playingID = nil
    }
}
