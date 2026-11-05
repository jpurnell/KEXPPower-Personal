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
	private var playExpectation = PlayStateExpectation()

	public init() {
		// Tell the widget the moment playback starts or stops, not on the next five-second poll.
		playerController.onPlayingChange = { [weak self] _ in
			guard let self else { return }
			Task { await self.widgetPublisher.updatePlayState(isPlaying: self.publishedPlaying) }
		}
	}

	/// Whether to tell the widget the stream is playing: the state just asked for while it is current, else the real one.
	private var publishedPlaying: Bool {
		playExpectation.effective(actual: playerController.isPlaying, at: Date())
	}

	/// Publishes the state a play/pause request is about to produce, so the widget shows it at once.
	/// - Parameter playing: Whether the request will start (`true`) or pause (`false`) playback.
	func expectPlayState(_ playing: Bool) async {
		playExpectation.expect(playing: playing, until: Date().addingTimeInterval(6))
		await widgetPublisher.updatePlayState(isPlaying: playing)
	}

	private var isPolling: Bool { polling.task != nil }

	/// Starts following the station once; later calls do nothing, so several windows can each ask.
	func startIfNeeded() async {
		guard !isPolling else { return }
		await getResults()
	}

	/// Starts refreshing the playlist and show every five seconds, replacing any earlier loop.
	func getResults() async {
		polling.task?.cancel()
		// A UI test gets fixed songs and no stream, so it neither needs the network nor starts audio.
		if UITestFixtures.isActive() {
			plays = UITestFixtures.plays
			play = plays.first ?? .fixture()
			return
		}
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
			await widgetPublisher.update(play: plays.first, show: show, isPlaying: publishedPlaying)
		} catch {
			logger.error("Refresh failed: \(error.localizedDescription, privacy: .public)")
			// A failed poll must not let the widget's playing flag go stale while the stream is still playing.
			await widgetPublisher.updatePlayState(isPlaying: publishedPlaying)
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
