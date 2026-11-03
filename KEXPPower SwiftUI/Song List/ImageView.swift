//
//  ImageView.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 5/7/24.
//  Copyright © 2024 KEXP. All rights reserved.
//

import SwiftUI
import KEXPPower

struct ImageView: View {
	var play: Play?
	func imageURL() -> String { return (play?.song == nil || play?.playType == .airbreak) ? "https://kexp.org/static/assets/img/kexp_logo.jpg" : "https://www.kexp.org/static/assets/img/default.png" }
    var body: some View {
		AsyncImage(url: URL(string: play?.imageURI ?? imageURL()), scale: 1) { image in
			image
				.resizable()
				.aspectRatio(contentMode: .fit)
		} placeholder: {
			if play?.imageURI == "" {
				AsyncImage(url: URL(string: imageURL()), scale: 1) {
					image in
					image.image?.resizable()
						.aspectRatio(contentMode: .fit)
				}
			}
			else {
				ProgressView().progressViewStyle(.circular)
			}
		}
		.clipShape(RoundedRectangle(cornerRadius: 5.0))
		.shadow(
			color: .primary.opacity(0.3),
			radius: 5.0,
			x: 1.0,
			y: 1.0
		)
    }
}

#Preview {
	ImageView(play: .fixture())
}
