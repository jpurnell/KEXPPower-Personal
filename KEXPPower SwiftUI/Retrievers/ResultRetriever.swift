//
//  ResultRetriever.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 5/22/24.
//  Copyright © 2024 KEXP. All rights reserved.
//

import Foundation
import OSLog

@MainActor
@Observable
public class ResultRetriever {
	let logger = Logger(#function)
	let networkManager = NetworkManager()
	var plays: [Play] = []
	var play: Play = .fixture()
	var show: Show = Show.fixture(hosts: [0], programName: "Retrieving…", hostNames: ["Retrieving…"], tagline: "", imageURI: "")
	var playerController = PlayerController()
	
	
	var attempt: Int = 0
	
	func getResults() async {
		Task {
			let streamURL = KEXPPower().streamURL
			playerController.initPlayer(link: streamURL, title: play.song ?? "Airbreak", album: play.album ?? "", artist: play.artist ?? "KEXP", artwork: play.imageURI ?? "https://kexp.org/static/assets/img/kexp_logo.jpg")
			repeat {
				let playResult = try await networkManager.getPlay()
				plays = playResult.plays ?? []
				play = playResult.plays?.first ?? .fixture()
				let showResult = try await networkManager.getShow()
				show = showResult.shows?.first ?? Show.fixture(hosts: [0], programName: "Retrieving…", hostNames: ["Retrieving…"])
				playerController.playbackTitle = play.song ?? ""
				playerController.playbackArtist = play.artist ?? ""
				playerController.playbackAlbum = play.album ?? ""
				playerController.playbackArtwork = play.imageURI ?? ""
				let updatedNotifications = await playerController.updateNotificationView(playerController.playbackTitle , artist: playerController.playbackArtist, album: playerController.playbackAlbum, artwork: playerController.playbackArtwork)
				logger.debug("Updated Player Controller for \(self.playerController.playbackTitle).\rNotifications Updated: \(updatedNotifications)")
								try await Task.sleep(until: .now + .seconds(5))
			} while (!Task.isCancelled)
		}
	}
}

