//
//  AppleMusicResult.swift
//  KEXPPower
//
//  Created by Dustin Bergman on 10/24/19.
//  Copyright © 2019 KEXP. All rights reserved.
//

import Foundation

// MARK: - AppleMusicResult

public struct AppleMusicResult: Decodable {
    public let resultCount: Int?
    public let results: [SearchTrack]?
    
//    enum CodingKeys: String, CodingKey {
//        case resultCount
//        case results
//    }
}

// MARK: - SearchTrack

public struct SearchTrack: Decodable {
    public let trackViewUrl: URL?
    
//    enum CodingKeys: String, CodingKey {
//        case trackViewUrl
//    }
}

extension SearchTrack {
	public static func fixture(trackViewUrl: URL = URL(string: "https://music.apple.com/us/album/this-year/1445589195?i=1445589202&uo=4")!) -> SearchTrack {
		return SearchTrack(trackViewUrl: trackViewUrl)
	}
}

extension AppleMusicResult {
	public static func fixture(resultCount: Int = 1, results: [SearchTrack] = [.fixture()]) -> AppleMusicResult {
		return AppleMusicResult(resultCount: resultCount, results: results)
	}
}
