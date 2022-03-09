//
//  Play Fixture.swift
//  KEXPPower
//
//  Created by Justin Purnell on 2/8/22.
//  Copyright © 2022 KEXP. All rights reserved.
//

import Foundation

extension Play {
    public static func fixture(id: Int? = 3000448,
                uri: String? = "https://api.kexp.org/v2/plays/3000448/",
                airdate: Date? = Date(),
                show: Int? = 52837,
                showURI: String? = "https://api.kexp.org/v2/shows/52837/",
                imageURI: String? = "https://coverartarchive.org/release/64d16be8-0039-4c74-86ed-4d16b61ed59b/5133157385-500.jpg",
                thumbnailURI: String? = "https://coverartarchive.org/release/64d16be8-0039-4c74-86ed-4d16b61ed59b/5133157385-250.jpg",
                comment: String? = "Songs on the album were composed by guitarists Joe Strummer and Mick Jones, with the notable exception of the reggae cover \"Police and Thieves\". Several songs from these sessions, including \"Janie Jones\", \"White Riot\", and \"London\'s Burning\" became classics of the punk genre and were among the first punk songs to see significant presence on singles charts. The album featured Jones and Strummer sharing guitar and vocal duties, with Paul Simonon on bass and Terry Chimes on drums.",
                playType: PlayType? = PlayType.trackplay,
                song: String? = "Complete Control",
                trackID: String? = "",
                recordingID: String? = "b5f07e55-fed3-4621-aa93-c140cdfc2138",
                artist: String? = "The Clash",
                artistIDs: [String]? = ["8f92558c-2baa-4758-8c38-615519e9deda"],
                album: String? = "The Clash",
                releaseID: String? = "",
                releaseGroupID: String? = "ca91cb5a-7ecc-3c46-84a0-0d4951889374",
                labels: [String]? = ["Epic"],
                labelIDs: [String]? = ["8f638ddb-131a-4cc3-b3d4-7ebdac201b55"],
                releaseDate: String? = "1977-04-08",
                rotationStatus: String? = "R/N",
                isLocal: Bool? = false,
                isRequest: Bool? = true,
                isLive: Bool? = false) -> Play {
        Play(
            id: id,
            uri: uri,
            airdate: airdate,
            show: show,
            showURI: showURI,
            imageURI: imageURI,
            thumbnailURI: thumbnailURI,
            comment: comment,
            playType: playType,
            song: song,
            trackID: trackID,
            recordingID: recordingID,
            artist: artist,
            artistIDs: artistIDs,
            album: album,
            releaseID: releaseID,
            releaseGroupID: releaseGroupID,
            labels: labels,
            labelIDs: labelIDs,
            releaseDate: releaseDate,
            rotationStatus: rotationStatus,
            isLocal: isLocal,
            isRequest: isRequest,
            isLive: isLive)
    }
}
