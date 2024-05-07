//
//  ArchiveStreamResult.swift
//  KEXPPower
//
//  Created by Dustin Bergman on 10/9/19.
//  Copyright © 2019 KEXP. All rights reserved.
//

import Foundation

public struct ArchiveStreamResult: Decodable {
    public var streamURL: URL?
    public var nextStreamURL: URL?
    public var offset: Double?
    
    enum CodingKeys: String, CodingKey {
        case streamURL = "sg-url"
        case nextStreamURL = "sg-url-next"
        case offset = "sg-offset"
    }
}
