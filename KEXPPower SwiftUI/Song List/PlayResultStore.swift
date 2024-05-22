//
//  PlayResultStore.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 2/1/22.
//  Copyright © 2022 KEXP. All rights reserved.
//

import Foundation
//import Combine
import SwiftUI
import OSLog


var unused: Void { return
	//extension Publisher {
	//	func asyncMap<T>(
	//		_ transform: @escaping (Output) async -> T
	//	) -> Publishers.FlatMap<Future<T, Never>, Self> {
	//		flatMap { value in
	//			Future { promise in
	//				Task {
	//					let output = await transform(value)
	//					promise(.success(output))
	//				}
	//			}
	//		}
	//	}
	//}


	//class PlayResultStore: ObservableObject, Identifiable {
	//    private var timerSubscription: AnyCancellable?
	//    @Published var results: [PlayResult] = []
	//    @Published var plays: [Play] = []
	//	@Published var activePlay: Play = .fixture()
	//
	//    init() {
	//		Task {
	//			await start()
	//			await next()
	//		}
	//    }
	//
	//    func start(every interval: TimeInterval = 5.0) async {
	//       timerSubscription = Timer
	//            .publish(every: interval,
	//                     on: RunLoop.main,
	//                     in: RunLoop.Mode.common)
	//			.autoconnect()
	//			.asyncMap{[weak self] _ in
	//				await self?.next()}
	//			.sink{ [weak self] _ in
	//				self
	//			}
	////            .sink { [weak self] _ in
	////               self?.next()
	////            }
	//    }
	//
	//    func next() async {
	//		let nextPlayResultsStoreLogger = Logger(#function)
	//		await listActivePlay()
	//		await listPlays()
	//		do {
	//			let result = try await NetworkManager().getPlay()
	//			self.results = [result]
	//		} catch {
	//			nextPlayResultsStoreLogger.error("\(error.localizedDescription, privacy: .public)")
	//		}
	////        NetworkManager().getPlay { result in
	////            switch result {
	////                case .success(let playResult):
	////					guard let goodPlayResult = playResult else { nextPlayResultsStoreLogger.warning("No Results"); return }
	////                    self.results = [goodPlayResult]
	////                    guard let plays = goodPlayResult.plays else { nextPlayResultsStoreLogger.warning("No Plays"); return}
	////					let currentPlay = [plays[(0)]].first!
	////					if self.activePlay.id != currentPlay.id {
	////					self.objectWillChange.send()
	////						self.activePlay = currentPlay
	////						nextPlayResultsStoreLogger.log("\(self.activePlay.description, privacy: .public)")
	////					}
	////                case .failure(let error):
	////					nextPlayResultsStoreLogger.error("\(error.localizedDescription, privacy: .public)")
	////            }
	////        }
	//
	//    }
	//
	//    func listPlays() async {
	//        self.$results
	//            .dropFirst()
	//            .map { results in
	//                results.flatMap({$0.plays ?? []})
	//        }
	//        .assign(to: &$plays)
	//    }
	//
	//	func listActivePlay() async {
	//		self.$results
	//			.map { results in
	//				results.flatMap({$0.plays ?? []}).first ?? .fixture()
	//			}
	//			.receive(on: DispatchQueue.main)
	//			.assign(to: &$activePlay)
	//	}
	//}

	//@MainActor
	//@Observable
	//class PlayResults: Identifiable, ObservableObject {
	//	private var timerSubscription: AnyCancellable?
	//	var results: [PlayResult] = []
	//	var plays: [Play] = []
	//	var activePlay: Play = .fixture()
	//	let nextPlayResultsLogger = Logger(#function)
	//
	//	func getActivePlay() async {
	//		let getActivePlayLogger = Logger(#function)
	//		activePlay = .fixture()
	//		Task {
	//			let result = try await NetworkManager().getPlay()
	//			results = [result]
	//			getActivePlayLogger.debug("Getting Play using \(#function)")
	//			DispatchQueue.main.async {
	//				self.activePlay = self.results.first?.plays?.first ?? .fixture()
	//			}
	//		}
	//	}
	//}
}


