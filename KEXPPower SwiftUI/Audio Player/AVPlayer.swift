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

#if os(iOS) || os(visionOS)

@MainActor
class PlayerController: ObservableObject {
	
	//MARK: – Published Properties
	
	// Published properties to trigger UI Updates when changed
	@Published var playbackVideoLink: String = ""
	@Published var playbackTitle: String = ""
	@Published var playbackAlbum: String = ""
	@Published var playbackArtist: String = ""
	@Published var playbackArtwork: String = ""
	@Published var isPlaying: Bool = false
	let logger = Logger(#function)
	var nowPlayingInfo: [String: Any] = [:]
	
	// MARK: - AVPlayer and AVPlayerViewController Properties
	
	var player: AVPlayer?
	var avPlayerViewController: AVPlayerViewController = AVPlayerViewController()
	// MARK: - Initialization and Setup
	
	@MainActor func initPlayer(link: URL = URL(string: "")!, title: String = "", album: String = "", artist: String = "", artwork: String = "") {
		logger.debug("Initiating PlayerController for \(title, privacy: .public)")
		self.playbackVideoLink = link.absoluteString
		self.playbackTitle = title
		self.playbackAlbum = album
		self.playbackArtist = artist
		self.playbackArtwork = artwork
		
		setupPlayer(link)
		setupAVPlayerViewController()
		setupRemoteTransportControls()
		setupNotificationView()
	}
	
	
	private func setupPlayer(_ url: URL = URL(string: "")!) {
		// Initialize AVPlayer with the provided link
		player = AVPlayer(url: url)
		#if os(iOS)
		player?.allowsExternalPlayback = true
		#endif
		// Set up metadata for the current item
		setupMetadata()
	}
	
	private func setupMetadata() {
		let title = AVMutableMetadataItem()
		title.identifier = .commonIdentifierTitle
		title.value = playbackTitle as NSString
		
		let album = AVMutableMetadataItem()
		album.identifier = .commonIdentifierAlbumName
		album.value = playbackAlbum as NSString
		
		let artist = AVMutableMetadataItem()
		artist.identifier = .commonIdentifierArtist
		artist.value = playbackArtist as NSString
		
		var artwork = AVMutableMetadataItem()
		Task {
			artwork = await setupArtworkMetadata(playbackArtwork).0
		}
		
		// Set external Metadata for the current AVPlayerItem
		player?.currentItem?.externalMetadata = [title, album, artist, artwork]
	}
	
	private func setupArtworkMetadata(_ artwork: String = "https://kexp.org/static/assets/img/kexp_logo.jpg") async -> (AVMutableMetadataItem, UIImage) {
		let artworkMetadata = AVMutableMetadataItem()
		artworkMetadata.identifier = .commonIdentifierArtwork
		artworkMetadata.value = artwork as NSString
		
		guard let url = URL(string: artwork) else { return (artworkMetadata, UIImage(systemName: "music.note")!) }
		
		let (data, _) = try! await URLSession.shared.data(from: url)
				
		guard let image = UIImage(data: data) else { return (artworkMetadata, UIImage(systemName: "music.note")!) }
		
		if let imageData = image.jpegData(compressionQuality: 1.0) {
			artworkMetadata.identifier = .commonIdentifierArtwork
			artworkMetadata.value = imageData as NSData
			artworkMetadata.dataType = kCMMetadataBaseDataType_JPEG as String
		}
		return (artworkMetadata, image)
	}
		
	// MARK: - AVPlayerViewController Setup
	
	@MainActor private func setupAVPlayerViewController() {
		// Assign AVPlayer to AVPlayerViewController
		avPlayerViewController.player = player
		avPlayerViewController.showsPlaybackControls = true
		avPlayerViewController.updatesNowPlayingInfoCenter = true
	}
	
	func setupRemoteTransportControls() {
		let commandCenter = MPRemoteCommandCenter.shared()
		
		commandCenter.playCommand.isEnabled = true
		commandCenter.playCommand.addTarget { [unowned self] event in
			if !self.isPlaying {
				player?.play()
				isPlaying.toggle()
				return .success
			}
			return .commandFailed
		}
		
		commandCenter.pauseCommand.isEnabled = true
		commandCenter.pauseCommand.addTarget { [unowned self] event in
			if self.isPlaying {
				player?.pause()
				isPlaying.toggle()
				return .success
			}
			return .commandFailed
		}
		
	}
	
	func setupNotificationView() {
		guard var nowPlayingInfo = player?.currentItem?.nowPlayingInfo else { logger.warning("Could not set up Now Playing info"); return }
		
		nowPlayingInfo[MPMediaItemPropertyTitle] = playbackTitle
		nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = playbackAlbum
		nowPlayingInfo[MPMediaItemPropertyArtist] = playbackArtist
		Task {
			let artwork = await setupArtworkMetadata(playbackArtwork).1
			nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size, requestHandler: { (size) -> UIImage in
			return artwork })
		}
		let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
		var info: [String: Any] = [:]
		info.updateValue(playbackTitle, forKey: MPMediaItemPropertyTitle)
		info.updateValue(playbackAlbum, forKey: MPMediaItemPropertyAlbumTitle)
		info.updateValue(playbackArtist, forKey: MPMediaItemPropertyArtist)
		info.updateValue(playbackArtwork, forKey: MPMediaItemPropertyArtwork)
		
		nowPlayingInfoCenter.nowPlayingInfo = info
//		logger.debug("Now Playing:\n\(nowPlayingInfoCenter.nowPlayingInfo.map({"\($0.key)\t\($0.value)"}).joined(separator: "\n"))")
	}
	
	func updateNotificationView(_ song: String, artist: String, album: String, artwork: String) async -> Bool {
		let updatedTitle = AVMutableMetadataItem()
		updatedTitle.identifier = .commonIdentifierTitle
		updatedTitle.value = song as NSString
		
		let updatedAlbum = AVMutableMetadataItem()
		updatedAlbum.identifier = .commonIdentifierAlbumName
		updatedAlbum.value = album as NSString
		
		let updatedArtist = AVMutableMetadataItem()
		updatedArtist.identifier = .commonIdentifierArtist
		updatedArtist.value = artist as NSString
		
		let updatedArtwork = await setupArtworkMetadata(artwork)
		
		player?.currentItem?.externalMetadata = [updatedTitle, updatedAlbum, updatedArtist, updatedArtwork.0]
		nowPlayingInfo.updateValue(song, forKey: MPMediaItemPropertyTitle)
		nowPlayingInfo.updateValue(artist, forKey: MPMediaItemPropertyArtist)
		nowPlayingInfo.updateValue(album, forKey: MPMediaItemPropertyAlbumTitle)
		Task {
			let artwork = await setupArtworkMetadata(artwork).1
			nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size, requestHandler: { (size) -> UIImage in
			return artwork })
		}
		player?.currentItem?.nowPlayingInfo = nowPlayingInfo
		let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
		nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
		
		return true
	}
	
	func setNowPlayingMetadata(_ song: String, artist: String, album: String, artwork: String) async -> Bool {
	   
		let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
		var nowPlayingInfo = [String: Any]()
		
		logger.log(level: .info, "**** Set track metadata: title \(song)")
		nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = true
		nowPlayingInfo[MPMediaItemPropertyTitle] = song
		nowPlayingInfo[MPMediaItemPropertyArtist] = artist
		nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
		nowPlayingInfo[MPMediaItemPropertyAlbumArtist] = artist
		nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = album
		
		nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
		return true
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
