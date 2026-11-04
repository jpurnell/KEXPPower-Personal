//
//  PlayPauseIntent.swift
//  KEXPPowerExampleSwiftUI
//

import AppIntents

/// Starts or pauses the stream from the widget.
///
/// An `AudioPlaybackIntent` runs in the app's process, so playback can start without the app coming to the front.
/// The widget extension compiles this too, to name the intent in its button; only the app's copy does anything.
struct PlayPauseIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play or Pause KEXP"
    static let description = IntentDescription("Starts the KEXP stream, or pauses it if it is playing.")

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await AppModelRegistry.togglePlayback()
        #endif
        return .result()
    }
}
