//
//  AppleMusicRetriever.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 5/22/24.
//  Copyright © 2024 KEXP. All rights reserved.
//

import Foundation
import KEXPPower

@MainActor
@Observable
public class AppleMusicRetriever {
	var appleMusicURL: URL?
	
	func getAppleMusicResult(artist: String, track: String, album: String) async throws -> URL? {
		do {
			let appleMusicResult = try await NetworkManager().getAppleMusicLink(artist: artist, track: track, album: album)
			if let appleMusicURL = (appleMusicResult.results?.first?.trackViewUrl) {
//				logger.debug("Got URL: \(appleMusicURL)")
				return appleMusicURL
			}
		} catch {
			return nil
		}
		return nil
	}
}
