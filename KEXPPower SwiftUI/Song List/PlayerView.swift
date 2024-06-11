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

#if os(iOS) || os(visionOS)
struct PlayerView: View {
	// StateObject that manages the player controller and its state
//	@StateObject var playerController = PlayerController()
	var resultsRetriever: ResultRetriever
	@State var small: Bool = true
	let logger = Logger(#function)
	
    var body: some View {
		HStack(alignment: .center) {
			Button(action: {resultsRetriever.playerController.playOrPause()}) {
				VStack {
					Button(action: {
						small.toggle()
					},
						   label: {
						VStack{
							HStack {
								ZStack {
									ImageView(play: resultsRetriever.play).frame( width: small ? 100 : 300, height: small ? 100 : 300 )
								}
								.animation(.easeInOut(duration: 1.0), value: 1.0)
								.padding(small ? [.vertical] : [])
								(small ? CompactView(play: resultsRetriever.play)
									.frame(minWidth: 150, maxWidth: .infinity)
									.padding(.leading)
									.padding(.vertical) : nil)
									.animation(.easeInOut(duration: 1.0), value: 1.0)
								small ?
								Button(action: resultsRetriever.playerController.playOrPause) {
									Image(systemName: resultsRetriever.playerController.isPlaying ? "pause.circle" : "play.circle")
										.resizable()
										.foregroundStyle(.primary)
										.opacity(small ? 0.9 : 0).animation(.easeInOut(duration: 1.0), value: 1.0)
										.frame(minWidth: 64, idealWidth: 64, maxWidth: 64, minHeight: 64, idealHeight: 64, maxHeight: 64, alignment: .center)
								} : nil
							}
							(small ? nil : ExtendedView(play: resultsRetriever.play))
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

					})
				}
			}
		}
		.task {
			
		}
		.onAppear {
			
		}
    }
}

#Preview {
	PlayerView(resultsRetriever: ResultRetriever())
}
#endif
