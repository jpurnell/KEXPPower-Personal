//
//  AVPlayer.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 5/8/24.
//  Copyright © 2024 KEXP. All rights reserved.
//

import Foundation
import AVKit
import MediaPlayer
import OSLog

#if os(iOS)
class PlayerController: ObservableObject {
	//MARK: – Published Properties
	
	// Published properties to trigger UI Updates when changed
	@Published var playbackVideoLink: String = ""
	@Published var playbackTitle: String = ""
	@Published var playbackArtist: String = ""
	@Published var playbackArtwork: String = ""
	@Published var isPlaying: Bool = false
	let logger = Logger(#function)
	
	// MARK: - AVPlayer and AVPlayerViewController Properties
	
	var player: AVPlayer?
	var avPlayerViewController: AVPlayerViewController = AVPlayerViewController()
	
	// MARK: - Initialization and Setup
	
	@MainActor func initPlayer(link: URL = URL(string: "")!, title: String = "", artist: String = "", artwork: String = "") {
		self.playbackVideoLink = link.absoluteString
		self.playbackTitle = title
		self.playbackArtist = artist
		self.playbackArtwork = artwork
		
		setupPlayer(link)
		setupAVPlayerViewController()
		setupRemoteTransportControls()
	}
	
	private func setupPlayer(_ url: URL = URL(string: "")!) {
		// Initialize AVPlayer with the provided link
		player = AVPlayer(url: url)
		
		// Set up metadata for the current item
		setupMetadata()
	}
	
	private func setupMetadata() {
		let title = AVMutableMetadataItem()
		title.identifier = .commonIdentifierTitle
		title.value = playbackTitle as NSString
		
		let artist = AVMutableMetadataItem()
		artist.identifier = .commonIdentifierArtist
		artist.value = playbackArtist as NSString
		
		let artwork = AVMutableMetadataItem()
		setupArtworkMetadata(artwork)
		
		// Set external Metadata for the current AVPlayerItem
		player?.currentItem?.externalMetadata = [title, artist, artwork]
	}
	
	
	private func setupArtworkMetadata(_ artwork: AVMutableMetadataItem) {
		if let url = URL(string: artwork.stringValue ?? "https://kexp.org/static/assets/img/kexp_logo.jpg") {
			let task = URLSession.shared.dataTask(with: url) { data, response, error in
				if let error = error { self.logger.error("Could not retrieve url.\(error.localizedDescription)") }
				else if let data = data {
					if let image = UIImage(data: data) {
						if let imageData = image.jpegData(compressionQuality: 1.0) {
							artwork.identifier = .commonIdentifierArtwork
							artwork.value = imageData as NSData
							artwork.dataType = kCMMetadataBaseDataType_JPEG as String
						}
					}
				}
			}
		}
	}
	
	// MARK: - AVPlayerViewController Setup
	
	@MainActor private func setupAVPlayerViewController() {
		// Assign AVPlayer to AVPlayerViewController
		avPlayerViewController.player = player
		avPlayerViewController.allowsPictureInPicturePlayback = true
		avPlayerViewController.canStartPictureInPictureAutomaticallyFromInline = true
		avPlayerViewController.allowsVideoFrameAnalysis = true
		avPlayerViewController.showsPlaybackControls = true
		avPlayerViewController.showsTimecodes = true
		avPlayerViewController.updatesNowPlayingInfoCenter = true

	}
	
	func setupRemoteTransportControls() {
		let commandCenter = MPRemoteCommandCenter.shared()
		
		commandCenter.playCommand.isEnabled = true
		commandCenter.playCommand.addTarget { [unowned self] event in
			if !self.isPlaying {
				player?.play()
				return .success
			}
			return .commandFailed
		}
		
		commandCenter.pauseCommand.isEnabled = true
		commandCenter.pauseCommand.addTarget { [unowned self] event in
			if self.isPlaying {
				player?.pause()
				return .success
			}
			return .commandFailed
		}
		
	}

	
	// MARK: - Playback Control
	
	func pausePlayer() {
		player?.pause()
	}
	
	func playPlayer() {
		player?.play()
	}
	
	func playOrPause() {
		isPlaying ? pausePlayer() : playPlayer()
		isPlaying.toggle()
	}
	
	// Set up metadata for the current AVPlayerItem
}
#endif
