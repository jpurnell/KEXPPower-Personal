//
//  CompactView.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 5/7/24.
//  Copyright © 2024 KEXP. All rights reserved.
//

import SwiftUI

struct CompactView: View {
	public var play: Play
	var body: some View {
		VStack(alignment: .leading) {
			Text(play.airtime).font(.callout)
			Text(play.song ?? "Airbreak").lineLimit(nil).fontWeight(.semibold)
			Text(play.artist ?? "").fontWeight(.light).lineLimit(nil)
			Text(play.album ?? "").font(.caption).lineLimit(nil)
			HStack(alignment: .top) {
				Text(play.releaseDate ?? "")
				Text(play.labels?.map({$0}).joined(separator: "\n") ?? "")
			}
			.font(.caption)
		}
		.multilineTextAlignment(/*@START_MENU_TOKEN@*/.leading/*@END_MENU_TOKEN@*/)
	}
}

#Preview {
	CompactView(play: .fixture())
		.previewLayout(.sizeThatFits)
}
