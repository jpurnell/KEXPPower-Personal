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
	
	#if os(iOS)
	//INFO: - https://www.hackingwithswift.com/quick-start/swiftui/how-to-add-an-appdelegate-to-a-swiftui-app
	@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
	#endif
    var body: some Scene {
        WindowGroup {
			ContentView()
        }
    }
}

#if os(iOS)
// Custom AppDelegate to handle application lifecycle events
// INFO: - https://medium.com/@afridi.khondakar/implementing-background-play-picture-in-picture-in-swiftui-building-a-video-streaming-app-with-141304b84728
class AppDelegate: NSObject, UIApplicationDelegate {
	let logger = Logger(#function)
	// This method is called when the application finishes launching
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
		
		// Configure the audio session for background audio and video services
		
		let audioSession = AVAudioSession.sharedInstance()
		application.beginReceivingRemoteControlEvents()
		do {
			// Set the audio session category to playback
			let audioSessionCategory: AVAudioSession.Category = .playAndRecord
			try audioSession.setCategory(audioSessionCategory, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowAirPlay])
			logger.info("set audioSession category to \(audioSessionCategory.rawValue, privacy: .public)")
			
			// Activate the audio session
			try audioSession.setActive(true, options: [.notifyOthersOnDeactivation])
			logger.info("set audioSession setactive to true")
		} catch {
			// Handle errors related to audio session setup
			logger.error("Setting category to AVAudioSessionCategoryPlayback failed.")
		}
		
		return true
	}
}
#endif
