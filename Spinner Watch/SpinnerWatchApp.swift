//
//  SpinnerWatchApp.swift
//  Spinner Watch
//

import SwiftUI

@main
struct SpinnerWatchApp: App {
    @State private var player: WatchPlayer

    init() {
        let player = WatchPlayer()
        _player = State(initialValue: player)
        // An App Intent from the watch widget reaches the player through this, even if the app is not on screen.
        WatchModelRegistry.player = player
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView(player: player)
        }
        #if os(macOS)
        .commands { CommandGroup(replacing: .newItem) {} }
        #endif

        #if os(macOS)
        Settings {
            EmptyView()
        }
        #endif
    }
}
