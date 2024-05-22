//
//  ShowStore.swift
//  KEXPPower
//
//  Created by Justin Purnell on 2/8/22.
//  Copyright © 2022 KEXP. All rights reserved.
//

import Foundation
import Combine
import OSLog

//class ShowStore: ObservableObject, Identifiable {
//    private var timerSubscription: AnyCancellable?
//    @Published var results: [ShowResult] = []
//    @Published var shows: [Show] = []
//    
//    init() {
////        next()
////        start()
//    }
//    
////    func start(every interval: TimeInterval = 300.0) {
////        timerSubscription = Timer
////            .publish(every: interval,
////                     on: .main,
////                     in: .common)
////            .autoconnect()
////            .sink { [weak self] _ in
////                self?.next()
////            }
////    }
//    
////    func next() {
////		let nextShowResultsStoreLogger = Logger(#function)
////		
////        NetworkManager().getShow { result in
////            switch result {
////                case .success(let showResult):
////					guard let goodShowResult = showResult else { nextShowResultsStoreLogger.warning("No Results"); return }
////                    self.results = [goodShowResult]
////                    guard let shows = goodShowResult.shows else { nextShowResultsStoreLogger.warning("No Shows"); return }
////					if self.shows.first?.id != shows.first?.id {
////					nextShowResultsStoreLogger.log("\(shows[0].description)")
////					}
////                case .failure(let error):
////					nextShowResultsStoreLogger.error("\(error.localizedDescription, privacy: .public)")
////				default:
////					nextShowResultsStoreLogger.error("\("Neither Error nor Result", privacy: .public)")
////            }
////        }
////        listShows()
////    }
//	
//	func next() async  {
//		let nextShowResultsStoreLogger = Logger(#function)
//		do {
//			let showResult: ShowResult = try await NetworkManager().getShow()
//			guard let shows = showResult.shows else {  return }
//			self.results = [showResult]
//		} catch {
//			nextShowResultsStoreLogger.error("\(error.localizedDescription, privacy: .public)")
//		}
//			
//				
//	}
//    
//    func listShows() {
//        self.$results
//            .dropFirst()
//            .map { results in
//                results.first?.shows ?? []
//            }
//            .assign(to: &$shows)
//    }
//}
