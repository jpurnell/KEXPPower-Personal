//
//  TestView.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 5/21/24.
//  Copyright © 2024 KEXP. All rights reserved.
//

import SwiftUI
import OSLog

struct TestView: View {
	var play: Play = .fixture()
	var imageURL: String = "https://kexp.org/static/assets/img/kexp_logo.jpg"
	@State var small: Bool = true
	
	var body: some View {
		VStack {
			CombinedView(play: play, small: false)
//			AsyncImage(url: URL(string: play.imageURI ?? imageURL))
//			Text(play.song ?? "")
		}
		
		
//		Button(action: {
//			small.toggle()
//		},
//			   label: {
//			VStack{
//				HStack {
//					ImageView(play: play ?? .fixture())
//					.frame(
//						minWidth: small ? 120 : 200,
//						idealWidth: small ? 120 : 500,
//						maxWidth: small ? 120 : 500,
//						minHeight: small ?  120 : 120,
//						idealHeight: small ? 120 : 500
//					)
//					.animation(.easeInOut(duration: 1.0), value: 1.0)
//					.padding(small ? [.vertical] : [.all])
//					(small ? CompactView(play: play ?? .fixture())
//						.frame(minWidth: 200, maxWidth: .infinity)
//						.padding(.leading)
//						.padding(.vertical) : nil)
//						.animation(.easeInOut(duration: 1.0), value: 1.0)
//				}
//				(small ? nil : ExtendedView(play: play ?? .fixture()))
//					.animation(.easeInOut(duration: 1.0), value: 1.0)
//					.frame(
//						minWidth: 200,
//						idealWidth: 200,
//						maxWidth: .infinity,
//						minHeight: 100,
//						idealHeight: 200,
//						maxHeight: 500,
//						alignment: .center
//					)
//					.padding(.bottom, 5).padding(.vertical)
//			}
//		})
//		.foregroundStyle(.primary)
		.onAppear(perform: {
//			let logger = Logger(#function)
//			logger.debug("Displaying Combined view for \(play.description, privacy: .public)")
		})
	}
}

#Preview {
    TestView()
}
