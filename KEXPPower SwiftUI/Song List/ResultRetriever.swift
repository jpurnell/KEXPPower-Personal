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
	
	
	var attempt: Int = 0
	
	func getResults() async {
		Task {
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
}

