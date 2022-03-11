//
//  PlayResultStore.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 2/1/22.
//  Copyright © 2022 KEXP. All rights reserved.
//

import Foundation
import Combine
import KEXPPower

class PlayResultStore: ObservableObject, Identifiable {
    private var timerSubscription: AnyCancellable?
    @Published var results: [PlayResult] = []
    @Published var plays: [Play] = []
    
    init() {
        next()
        start()
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
        NetworkManager().getPlay { result in
            switch result {
                case .success(let playResult):
                    guard let goodPlayResult = playResult else { print("no results"); return }
                    self.results = [goodPlayResult]
                    guard let plays = goodPlayResult.plays else { print("no plays"); return}
                    print(plays[0])
                case .failure(let error):
                    print("error: \(error.localizedDescription)")
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
}
