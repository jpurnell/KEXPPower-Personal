//
//  PlayerView UI.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 5/8/24.
//  Copyright © 2024 KEXP. All rights reserved.
//

import SwiftUI
import OSLog

struct PlayerView: View {
	// StateObject that manages the player controller and its state
	@StateObject var playerController = PlayerController()
	@State var play: Play
	let logger = Logger(#function)
	
    var body: some View {
		HStack(alignment: .center) {
			ZStack {
//				VideoPlayer(playerController: playerController).overlay {
//					CombinedView(play: play)
//				}
				Button(action: {playerController.playOrPause()}) {
					Image(systemName: playerController.isPlaying ? "pause.circle" : "play.circle")
						.resizable()
						.frame(minWidth: 64, idealWidth: 64, maxWidth: 64, minHeight: 64, idealHeight: 64, maxHeight: 64, alignment: .center)
				}
			}
		}
		.onAppear {
			let streamURL = KEXPPower().streamURL
			logger.debug("Setting Stream URL to \(streamURL.absoluteString, privacy: .public)")
			
			playerController.initPlayer(
				link: KEXPPower().streamURL,
				title: play.song ?? "",
				artist: play.artist ?? "",
				artwork: play.imageURI ?? ""
			)
		}
    }
}

#Preview {
	PlayerView(play: .fixture())
}
