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
import OSLog

@MainActor
struct ContentView: View {

	var resultsRetriever: ResultRetriever = ResultRetriever()
	let logger = Logger(#function)
	@State var press: Bool = false
	
    var body: some View {
		VStack(alignment: .leading){
				HStack {
					ShowView(show: resultsRetriever.show).padding([.horizontal, .top])
					Spacer()
				}
				#if os(macOS)
				VStack(alignment: .leading){
					Text("Now Playing").fontWeight(.semibold)
					HStack(alignment: .center) {
						CombinedView(play: resultsRetriever.play)
					}
				}.padding(.horizontal)
				#endif
				#if os(iOS)
				VStack(alignment: .leading){
					Text("Now Playing").fontWeight(.semibold)
					HStack(alignment: .center) {
						PlayerView(play: resultsRetriever.play)
					}
				}.padding(.horizontal)
				#endif
			Text("Previously").fontWeight(.semibold).padding([.horizontal])
			List(resultsRetriever.plays.compactMap({$0}).dropFirst()) { play in
						CombinedView(play: play)
					}
					.listSectionSeparator(.hidden)
					.listRowSeparator(.hidden)
					.refreshable {
						press.toggle()
						let _ = await resultsRetriever.getResults()
						logger.debug("Manual Refresh\rActive Play:\r\((resultsRetriever.play ?? .fixture()).description, privacy: .public)")
				}
			}
			.task {
				let _ = await resultsRetriever.getResults()
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
        ContentView()
            .previewLayout(.sizeThatFits)
    }
}
