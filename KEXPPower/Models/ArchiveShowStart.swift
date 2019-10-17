//
//  ArchiveShowStart.swift
//  KEXPPower
//
//  Created by Dustin Bergman on 10/14/19.
//  Copyright © 2019 KEXP. All rights reserved.
//

import UIKit

public struct ArchiveShowStart {
    public let startTimeDisplay: String
    public let startTimeDate: Date
    public let startTimeEpochValue: Int
    
    public init(startTimeDisplay: String, startTimeDate: Date, startTimeEpochValue: Int) {
        self.startTimeDisplay = startTimeDisplay
        self.startTimeDate = startTimeDate
        self.startTimeEpochValue = startTimeEpochValue
    }
}

