//
//  Show Fixture.swift
//  KEXPPower
//
//  Created by Justin Purnell on 2/8/22.
//  Copyright © 2022 KEXP. All rights reserved.
//

import Foundation

extension Show {
    public static func fixture(id: Int = 52837,
                               uri: String? = "https://api.kexp.org/v2/shows/52837/",
                               program: Int? =  14,
                               programURI: String? = "https://api.kexp.org/v2/programs/14/",
                               hosts: [Int]? = [55],
                               hostsURIs: [String]? = ["https://api.kexp.org/v2/hosts/55/"],
                               programName: String? = "The Afternoon Show",
                               programTags: String? = "Rock,Eclectic,Variety Mix",
                               hostNames:[String]? = ["Larry Mizell, Jr."],
                               tagline: String? = "Happy INTERNATIONAL CLASH DAY! Today we\'ll be coming out the Most Important Band in the world via dub, reggae, post-punk, covers and interview clips!",
                               imageURI: String? = "https://www.kexp.org/media/filer_public/5e/ed/5eed57ed-2169-45b8-8605-266712b6eee3/larry_mizell_jr_thumbnail.png",
                               startTime: Date? = Date()) -> Show {
        Show(id: id, uri: uri, program: program, programURI: programURI, hosts: hosts, hostURIs: hostsURIs, programName: programName, programTags: programTags, hostNames: hostNames, tagline: tagline, imageURI: imageURI, startTime: startTime)
    }
    
}
