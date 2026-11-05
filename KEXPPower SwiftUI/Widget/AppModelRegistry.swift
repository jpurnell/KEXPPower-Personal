//
//  AppModelRegistry.swift
//  KEXPPowerExampleSwiftUI
//

/// Lets an App Intent reach the running app's player, since an intent is created by the system, not by the app.
@MainActor
enum AppModelRegistry {
    /// The model the app created at launch.
    static var model: ResultRetriever?
    /// The saving model the app created at launch, so CarPlay adds songs to the same playlists as the phone.
    static var saving: SongSavingModel?

    /// Starts playback if it is stopped and pauses it if it is playing.
    ///
    /// The stream is created on first use, because an intent can launch the app in the background before any window
    /// has asked for it.
    static func togglePlayback() async {
        guard let model else { return }
        // The widget reloads as soon as this returns, before the stream has started: tell it what is coming.
        await model.expectPlayState(!model.playerController.isPlaying)
        await model.startIfNeeded()
        model.playerController.playOrPause()
    }

    /// Starts or pauses playback to match what a control asked for; a request for the current state does nothing.
    /// - Parameter playing: Whether the listener wants the stream playing.
    static func setPlayback(_ playing: Bool) async {
        guard let model, ControlPlayState.shouldToggle(wanted: playing, isPlaying: model.playerController.isPlaying) else { return }
        await togglePlayback()
    }
}
