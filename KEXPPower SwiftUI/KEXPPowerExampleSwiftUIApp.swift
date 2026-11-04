//
//  KEXPPowerExampleSwiftUIApp.swift
//  Shared
//
//  Created by Justin Purnell on 1/31/22.
//  Copyright © 2022 KEXP. All rights reserved.
//

import SwiftUI

/// The ids of the app's windows, used to open one and close the other.
enum SceneID {
    static let main = "main"
    static let mini = "mini"
}

@main
struct KEXPPowerExampleSwiftUIApp: App {
    /// The one player and playlist, shared by every window and by the menus.
    @State private var model = ResultRetriever()
    /// Saves songs to the listener's playlists; the add buttons read it from the environment.
    @State private var saving = AppSongSaver.makeModel()

    var body: some Scene {
        #if os(macOS)
        // A single window, so "Show Full Window" brings the existing one back instead of opening another.
        Window("Spinner", id: SceneID.main) {
            RootView(model: model)
                .environment(saving)
        }
        .defaultSize(width: 780, height: 900)
        .commands {
            // One window, no documents: File > New Window has nothing sensible to open.
            CommandGroup(replacing: .newItem) {}
            SidebarCommands()
            PlaybackCommands(model: model)
        }

        Window("Mini Player", id: SceneID.mini) {
            MiniPlayerView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 112)

        Settings {
            SettingsView()
        }
        #else
        WindowGroup {
            RootView(model: model)
                .environment(saving)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            PlaybackCommands(model: model)
        }
        #endif
    }
}
