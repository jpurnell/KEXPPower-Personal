//
//  PlayerView UI.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 5/8/24.
//  Copyright © 2024 KEXP. All rights reserved.
//

import SwiftUI
import OSLog
import AVFAudio

#if os(iOS)
struct PlayerView: View {
	// StateObject that manages the player controller and its state
	@StateObject var playerController = PlayerController()
	var play: Play?
	@State var small: Bool = true
	let logger = Logger(#function)
	
    var body: some View {
		HStack(alignment: .center) {
			Button(action: {playerController.playOrPause()}) {
				VStack {
					Button(action: {
						small.toggle()
					},
						   label: {
						VStack{
							HStack {
								ZStack {
									ImageView(play: play ?? .fixture()).frame( width: small ? 120 : 300, height: small ? 120 : 300 )
									Button(action: playerController.playOrPause) {
										Image(systemName: playerController.isPlaying ? "pause.circle" : "play.circle")
											.resizable()
											.foregroundStyle(.primary)
											.opacity(small ? 0.9 : 0).animation(.easeInOut(duration: 1.0), value: 1.0)
											.frame(minWidth: 64, idealWidth: 64, maxWidth: 64, minHeight: 64, idealHeight: 64, maxHeight: 64, alignment: .center)
									}
								}
								.animation(.easeInOut(duration: 1.0), value: 1.0)
								.padding(small ? [.vertical] : [.all])
								(small ? CompactView(play: play ?? .fixture())
									.frame(minWidth: 200, maxWidth: .infinity)
									.padding(.leading)
									.padding(.vertical) : nil)
									.animation(.easeInOut(duration: 1.0), value: 1.0)
							}
							(small ? nil : ExtendedView(play: play ?? .fixture()))
								.animation(.easeInOut(duration: 1.0), value: 1.0)
								.frame(
									minWidth: 200,
									idealWidth: 200,
									maxWidth: .infinity,
									minHeight: 100,
									idealHeight: 500,
									maxHeight: .infinity,
									alignment: .center
								)
						}
					})
					.foregroundStyle(.primary)
					.onAppear(perform: {
//						let logger = Logger(#function)
//						logger.debug("Displaying Combined view for \(play?.description ?? "Default Play", privacy: .public)")
					})
				}
			}
		}
		.task {
		}
		.onAppear {
//			logger.debug("Displaying Player view for \(play?.description ?? "Default Play", privacy: .public)")
			let streamURL = KEXPPower().streamURL
			
			
			playerController.initPlayer(
				link: streamURL,
				title: play?.song ?? "",
				artist: play?.artist ?? "",
				artwork: play?.imageURI ?? ""
			)
//			logger.debug("Set up Player with Stream \(streamURL.absoluteString, privacy: .public) with play \(play?.description ?? "No Song")")
		}
    }
}

#Preview {
	PlayerView(play: .fixture())
//	PlayerView(playResultsStore: PlayResultStore())
}
#endif
