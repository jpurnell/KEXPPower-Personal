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

#if !os(tvOS)
/// The Playback menu: play or pause the stream from the keyboard, and on the Mac switch between the two windows.
/// tvOS has no menu bar, so it has no commands; the TV compiles this file for ``PlaybackMenuState``.
struct PlaybackCommands: Commands {
    let model: ResultRetriever

    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    var body: some Commands {
        CommandMenu("Playback") {
            Button(PlaybackMenuState(isPlaying: model.playerController.isPlaying).title) {
                model.playerController.playOrPause()
            }
            .keyboardShortcut(.space, modifiers: [])
            #if os(macOS)
            Divider()
            Button("Show Mini Player") {
                openWindow(id: SceneID.mini)
                dismissWindow(id: SceneID.main)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            Button("Show Full Window") {
                openWindow(id: SceneID.main)
                dismissWindow(id: SceneID.mini)
            }
            .keyboardShortcut("m", modifiers: [.command, .option])
            #endif
        }
    }
}
#endif
