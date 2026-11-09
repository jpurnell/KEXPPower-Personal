//
//  Extended View.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 5/7/24.
//  Copyright © 2024 KEXP. All rights reserved.
//

import OSLog
import SwiftUI
import KEXPPower

@MainActor
struct ExtendedView: View {
    @Environment(\.openURL) private var openURL
    var play: Play?
    let appleMusicRetriever: AppleMusicRetriever = AppleMusicRetriever()
    let logger = Logger(#function)
    @State var appleMusicURL: URL?

    var body: some View {
        VStack {
            HStack {
                VStack {
                    #if os(tvOS)
                    // Nothing on a TV opens a web link, so the title is not a button and the search links are left out.
                    Text(play?.song ?? "Airbreak").fontWeight(.semibold)
                    #else
                    Button {
                        if let appleMusicURL {
                            logger.debug("Opening \(appleMusicURL.absoluteString, privacy: .public)")
                            openURL(appleMusicURL)
                        }
                    } label: {
                        Text(play?.song ?? "Airbreak").fontWeight(.semibold)
                    }
                    #endif
                    Text(play?.artist ?? "").font(.caption)
                    Text(play?.album ?? "").font(.caption).foregroundColor(.gray)
                    #if !os(tvOS)
                    HStack {
                        if let url = MusicLinks.spotifySearchURL(artist: play?.artist, track: play?.song) {
                            Link("Spotify", destination: url)
                        }
                        if let url = MusicLinks.bandcampSearchURL(artist: play?.artist, album: play?.album) {
                            Link("Bandcamp", destination: url)
                        }
                    }
                    .font(.caption)
                    #endif
                }

            }
            #if os(macOS)
                // The whole page scrolls on the Mac. An inner scroll view here would take every click in its frame,
                // so a click on the row would not reach the row.
                Text(MusicLinks.linkedComment(play?.comment ?? ""))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            #else
                ScrollView(.vertical, showsIndicators: true) {
                    Text(MusicLinks.linkedComment(play?.comment ?? ""))
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                }
            #endif
        }
        .task { await lookUpAppleMusic() }
    }

    private func lookUpAppleMusic() async {
        guard let artist = play?.artist, let song = play?.song else { return }
        logger.debug("Looking up \(song, privacy: .public)")
        do {
            appleMusicURL = try await appleMusicRetriever.getAppleMusicResult(
                artist: artist, track: song, album: play?.album ?? "")
            logger.debug("Got track \(song, privacy: .public) by \(artist, privacy: .public) at \(appleMusicURL?.absoluteString ?? "", privacy: .public)")
        } catch {
            logger.error("No track found")
        }
    }
}

#Preview {
    ExtendedView(play: .fixture())
}
