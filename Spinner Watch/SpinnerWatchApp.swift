//
//  SpinnerWatchApp.swift
//  Spinner Watch
//

import SwiftUI

@main
struct SpinnerWatchApp: App {
    @State private var player = WatchPlayer()

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
