//
//  ContentView.swift
//  Shared
//
//  Created by Justin Purnell on 1/31/22.
//  Copyright © 2022 KEXP. All rights reserved.
//

//import Combine
import AVKit
import OSLog
import SwiftUI
import KEXPPower

@MainActor
struct ContentView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var resultsRetriever: ResultRetriever = ResultRetriever()
    let logger = Logger(#function)
    @State var press: Bool = false

    /// Everything but the play on the air, newest first.
    private var previousPlays: [Play] {
        Array(resultsRetriever.plays.compactMap({ $0 }).dropFirst())
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                ShowView(show: resultsRetriever.show).padding([.horizontal, .top])
                Spacer()
            }
            #if os(macOS)
                VStack(alignment: .leading) {
                    HStack {
                        Text("Now Playing").fontWeight(.semibold)
                        Spacer()
                        Button(action: resultsRetriever.playerController.playOrPause) {
                            Image(systemName: resultsRetriever.playerController.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .resizable()
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(resultsRetriever.playerController.isPlaying ? "Pause" : "Play")
                    }
                    CombinedView(play: resultsRetriever.play)
                }.padding(.horizontal)
            #endif
            #if os(iOS) || os(visionOS)
                VStack(alignment: .leading) {
                    Text("Now Playing").fontWeight(.semibold)
                    HStack(alignment: .center) {
                        PlayerView(resultsRetriever: resultsRetriever)
                    }
                }.padding(.horizontal)
            #endif
            Text("Previously").fontWeight(.semibold).padding([.horizontal])
            #if os(macOS)
                // A scroll view, not a List: a Mac List adds its own insets and gutters, so the rows would not line up with Now Playing.
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(previousPlays) { play in
                            CombinedView(play: play)
                        }
                    }
                    .padding([.horizontal, .bottom])
                }
                .background(OverlayScrollers())
            #else
                List(previousPlays) { play in
                    CombinedView(play: play)
                        .listRowSeparator(.hidden)
                        .listSectionSeparator(.hidden)
                }
                .refreshable {
                    press.toggle()
                    let _ = await resultsRetriever.getResults()
                    logger.debug(
                        "Manual Refresh\rActive Play:\r\((resultsRetriever.play).description, privacy: .public)"
                    )
                }
            #endif
        }
        .task {
            let _ = await resultsRetriever.getResults()
        }
        .background(reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.ultraThinMaterial))
        #if os(iOS) || os(visionOS)
            .navigationBarHidden(true)
        #endif
        #if os(iOS) || os(visionOS)
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
