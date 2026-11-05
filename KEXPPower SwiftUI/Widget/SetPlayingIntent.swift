//
//  SetPlayingIntent.swift
//  KEXPPowerExampleSwiftUI
//

#if !os(visionOS)
import AppIntents

/// Sets the stream playing or paused from a Control Center control.
///
/// A control's toggle hands its intent the state the listener asked for, so this sets that state instead of flipping
/// whatever the player is doing. It is an `AudioPlaybackIntent`, so it runs in the app's process and can start audio
/// without the app coming to the front. The widget extension compiles it to name the intent; only the app's copy acts.
@available(iOS 18.0, macOS 26.0, *)
struct SetPlayingIntent: SetValueIntent, AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play KEXP"
    static let description = IntentDescription("Starts or pauses the KEXP stream.")

    @Parameter(title: "Playing")
    var value: Bool

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await AppModelRegistry.setPlayback(value)
        #endif
        return .result()
    }
}
#endif
