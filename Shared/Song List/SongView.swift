//
//  PlayView.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 2/1/22.
//  Copyright © 2022 KEXP. All rights reserved.
//

import SwiftUI

struct SongView: View {
    var imageURL: String = "https://kexp.org/static/assets/img/kexp_logo.jpg"
    var playTime: Date = Date()
    var songName: String = "Song"
    var artistName: String = "Artist"
    var albumName: String = "Album"
    var year: String = "Year"
    var recordLabel: String = "Record Label"
    var comments: String = "Comments"
    var small: Bool = false
    
    var body: some View {
        VStack {
            HStack(alignment: .top) {
                //AsyncImage from https://stackoverflow.com/questions/60677622/how-to-display-image-from-a-url-in-swiftui
                //Resizing AsyncImage from https://blckbirds.com/post/how-to-use-asyncimage-in-swiftui/
                AsyncImage(url: URL(string: imageURL), scale: 1) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    if imageURL == "" {
                        Image(systemName: "music.note.list").font(.system(size: 75)) }
                    else {
                        ProgressView().progressViewStyle(.circular)
                    }
                }
				.clipShape(RoundedRectangle(cornerRadius: 36.0))
				.shadow(color: .black.opacity(0.3), radius: 6, x: 1.0, y: 1.0)
                .frame(minWidth: 20, idealWidth: 200, maxWidth: 200, minHeight: 20, idealHeight: 100, maxHeight: 200, alignment: .topLeading)
				
                VStack(alignment: .leading) {
					Text(DateFormatter.displayFormatterWithDate.string(from: playTime))
//						.font(.caption)
                    Text(songName).bold()
                    Text(artistName).fontWeight(.light)
                    Text(albumName).font(.caption)
                    HStack(alignment: .top) {
                        Text(year)
                        Text(recordLabel)
                    }
//					.font(.caption)
                }
                .frame(minWidth: 100, idealWidth: 200, maxWidth: 200, minHeight: 20, idealHeight: 100, maxHeight: 200, alignment: .topLeading)
            }.padding(.bottom, 5)
//            ScrollView(.vertical, showsIndicators: true) {
//                Text(.init(stringLiteral: comments))
////                    .font(.caption)
//            }
			.padding(.vertical)
        }
    }
}

struct SongView_Previews: PreviewProvider {
    static var previews: some View {
        SongView().previewLayout(.sizeThatFits)
    }
}
