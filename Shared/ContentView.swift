//
//  ContentView.swift
//  Shared
//
//  Created by Justin Purnell on 1/31/22.
//  Copyright © 2022 KEXP. All rights reserved.
//

import SwiftUI
import Combine
//import KEXPPower

struct ContentView: View {
    let networkManager = NetworkManager()
    let archiveManager = ArchiveManager()
    @ObservedObject var playResults: PlayResultStore
    @ObservedObject var showResults: ShowStore
    
    var body: some View {
//        NavigationView {
            VStack(alignment: .leading) {
				ShowView(show: showResults.shows.first).padding(.horizontal)
				List(playResults.results.flatMap({$0.plays ?? [] })) { play in
						CombinedView(play: play)

                }.refreshable {
                    playResults.next()
                    showResults.next()
                }
			}
			.background(.ultraThinMaterial)
//			.navigationBarHidden(true)
			#if os(iOS)
			.navigationSplitViewStyle(.balanced)
			#endif
//        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(
            playResults: PlayResultStore(),
            showResults: ShowStore())
            .previewLayout(.sizeThatFits)
    }
}
