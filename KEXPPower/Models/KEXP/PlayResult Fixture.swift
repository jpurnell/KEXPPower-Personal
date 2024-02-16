//
//  PlayResult Fixture.swift
//  KEXPPower
//
//  Created by Justin Purnell on 2/8/22.
//  Copyright © 2022 KEXP. All rights reserved.
//

import Foundation

extension PlayResult {
    public static func fixture(next: String?, previous: String? = "", plays: [Play] = [Play.fixture()]) -> PlayResult {
//        PlayResult(next: next, previous: previous, plays: plays)
		PlayResult(next: next, previous: previous)
    }
}
