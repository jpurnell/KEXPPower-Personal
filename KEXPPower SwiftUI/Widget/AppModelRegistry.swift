//
//  AppModelRegistry.swift
//  KEXPPowerExampleSwiftUI
//

/// Lets an App Intent reach the running app's player, since an intent is created by the system, not by the app.
@MainActor
enum AppModelRegistry {
    /// The model the app created at launch.
    static var model: ResultRetriever?

    /// Starts playback if it is stopped and pauses it if it is playing.
    ///
    /// The stream is created on first use, because an intent can launch the app in the background before any window
    /// has asked for it.
    static func togglePlayback() async {
        guard let model else { return }
        await model.startIfNeeded()
        model.playerController.playOrPause()
    }
}
