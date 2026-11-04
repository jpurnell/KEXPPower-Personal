//
//  VideoPlayer.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 5/8/24.
//  Copyright © 2024 KEXP. All rights reserved.
//

import Foundation
import SwiftUI
import AVKit

#if os(iOS) || os(visionOS)
// A SwiftUI view wrapper for an AVPlayerViewController
struct VideoPlayer: UIViewControllerRepresentable {
	// MARK: - Player
	
	// Manages the underlying AVPlayer and its playback state
	let playerController: PlayerController
	
	// MARK: - UIViewControllerRepresentable Protocol Methods
	
	// Update the AVPlayerViewController when SwiftUI view updates
	func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
		// Update the view controller if needed
		// (e.g., handle updates when the underlying AVPlayer changes
	}
	
	// Create and configure the AVPlayerViewController
	func makeUIViewController(context: Context) -> AVPlayerViewController {
		return playerController.avPlayerViewController
	}
}
#endif
