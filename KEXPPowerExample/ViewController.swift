//
//  ViewController.swift
//  KEXPPowerExample
//
//  Created by Dustin Bergman on 6/30/19.
//  Copyright © 2019 KEXP. All rights reserved.
//

import KEXPPower
import UIKit
import OSLog

class ViewController: UIViewController {
    let networkManager = NetworkManager()
    let archiveManager = ArchiveManager()
	let viewControllerLogger = Logger(subsystem: "KEXP Power Example > View Controller", category: "View Controller")
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .white
        
        networkManager.getPlay { result in
			viewControllerLogger.log("playResult: \(result, privacy: .public)")
        }

        networkManager.getShow { result in
			viewControllerLogger.log("showResult: \(result, privacy: .public)")
        }

        networkManager.getShowDetails(with: "47008") { result in
			viewControllerLogger.log("showDetailsResult: \(result, privacy: .public)")
        }
   
        let now = Int(Date().timeIntervalSince1970)
        let oneWeekAgo = now - 604800

        networkManager.getShowStart(with: "\(oneWeekAgo)") { result in
			viewControllerLogger.log("showStartResult: \(result, privacy: .public)")
        }
        
        archiveManager.retrieveArchiveShows { dateShows, hostShows, shows, genreShows in
			viewControllerLogger.log("retrieveArchiveShows: \(dateShows, privacy: .public)")
        }
    }
}

