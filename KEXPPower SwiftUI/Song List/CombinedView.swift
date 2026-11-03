//
//  CombinedView.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 5/7/24.
//  Copyright © 2024 KEXP. All rights reserved.
//

import OSLog
import SwiftUI
import KEXPPower

struct CombinedView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var play: Play?
    var imageURL: String = "https://kexp.org/static/assets/img/kexp_logo.jpg"
    @State var small: Bool = true

    var body: some View {
        ZStack {
//            // Bottom Layer: Large blurred ImageView
            ImageView(play: play ?? .fixture())
				.scaledToFill()
                .blur(radius: reduceTransparency ? 0 : 20)
                .frame(maxWidth: 500)
				.clipped()
				.frame(minHeight: 0, maxHeight: small ? 120 : 200)

            // Middle Layer: UltraThinMaterial overlay
            Rectangle()
                .fill(reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.ultraThinMaterial))
				.scaledToFill()
				.frame(minHeight: 0, maxHeight: small ? 120 : .infinity)
//				.border(Color.blue)

            // Button and other content can go here
			Button(action: {
						small.toggle()
					},
						   label: {
						VStack{
							HStack {
								ImageView(play: play ?? .fixture())
								.frame(
									minWidth: small ? 120 : 200,
									idealWidth: small ? 120 : 400,
									maxWidth: small ? 120 : 400,
									minHeight: small ?  120 : 120,
									idealHeight: small ? 120 : 400
								)
								.padding(small ? [.vertical] : [.all])
								(small ? CompactView(play: play ?? .fixture())
									.frame(minWidth: 200, maxWidth: .infinity)
									.padding(.leading)
									.padding(.vertical) : nil)
//									.border(Color.orange)
							}
							(small ? nil : ExtendedView(play: play ?? .fixture()))
								.frame(
									minWidth: 200,
									idealWidth: 200,
									maxWidth: 340,
									minHeight: 100,
									idealHeight: 200,
									maxHeight: 400,
									alignment: .center
								)
								.clipped()
								.padding(.bottom, 5).padding(.vertical)
//								.border(Color.yellow)
						}
					})
            .foregroundStyle(.primary)
            .padding(8)
            .onAppear(perform: {
                //				let logger = Logger(#function)
                //				logger.debug("Displaying Combined view for \(play?.description ?? "Default Play", privacy: .public)")
            })
        }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    CombinedView(play: .fixture())
}
