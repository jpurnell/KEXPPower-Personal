//
//  SingleSongView.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 2/8/22.
//  Copyright © 2022 KEXP. All rights reserved.
//

import SwiftUI
import KEXPPower

struct SingleSongView: View {
    var play: Play
    
    var body: some View {
        VStack {
            AsyncImage(url: URL(string: play.imageURI ?? ""), scale: 1) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } placeholder: {
                if play.imageURI == "" {
                    Image(systemName: "music.note.list").font(.system(size: 75)) }
                else {
                    ProgressView().progressViewStyle(.circular)
                }
            }
            
            Text(play.song ?? "").fontWeight(.semibold)
            Text(play.artist ?? "").font(.caption)
            Text(play.album ?? "").font(.caption).foregroundColor(.gray)
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                Text(.init(stringLiteral: play.comment ?? ""))
//                            .font(.caption)
            }
			
            Spacer()
        }
		.padding()
    }
}

struct SingleSongView_Previews: PreviewProvider {
    static var previews: some View {
        SingleSongView(play: Play.fixture()).previewLayout(.sizeThatFits)
    }
}
