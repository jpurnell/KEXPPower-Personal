//
//  WatchPlayPauseIntent.swift
//  Spinner Watch
//

import AppIntents

/// Starts or pauses the stream from the watch widget.
///
/// An `AudioPlaybackIntent` runs in the watch app's process, so playback can start without the app coming to the front.
/// The widget extension compiles this too, to name the intent in its button; only the app's copy does anything.
struct WatchPlayPauseIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play or Pause KEXP"
    static let description = IntentDescription("Starts the KEXP stream, or pauses it if it is playing.")

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await WatchModelRegistry.togglePlayback()
        #endif
        return .result()
    }
}
