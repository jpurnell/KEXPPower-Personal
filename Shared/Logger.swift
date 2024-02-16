//
//  Logger.swift
//  KEXPPower
//
//  Created by Justin Purnell on 2/15/24.
//  Copyright © 2024 KEXP. All rights reserved.
//

import Foundation
import OSLog

@available(macOS 11.0, *)
extension Logger {
	init(_ function: String, _ filePath: String = #file, _ depth: Int = 3, _ separator: String = " > ") {
		let fileName = filePath.components(separatedBy: "/").suffix(depth).joined(separator: separator)
		if let bundleIdentifier = Bundle.main.bundleIdentifier {
			self.init(subsystem: "\(bundleIdentifier)\(bundleIdentifier != "" ? separator : "")\(fileName)", category: "\(function)")
		} else {
			self.init(subsystem: "\(fileName)", category: "\(function)")
		}
	}
}
