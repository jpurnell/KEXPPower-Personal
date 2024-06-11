	//
	//  ResultRetriever.swift
	//  KEXPPowerExampleSwiftUI (iOS)
	//
	//  Created by Justin Purnell on 5/22/24.
	//  Copyright © 2024 KEXP. All rights reserved.
	//

import Foundation
import OSLog
import AVKit

@MainActor
@Observable
public class ResultRetriever {
	let logger = Logger(#function)
	let networkManager = NetworkManager()
	var plays: [Play] = []
	var play: Play = .fixture()
	var show: Show = Show.fixture(hosts: [0], programName: "Retrieving…", hostNames: ["Retrieving…"], tagline: "", imageURI: "")
#if os(iOS) || os(visionOS)
	var playerController = PlayerController()
#endif
	
	
	var attempt: Int = 0
	
#if os(iOS) || os(visionOS)
	func getResults() async {
		Task {
			let streamURL = KEXPPower().streamURL
			let kexpLogo = "https://kexp.org/static/assets/img/kexp_logo.jpg"
			playerController.initPlayer(link: streamURL, title: play.song ?? "Airbreak", album: play.album ?? "", artist: play.artist ?? "KEXP", artwork: play.imageURI ?? kexpLogo)
			repeat {
				let playResult = try await networkManager.getPlay()
				plays = playResult.plays ?? []
				play = playResult.plays?.first ?? .fixture()
				let showResult = try await networkManager.getShow()
				show = showResult.shows?.first ?? Show.fixture(hosts: [0], programName: "Retrieving…", hostNames: ["Retrieving…"])
				playerController.playbackTitle = play.song ?? "Airbreak"
				playerController.playbackArtist = play.artist ?? "KEXP"
				playerController.playbackAlbum = play.album ?? ""
				playerController.playbackArtwork = play.imageURI ?? kexpLogo
				#if os(iOS) || os(visionOS)
				let updatedNotifications = await playerController.updateNotificationView(playerController.playbackTitle , artist: playerController.playbackArtist, album: playerController.playbackAlbum, artwork: playerController.playbackArtwork)
				logger.debug("Updated Player Controller for \(self.playerController.playbackTitle).\rNotifications Updated: \(updatedNotifications)")
				#endif
				#if os(macOS)
				let updatedNotification = await playerController.setNowPlayingMetadata(playerController.playbackTitle , artist: playerController.playbackArtist, album: playerController.playbackAlbum, artwork: playerController.playbackArtwork)
				#endif
				try await Task.sleep(until: .now + .seconds(5))
			} while (!Task.isCancelled)
		}
	}
#endif
	
#if os(macOS)
	func getResults() async {
		Task {
			let streamURL = KEXPPower().streamURL
			let kexpLogo = "https://kexp.org/static/assets/img/kexp_logo.jpg"
			repeat {
				let playResult = try await networkManager.getPlay()
				plays = playResult.plays ?? []
				play = playResult.plays?.first ?? .fixture()
				let showResult = try await networkManager.getShow()
				show = showResult.shows?.first ?? Show.fixture(hosts: [0], programName: "Retrieving…", hostNames: ["Retrieving…"])
				try await Task.sleep(until: .now + .seconds(5))
			} while (!Task.isCancelled)
		}
	}
#endif
}

