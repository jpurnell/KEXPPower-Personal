//
//  AudioPlayerViewModel.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 5/8/24.
//  Copyright © 2024 KEXP. All rights reserved.
//

//import Foundation
//import AVFoundation
//import OSLog
//
//class AudioPlayerViewModel: ObservableObject {
//	var audioPlayer: AVAudioPlayer?
//	var stream: URL = KEXPPower().streamURL
//	let logger = Logger(#function)
//	
//	@Published var isPlaying = false
//	init(stream: URL) {
//		do {
//			self.stream = URL(string: "https://kexp.streamguys1.com/kexp160.aac?listenerId=04E2D6DE-2A35-4A7B-8C97-84E0CC1E4498")!
//			logger.debug("Set stream to \(self.stream, privacy: .public)")
//			self.audioPlayer = try! AVAudioPlayer(contentsOf: URL(string: "https://kexp.streamguys1.com/kexp160.aac?listenerId=04E2D6DE-2A35-4A7B-8C97-84E0CC1E4498")!)
//			if let player = self.audioPlayer {
//				logger.debug("Got audio player: \(player, privacy: .public)")
//			}
//		} catch {
//			logger.error("AVAudioPlayer could not be instantiated \(error.localizedDescription)")
//		}
//	}
//	
//	func playOrPause() {
//		guard let player = audioPlayer else { logger.error("No Audio Player returned"); return }
//		
//		if player.isPlaying {
//			player.pause()
//			isPlaying = false
//		} else {
//			player.play()
//			isPlaying = true
//		}
//	}
//}
