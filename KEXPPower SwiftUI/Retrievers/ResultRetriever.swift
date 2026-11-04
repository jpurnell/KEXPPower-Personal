//
//  ResultRetriever.swift
//  KEXPPowerExampleSwiftUI (iOS)
//

import AVKit
import Foundation
import KEXPPower
import OSLog
import StationKit
import StationKitAdapterKEXP

@MainActor
@Observable
public class ResultRetriever {
	let logger = Logger(#function)
	let networkManager = NetworkManager()

	/// How many recent plays to keep on screen. The playlist is refreshed every few seconds,
	/// so this bounds each request and the memory held.
	static let playsPerRefresh = 50

	var plays: [Play] = []
	var play: Play = .fixture()
	var show: Show = Show.fixture(hosts: [0], programName: "Retrieving…", hostNames: ["Retrieving…"], tagline: "", imageURI: "")

	var playerController = PlayerController()

	private let polling = PollingTask()
	private let widgetPublisher = WidgetPublisher()

	private var isPolling: Bool { polling.task != nil }

	/// Starts following the station once; later calls do nothing, so several windows can each ask.
	func startIfNeeded() async {
		guard !isPolling else { return }
		await getResults()
	}

	/// Starts refreshing the playlist and show every five seconds, replacing any earlier loop.
	func getResults() async {
		polling.task?.cancel()
		// A refresh must not replace the player: that would cut off what is playing.
		if playerController.player == nil {
			let quality = StreamQuality.resolve(stored: UserDefaults.standard.string(forKey: StreamQuality.storageKey))
			let streams = KEXPStation().streams
			if let stream = streams.first(where: { $0.id == quality.rawValue }) ?? streams.first {
				playerController.initPlayer(link: stream.url)
			}
		}
		polling.task = Task { [weak self] in
			while !Task.isCancelled {
				await self?.refresh()
				try? await Task.sleep(for: .seconds(5))
			}
		}
	}

	private func refresh() async {
		do {
			let playResult = try await networkManager.getPlay(limit: Self.playsPerRefresh)
			plays = playResult.plays ?? []
			play = plays.first ?? .fixture()

			let showResult = try await networkManager.getShow(limit: 1)
			show = showResult.shows?.first ?? Show.fixture(hosts: [0], programName: "Retrieving…", hostNames: ["Retrieving…"])

			await playerController.updateNowPlaying(KEXPMapping.nowPlaying(from: plays.first))
			await widgetPublisher.update(play: plays.first, show: show, isPlaying: playerController.isPlaying)
		} catch {
			logger.error("Refresh failed: \(error.localizedDescription, privacy: .public)")
		}
	}
}

/// Holds the refresh loop and cancels it when the owner goes away.
private final class PollingTask {
	var task: Task<Void, Never>?

	deinit {
		task?.cancel()
	}
}
