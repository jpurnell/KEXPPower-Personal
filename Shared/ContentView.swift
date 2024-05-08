//
//  ContentView.swift
//  Shared
//
//  Created by Justin Purnell on 1/31/22.
//  Copyright © 2022 KEXP. All rights reserved.
//

import SwiftUI
import Combine
import AVKit

struct ContentView: View {
    let networkManager = NetworkManager()
    let archiveManager = ArchiveManager()
    @ObservedObject var playResults: PlayResultStore
    @ObservedObject var showResults: ShowStore
	
    var body: some View {
            VStack(alignment: .leading) {
				HStack {
					ShowView(show: showResults.shows.first).padding()
					Spacer()
				}
				Divider()
				HStack(alignment: .center) {
					Spacer()
					Text("Listen")
					PlayerView(play: playResults.activePlay)
					Text("Live")
					Spacer()
				}
				Divider()
					List(playResults.results.flatMap({$0.plays ?? [] })) { play in
						CombinedView(play: play)
					}
					.listSectionSeparator(.hidden)
					.listRowSeparator(.visible)
					.refreshable {
					  playResults.next()
					  showResults.next()

				}
				
			}
			.background(.ultraThinMaterial)
		#if os(iOS) || os(visionOS)
			.navigationBarHidden(true)
		#endif
			#if os(iOS)
			.navigationSplitViewStyle(.balanced)
			#endif
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
