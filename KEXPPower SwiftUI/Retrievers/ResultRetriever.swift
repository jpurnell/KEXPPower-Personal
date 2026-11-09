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

	/// The station's recent plays as it reported them, newest first: what is on the air.
	var latestPlays: [Play] = []
	/// The plays up to what the listener is hearing, which is behind the air when live is paused or rewound.
	var plays: [Play] { HeardPlays.plays(latestPlays, behind: playerController.heardLag, now: Date()) }
	/// The song being heard.
	var play: Play { plays.first ?? .fixture() }
	/// Shown as the show's name until the first one has arrived.
	static let retrievingName = "Retrieving…"
	var show: Show = Show.fixture(hosts: [0], programName: ResultRetriever.retrievingName, hostNames: [ResultRetriever.retrievingName], tagline: "", imageURI: "")

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

	/// Starts following the station and waits until the first playlist has arrived, for a caller that must answer from it.
	///
	/// A cold launch from Siri or CarPlay has no window to ask for the fetch, and `startIfNeeded` returns before the first
	/// reply, so the playlist is still empty when it does. A failed fetch leaves it empty.
	func firstResults() async {
		await startIfNeeded()
		if latestPlays.isEmpty { await refresh() }
	}

	/// Starts refreshing the playlist and show every five seconds, replacing any earlier loop.
	func getResults() async {
		polling.task?.cancel()
		// A UI test gets fixed songs and no stream, so it neither needs the network nor starts audio.
		if UITestFixtures.isActive() {
			latestPlays = UITestFixtures.plays
			return
		}
		// A refresh must not replace the player: that would cut off what is playing.
		if playerController.player == nil, let live = Self.liveStream(for: ListeningSettings.current()) {
			playerController.initPlayer(link: live.url)
			// With a rewind window on, live plays through a recording of the stream; off, directly as before.
			playerController.liveShift = live.shift
		}
		polling.task = Task { [weak self] in
			while !Task.isCancelled {
				await self?.refresh()
				try? await Task.sleep(for: .seconds(5))
			}
		}
	}

	/// The live stream for a set of settings: the address at the chosen quality, and its recording if a window is kept.
	/// - Parameter settings: The listener's quality and rewind window.
	static func liveStream(for settings: ListeningSettings) -> (url: URL, shift: (any LiveShifting)?)? {
		let streams = KEXPStation().streams
		guard let stream = streams.first(where: { $0.id == settings.quality.rawValue }) ?? streams.first else { return nil }
		let shift = settings.window.duration.map { LiveTimeShift(source: URLSessionByteSource(url: stream.url), window: $0) }
		return (stream.url, shift)
	}

	/// Starts the live stream over with new settings: another quality, or another rewind window.
	/// - Parameter settings: The listener's quality and rewind window.
	func apply(_ settings: ListeningSettings) async {
		guard let live = Self.liveStream(for: settings) else { return }
		await playerController.reconfigureLive(link: live.url, liveShift: live.shift)
	}

	private func refresh() async {
		do {
			let playResult = try await networkManager.getPlay(limit: Self.playsPerRefresh)
			latestPlays = playResult.plays ?? []

			let showResult = try await networkManager.getShow(limit: 1)
			show = showResult.shows?.first ?? Show.fixture(hosts: [0], programName: "Retrieving…", hostNames: ["Retrieving…"])

			// An archived show is playing: the lock screen shows it, not the live song.
			if !playerController.isPlayingArchive {
				await playerController.updateNowPlaying(KEXPMapping.nowPlaying(from: plays.first))
			}
			await widgetPublisher.update(play: latestPlays.first, show: show, isPlaying: publishedPlaying)
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
