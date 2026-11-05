//
//  ControlPlayState.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// What the Control Center control says and does for a play state, kept apart from WidgetKit so it can be tested.
enum ControlPlayState {
    /// Whether a request to set playback needs the player toggled.
    ///
    /// A control can show a stale state, so it asks for a state ("play") rather than a flip; asking for what is
    /// already true does nothing.
    /// - Parameters:
    ///   - wanted: The state the listener asked for.
    ///   - isPlaying: Whether the player is playing now.
    static func shouldToggle(wanted: Bool, isPlaying: Bool) -> Bool {
        wanted != isPlaying
    }

    /// The value shown beside the control's label.
    static func valueText(isPlaying: Bool) -> String {
        isPlaying ? "Playing" : "Paused"
    }

    /// The symbol shown on the control: the action a tap performs.
    static func symbolName(isPlaying: Bool) -> String {
        isPlaying ? "pause.fill" : "play.fill"
    }

    /// What VoiceOver reads for the control.
    static func accessibilityLabel(station: String, isPlaying: Bool) -> String {
        "\(station), \(valueText(isPlaying: isPlaying).lowercased())"
    }
}
