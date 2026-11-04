//
//  KEXPPowerExampleSwiftUIApp.swift
//  Shared
//
//  Created by Justin Purnell on 1/31/22.
//  Copyright © 2022 KEXP. All rights reserved.
//

import SwiftUI

@main
struct KEXPPowerExampleSwiftUIApp: App {
    /// The one player and playlist, shared by every window and by the menus.
    @State private var model = ResultRetriever()

    var body: some Scene {
        WindowGroup {
            ContentView(resultsRetriever: model)
        }
        .commands {
            // One window, no documents: File > New Window has nothing sensible to open.
            CommandGroup(replacing: .newItem) {}
            PlaybackCommands(model: model)
        }

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
