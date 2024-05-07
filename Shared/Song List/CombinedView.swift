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
				HStack {
					ImageView(play: play)
					.frame(
						minWidth: small ? 20 : 100,
						idealWidth: small ? 100 : 200,
						maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/,
						minHeight: small ?  20 : 100,
						idealHeight: small ? 100 : 200,
						maxHeight: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/,
						alignment: small ? .topLeading : .center
					)
					.padding(small ? [.top] : [.all])
					.animation(.easeInOut(duration: 1.0), value: 1.0)
					small ? CompactView(play: play).frame(minWidth: 200, idealWidth: 200, minHeight: 20, idealHeight: 100, maxHeight: 300, alignment: .topLeading).padding(.bottom, 5).padding(.vertical) : nil
				}
				small ? nil : ExtendedView(play: play)				
			}
		}).foregroundStyle(.black)
		}
	}
			   
#Preview {
		CombinedView(play: .fixture())
}
