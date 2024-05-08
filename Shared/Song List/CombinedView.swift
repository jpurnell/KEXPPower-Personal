	//
	//  CombinedView.swift
	//  KEXPPowerExampleSwiftUI (iOS)
	//
	//  Created by Justin Purnell on 5/7/24.
	//  Copyright © 2024 KEXP. All rights reserved.
	//

import SwiftUI

struct CombinedView: View {
	@State var play: Play
	var imageURL: String = "https://kexp.org/static/assets/img/kexp_logo.jpg"
	var playTime: String = RelativeDateTimeFormatter().string(for: Date())!
	var songName: String = "Song"
	var artistName: String = "Artist"
	var albumName: String = "Album"
	var year: String = "Year"
	var recordLabel: String = "Record Label"
	var comments: String = "Comments"
	@State var small: Bool = true
	
	var body: some View {
		Button(action: {
			small.toggle()
		},
			   label: {
			VStack{
				HStack(alignment: .center) {
					ImageView(play: play)
					.frame(
						minWidth: small ? 100 : 220,
						idealWidth: small ? 100 : 400,
						maxWidth: small ? 100 : 220,
						minHeight: small ?  100 : 100,
						idealHeight: small ? 100 : 400
					)
					.padding(small ? [.vertical] : [.all])
					.animation(.easeInOut(duration: 1.0), value: 1.0)
					small ? CompactView(play: play)
						.padding(.leading, 5)
						.padding(.vertical) : nil
				}
				small ? nil : ExtendedView(play: play)
					.frame(
						minWidth: 200,
						idealWidth: 200,
						maxWidth: .infinity,
						minHeight: 100,
						idealHeight: 200,
						maxHeight: 500,
						alignment: .center
					)
					.padding(.bottom, 5).padding(.vertical)
			}
		}).foregroundStyle(.black)
		}
	}
			   
#Preview {
	CombinedView(play: .fixture()).previewLayout(.sizeThatFits).previewDevice(.none)
}
