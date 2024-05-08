//
//  PlayResultStore.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 2/1/22.
//  Copyright © 2022 KEXP. All rights reserved.
//

import Foundation
import Combine
import SwiftUI
import OSLog

class PlayResultStore: ObservableObject, Identifiable {
    private var timerSubscription: AnyCancellable?
    @Published var results: [PlayResult] = []
    @Published var plays: [Play] = []
	@Published var activePlay: Play = .fixture()
	
    init() {
		start()
		next()
    }
    
    func start(every interval: TimeInterval = 10.0) {
       timerSubscription = Timer
            .publish(every: interval,
                     on: RunLoop.main,
                     in: RunLoop.Mode.common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.next()
            }
    }
    
    func next() {
		let logger = Logger(#function)
		let nextPlayResultsStoreLogger = Logger(#function)
		listActivePlay()
        NetworkManager().getPlay { result in
            switch result {
                case .success(let playResult):
					guard let goodPlayResult = playResult else { nextPlayResultsStoreLogger.warning("No Results"); return }
                    self.results = [goodPlayResult]
                    guard let plays = goodPlayResult.plays else { nextPlayResultsStoreLogger.warning("No Plays"); return}
					let currentPlay = [plays[(0)]].first!
					if self.activePlay.id != currentPlay.id {
						self.activePlay = currentPlay
						nextPlayResultsStoreLogger.log("\(self.activePlay.description), privacy: .public)")
					}
                case .failure(let error):
					nextPlayResultsStoreLogger.error("\(error.localizedDescription, privacy: .public)")
            }
        }
        listPlays()
    }
    
    func listPlays() {
        self.$results
            .dropFirst()
            .map { results in
                results.flatMap({$0.plays ?? []})
        }
        .assign(to: &$plays)
    }
	
	func listActivePlay() {
		self.$results
			.map { results in
				results.flatMap({$0.plays ?? []}).first ?? .fixture()
			}
			.assign(to: &$activePlay)
	}
}
