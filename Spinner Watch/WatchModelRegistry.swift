//
//  WatchModelRegistry.swift
//  Spinner Watch
//

/// Lets an App Intent reach the running watch app's player, since an intent is created by the system.
@MainActor
enum WatchModelRegistry {
    /// The player the app created at launch.
    static var player: WatchPlayer?

    /// Starts playback if it is stopped and pauses it if it is playing or about to.
    static func togglePlayback() async {
        guard let player else { return }
        player.start()
        await player.toggleFromIntent()
    }
}
