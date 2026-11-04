//
//  PlaybackCommands.swift
//  KEXPPowerExampleSwiftUI
//

import SwiftUI

/// What the play/pause control says for the player's current state.
struct PlaybackMenuState: Equatable {
    let isPlaying: Bool

    /// The control's title and accessibility label.
    var title: String { isPlaying ? "Pause" : "Play" }
}

/// The Playback menu: play or pause the stream from the keyboard.
struct PlaybackCommands: Commands {
    let model: ResultRetriever

    var body: some Commands {
        CommandMenu("Playback") {
            Button(PlaybackMenuState(isPlaying: model.playerController.isPlaying).title) {
                model.playerController.playOrPause()
            }
            .keyboardShortcut(.space, modifiers: [])
        }
    }
}
