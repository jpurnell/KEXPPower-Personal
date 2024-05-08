//
//  KEXPPowerExampleSwiftUIApp.swift
//  Shared
//
//  Created by Justin Purnell on 1/31/22.
//  Copyright © 2022 KEXP. All rights reserved.
//

import SwiftUI
import AVKit
import OSLog

@main
struct KEXPPowerExampleSwiftUIApp: App {
	
	//INFO: - https://www.hackingwithswift.com/quick-start/swiftui/how-to-add-an-appdelegate-to-a-swiftui-app
	@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
	
    var body: some Scene {
        WindowGroup {
            ContentView(playResults: PlayResultStore(), showResults: ShowStore())
        }
    }
}

// Custom AppDelegate to handle application lifecycle events
// INFO: - https://medium.com/@afridi.khondakar/implementing-background-play-picture-in-picture-in-swiftui-building-a-video-streaming-app-with-141304b84728
class AppDelegate: NSObject, UIApplicationDelegate {
	let logger = Logger(#function)
	// This method is called when the application finishes launching
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
		
		// Configure the audio session for background audio and video services
		
		let audioSession = AVAudioSession.sharedInstance()
		
		do {
			// Set the audio session category to playback
			try audioSession.setCategory(.playback)
			logger.info("set audioSession category to playback")
			
			// Activate the audio session
			try audioSession.setActive(true, options: [])
			logger.info("set audioSession setactive to true")
		} catch {
			// Handle errors related to audio session setup
			logger.error("Setting category to AVAudioSessionCategoryPlayback failed.")
		}
		
		return true
	}
}
