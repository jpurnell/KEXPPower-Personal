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
			Text(play.airtime).multilineTextAlignment(/*@START_MENU_TOKEN@*/.leading/*@END_MENU_TOKEN@*/)
			Text(play.song ?? "").bold()
			Text(play.artist ?? "").fontWeight(.light)
			Text(play.album ?? "").font(.caption)
			HStack(alignment: .top) {
				Text(play.releaseDate ?? "")
				Text(play.labels?.map({$0}).joined(separator: "\n") ?? "")
			}.font(.caption)
		}
	}
}

#Preview {
	CompactView(play: .fixture())
}
