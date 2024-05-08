//
//  Extended View.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 5/7/24.
//  Copyright © 2024 KEXP. All rights reserved.
//

import SwiftUI

struct ExtendedView: View {
	public var play: Play
	
    var body: some View {
		VStack {
			Text(play.song ?? "Airbreak").fontWeight(.semibold)
			Text(play.artist ?? "").font(.caption)
			Text(play.album ?? "").font(.caption).foregroundColor(.gray)
			ScrollView(.vertical, showsIndicators: true) {
				Text(.init(stringLiteral: play.comment ?? ""))
					.lineLimit(nil)
					.multilineTextAlignment(.leading)
			}
			Spacer()
		}
    }
}

#Preview {
	ExtendedView(play: .fixture())
}
