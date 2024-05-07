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
			Text(play.song ?? "").fontWeight(.semibold)
			Text(play.artist ?? "").font(.caption)
			Text(play.album ?? "").font(.caption).foregroundColor(.gray)
//			Divider()
			ScrollView(.vertical, showsIndicators: false) {
				Text(.init(stringLiteral: play.comment ?? ""))
			}
			Spacer()
		}
    }
}

#Preview {
	ExtendedView(play: .fixture())
}
