//
//  ShowStore.swift
//  KEXPPower
//
//  Created by Justin Purnell on 2/8/22.
//  Copyright © 2022 KEXP. All rights reserved.
//

import Foundation
import Combine
import KEXPPower

class ShowStore: ObservableObject, Identifiable {
    private var timerSubscription: AnyCancellable?
    @Published var results: [ShowResult] = []
    @Published var shows: [Show] = []
    
    init() {
        next()
        start()
    }
    
    func start(every interval: TimeInterval = 300.0) {
        timerSubscription = Timer
            .publish(every: interval,
                     on: .main,
                     in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.next()
            }
    }
    
    func next() {
        NetworkManager().getShow { result in
            switch result {
                case .success(let showResult):
                    guard let goodShowResult = showResult else { print("no results"); return }
                    self.results = [goodShowResult]
                    guard let shows = goodShowResult.shows else { print("no shows"); return }
                    print(shows[0])
                case .failure(let error):
                    print("error: \(error.localizedDescription)")
            }
        }
        listShows()
    }
    
    func listShows() {
        self.$results
            .dropFirst()
            .map { results in
                results.first?.shows ?? []
            }
            .assign(to: &$shows)
    }
}
