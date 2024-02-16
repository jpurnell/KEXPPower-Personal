//
//  KEXPPower.swift
//  KEXPPower
//
//  Created by Dustin Bergman on 7/8/19.
//  Copyright © 2019 KEXP. All rights reserved.
//

import Foundation
import OSLog

/// Class used to configure KEXP networking
public class KEXPPower {
    /// Available archive bit rates
    public enum StreamingBitRate: Int {
        case sixtyFour
        case oneSixty
    }
    
    /// Singleton access to KEXPower
    public static let sharedInstance = KEXPPower()
    
    /// User's selected archive bitrate
    public var selectedBitRate: StreamingBitRate!

    // Generate a random UUID that will be passed to StreamGuys in order to identify this particular
    // streaming "session"
    let listenerId: UUID = .init()

    var playURL: URL {
		let playURLLogger = Logger(subsystem: "KEXPPower > Public API > KEXPPower", category: "play URL")
		playURLLogger.info("Attempting \(KEXPPower.sharedInstance.kexpBaseURL)")
		guard let returnURL = try URL(string: KEXPPower.sharedInstance.kexpBaseURL + "/v2/plays") else {
			let defaultReturnURL = URL(string: "https://kexp.streamguys1.com/kexp160.aac?listenerId=\(UUID())")!
			playURLLogger.log("opening  \(defaultReturnURL.absoluteString, privacy: .public)")
			return defaultReturnURL }
		return returnURL
    }
    var showURL: URL {
        URL(string: KEXPPower.sharedInstance.kexpBaseURL + "/v2/shows")!
    }
    
    var showStartURL: URL {
        URL(string: KEXPPower.sharedInstance.kexpBaseURL + "/get_show_start/")!
    }
            
    var streamingURL: URL {
        URL(string: KEXPPower.sharedInstance.kexpBaseURL + "/get_streaming_url")!
    }

    private var kexpBaseURL: String

    /// Configure KEXPPower
    /// - Parameters:
    ///   - kexpBaseURL: Base URL for making network requests
    ///   - selectedBitRate: User's selected bitrate
    public func setup(kexpBaseURL: String, selectedBitRate: StreamingBitRate) {
        self.kexpBaseURL = kexpBaseURL
        self.selectedBitRate = selectedBitRate
    }
    
    public var streamURL: URL {
        let availableStreams = AvailableStreams(with: KEXPPower.sharedInstance.listenerId)
        
        return availableStreams.livePlayback[KEXPPower.sharedInstance.selectedBitRate] ??
            URL(string: "https://kexp.streamguys1.com/kexp64.aac?listenerId=\(listenerId.uuidString)")!
    }
    
    static func getShowURL(with showId: String) -> URL {
		guard let returnURL = URL(string: KEXPPower.sharedInstance.kexpBaseURL + "/v2/shows/\(showId)") else { return URL(string: "")! }
		return returnURL
    }

    private init(){
		self.kexpBaseURL = "https://api.kexp.org"
		self.selectedBitRate = .oneSixty
	}
    
	public static func fixture(kexpBaseURL: String? = "https://api.kexp.org", selectedBitRate: StreamingBitRate = .oneSixty) -> KEXPPower {
        let sharedInstance = KEXPPower()
        sharedInstance.setup(kexpBaseURL: kexpBaseURL ?? "", selectedBitRate: selectedBitRate)
        return sharedInstance
    }
}
