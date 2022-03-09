//
//  KEXPPowerExampleSwiftUIApp.swift
//  Shared
//
//  Created by Justin Purnell on 1/31/22.
//  Copyright © 2022 KEXP. All rights reserved.
//

import SwiftUI
import KEXPPower

@main
struct KEXPPowerExampleSwiftUIApp: App {
    
    let kexp = KEXPPower.fixture()
    
    var body: some Scene {
        WindowGroup {
            ContentView(playResults: PlayResultStore(), showResults: ShowStore())
        }
    }
}
