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

    /// The shared model; the app owns it, so every window shows the same player.
    let resultsRetriever: ResultRetriever
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
                #if os(iOS)
                SettingsButton(model: resultsRetriever).padding([.horizontal, .top])
                #endif
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
                        .accessibilityLabel(PlaybackMenuState(isPlaying: resultsRetriever.playerController.isPlaying).title)
                    }
                    CombinedView(play: resultsRetriever.play)
                }.padding(.horizontal)
            #endif
            #if os(tvOS)
                // A labelled button rather than iOS's PlayerView, whose nested buttons have no sensible focus order:
                // the remote moves to Play and selects it, and the card below shows what is on the air.
                VStack(alignment: .leading) {
                    HStack {
                        Text("Now Playing").fontWeight(.semibold)
                        Spacer()
                        Button(action: resultsRetriever.playerController.playOrPause) {
                            Label(PlaybackMenuState(isPlaying: resultsRetriever.playerController.isPlaying).title,
                                  systemImage: resultsRetriever.playerController.isPlaying ? "pause.fill" : "play.fill")
                        }
                    }
                    CombinedView(play: resultsRetriever.play)
                }.padding(.horizontal)
            #endif
            #if os(iOS) || os(visionOS)
                VStack(alignment: .leading) {
                    // The add button sits on the label line, so the row below keeps its whole width.
                    HStack {
                        Text("Now Playing").fontWeight(.semibold)
                        Spacer()
                        if AppSongSaver.canSaveToPlaylists, SongSavingModel.canSave(resultsRetriever.play) {
                            SaveButton(play: resultsRetriever.play)
                        }
                    }
                    HStack(alignment: .center) {
                        PlayerView(resultsRetriever: resultsRetriever)
                    }
                }.padding(.horizontal)
            #endif
            Text("Previously").fontWeight(.semibold).padding([.horizontal])
            // A scroll view, not a List: a List adds its own insets and, on iOS, a grouped background, so the cards would
            // not line up with Now Playing above them.
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(previousPlays) { play in
                        CombinedView(play: play)
                    }
                }
                .padding([.horizontal, .bottom])
            }
            #if os(macOS)
                .background(OverlayScrollers().frame(width: 0, height: 0).allowsHitTesting(false))
            #else
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
            await resultsRetriever.startIfNeeded()
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
        ContentView(resultsRetriever: ResultRetriever())
            .environment(AppSongSaver.makeModel())
            .previewLayout(.sizeThatFits)
    }
}
