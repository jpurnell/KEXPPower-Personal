//
//  Extended View.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 5/7/24.
//  Copyright © 2024 KEXP. All rights reserved.
//

import SwiftUI
import OSLog

@MainActor
struct ExtendedView: View {
	@Environment(\.openURL) private var openURL
	var play: Play?
	let appleMusicRetriever: AppleMusicRetriever = AppleMusicRetriever()
	let logger = Logger(#function)
	@State var appleMusicURL: URL?
	
    var body: some View {
		VStack {
			HStack{
				VStack{
					Button {
						if let _ = appleMusicURL {
							logger.debug("Opening \(appleMusicURL?.absoluteString ?? "")")
							openURL(appleMusicURL!)
							logger.debug("Think we opened \(appleMusicURL?.absoluteString ?? "")")
						}
					} label: {
						Text(play?.song ?? "Airbreak").fontWeight(.semibold)
					}
					Text(play?.artist ?? "").font(.caption)
					Text(play?.album ?? "").font(.caption).foregroundColor(.gray)
				}
				
			}
			ScrollView(.vertical, showsIndicators: true) {
				Text(.init(stringLiteral: play?.comment ?? ""))
					.lineLimit(nil)
					.multilineTextAlignment(.leading)
			}
		}
		.task {
			
		}
		.onAppear {
			Task {
				do {
					if play?.artist != nil && play?.song != nil {
						logger.debug("Looking up \(play?.song ?? "", privacy: .public)")
						let track = try await appleMusicRetriever.getAppleMusicResult(artist: play!.artist!, track: play!.song!, album: play?.album ?? "")
						appleMusicURL = track
						logger.debug("Got track \(play?.song ?? "", privacy: .public) by \(play?.artist ?? "", privacy: .public) from \(play?.album ?? "N/A") (\(play?.formattedReleaseYear ?? "")) at \(appleMusicURL?.absoluteString ?? "", privacy: .public)")
					} else { return }
				} catch {
					let logger = Logger(#function)
					logger.error("No track found")
				}
			}
		}
    }
}

#Preview {
	ExtendedView(play: .fixture())
}
