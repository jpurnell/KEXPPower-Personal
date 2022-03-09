//
//  ShowResult Fixture.swift
//  KEXPPower
//
//  Created by Justin Purnell on 2/8/22.
//  Copyright © 2022 KEXP. All rights reserved.
//

import Foundation

extension ShowResult {
    public static func fixture(count: Int?  = 0, next: String? = "", previous: String? = "", shows: [Show] = [Show.fixture()]) -> ShowResult {
        ShowResult(count: count, next: next, previous: previous, shows: shows)
    }
}
