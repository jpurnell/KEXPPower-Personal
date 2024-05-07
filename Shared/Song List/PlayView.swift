//
//  PlayView.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 2/1/22.
//  Copyright © 2022 KEXP. All rights reserved.
//

import SwiftUI
//import KEXPPower

struct PlayView: View {
    var play: Play
    
    var body: some View {
		play.song == "" ? SongView(imageURL: "https://kexp.org/static/assets/img/kexp_logo.jpg", playTime: play.airtime, songName: "Airbreak", artistName: "KEXP", albumName: "", year: "", recordLabel: "", comments: "", small: true) :
		SongView(imageURL: play.thumbnailURI ?? "", playTime: play.airtime, songName: play.song ?? "", artistName: play.artist ?? "", albumName: play.album ?? "", year: play.releaseDate ?? "", recordLabel: play.labels?.map({$0}).joined(separator: "\n") ?? "", comments: play.comment ?? "")
    }
}

struct PlayView_Previews: PreviewProvider {
    static var previews: some View {
        PlayView(play: Play.fixture())
            .previewLayout(.sizeThatFits)
    }
}
