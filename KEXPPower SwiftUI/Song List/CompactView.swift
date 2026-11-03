//
//  CompactView.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 5/7/24.
//  Copyright © 2024 KEXP. All rights reserved.
//

import SwiftUI
import OSLog
import KEXPPower

struct CompactView: View {
	var play: Play?
	
	var body: some View {
		HStack {
			VStack(alignment: .leading) {
				Text(play?.airtime ?? DateFormatter.playlistDisplayFormatter.string(from: Date())).font(.callout)
				Text(play?.song ?? "Airbreak").lineLimit(nil).fontWeight(.semibold)
				Text(play?.artist ?? "").fontWeight(.light).lineLimit(nil)
				Text(play?.album ?? "").font(.caption).lineLimit(nil)
				HStack(alignment: .top) {
					Text(play?.releaseDate ?? "")
					Text(play?.labels?.map({$0}).joined(separator: "\n") ?? "")
				}
				.font(.caption)
			}
			.multilineTextAlignment(.leading)
			Spacer()
		}
		.onAppear {
//			let logger = Logger(#function)
//			logger.debug("Displaying Compact view for \(play?.description ?? "Default Play", privacy: .public)")
		}
	}
}

#Preview {
	CompactView(play: .fixture())
		.previewLayout(.sizeThatFits)
}
