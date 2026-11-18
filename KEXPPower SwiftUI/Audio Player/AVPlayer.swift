//
//  AVPlayer.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 5/8/24.
//  Copyright © 2024 KEXP. All rights reserved.
//


import AVFoundation
import AVKit
import Combine
import Foundation
import ImageIO
import Observation
import OSLog
import StationKit
import UniformTypeIdentifiers

    /// Owns the live-stream `AVPlayer` and reports it to the system through a single publisher.
    ///
    /// `isPlaying` mirrors the player's own `timeControlStatus`; it is never toggled by hand, so a
    /// remote command, an interruption, or a route change cannot leave it out of step.
    @MainActor
    @Observable
    final class PlayerController: ArchivePlayer {

        // MARK: - State

        private(set) var isPlaying = false
        /// Whether audio has played this session, so a bar that controls it has something to control.
        private(set) var hasPlayed = false

        /// Called with the new value whenever the player starts or stops playing.
        @ObservationIgnored var onPlayingChange: (@MainActor (Bool) -> Void)?

        @ObservationIgnored private(set) var player: AVPlayer?
        /// The live stream's address, kept so the player can return to it after an archived show.
        @ObservationIgnored private var liveLink: URL?
        /// Whether the player holds an archived show's file instead of the live stream.
        private(set) var isPlayingArchive = false
        /// Records the live stream so it can be paused and rewound; `nil` when the rewind window is off.
        @ObservationIgnored var liveShift: (any LiveShifting)? {
            didSet { watchConnection() }
        }
        /// Where the listener's settings are read from; tests give it a store of their own.
        @ObservationIgnored var defaults: UserDefaults = .standard
        /// Whether the live stream has been resolved to the time-shift's address or to the direct stream since live
        /// last began, and whether that is under way.
        private enum LiveSource { case unresolved, resolving, shifted, direct }
        @ObservationIgnored private var liveSource = LiveSource.unresolved {
            didSet { isTimeShifted = liveSource == .shifted }
        }
        /// Whether live is playing through the recording, so it can be paused and rewound.
        private(set) var isTimeShifted = false
        /// How far behind the broadcast the audio being heard is, in seconds; zero unless live is time-shifted. The song
        /// shown follows it, so that it is the one in the listener's ears.
        private(set) var heardLag: TimeInterval = 0
        @ObservationIgnored private let lagWatch = TaskHolder()
        @ObservationIgnored private let shiftTask = TaskHolder()
        /// Watches how long going back to live takes; replaced each time, so only the latest request is measured.
        @ObservationIgnored private let liveTimer = TaskHolder()
        /// How the phone is connected and where the sound is going, asked when live is requested; tests replace them.
        @ObservationIgnored var networkKind: @Sendable () -> NetworkKind = { NetworkPathObserver.shared.kind }
        @ObservationIgnored var outputRoute: @MainActor () -> OutputRoute = { OutputRoute.current() }
        /// Whether the player has handed the item to an external destination; set when the player is made, and a seam for tests.
        @ObservationIgnored var externalPlaybackActive: @MainActor () -> Bool = { false }
        /// What the listener may do under the plan chosen for live; decided before the item is swapped, so the controls do not change mid-start.
        private(set) var capabilities = PlaybackCapabilities(canRewind: false)

        /// Where the sound is going now.
        func playbackSource() -> PlaybackSource {
            PlaybackSource(route: outputRoute(), externalPlayback: externalPlaybackActive())
        }
        /// Told how each live start ended; the app passes it on to the diagnostics hub.
        @ObservationIgnored var onLiveStart: @MainActor (LiveStart) -> Void = { FieldDiagnostics.shared.report(.liveStart($0)) }
        /// Whether a live start gave up and the listener has not paused since, so audio is still wanted when the network returns.
        @ObservationIgnored private var awaitingNetwork = false
        /// Whether the live start under way is the retry after the network came back.
        @ObservationIgnored private var startIsRecovery = false
        @ObservationIgnored private let networkTask = TaskHolder()
        /// Called with each stall that ended (playback stopped moving while the listener wanted it); the app passes it on to the diagnostics hub.
        @ObservationIgnored var onStall: @MainActor (PlaybackStall) -> Void = { FieldDiagnostics.shared.report(.playbackStall($0)) }
        @ObservationIgnored private var stallWatching = false
        @ObservationIgnored private let stallTask = TaskHolder()
        /// Whether the listener wants audio: set by play and cleared by pause, so a stall the listener ends by pausing is told from one that ends by itself.
        @ObservationIgnored private(set) var wantsPlayback = false
        /// Set while something the listener did (an archived show, a seek) makes the player wait, which is not a stall; cleared when audio moves.
        @ObservationIgnored private(set) var settling = false
        /// Set while a live start is being watched, which has its own report.
        @ObservationIgnored private var liveStartRunning = false
        @ObservationIgnored private var lastStatusLine = ""
        /// Called with each outage of the stream's connection that ended, heard or not; the app passes it on to the diagnostics hub.
        @ObservationIgnored var onStreamOutage: @MainActor (StreamOutage) -> Void = { FieldDiagnostics.shared.report(.streamOutage($0)) }
        @ObservationIgnored private var outageObserver = StreamOutageObserver()
        @ObservationIgnored private let outageTask = TaskHolder()
        @ObservationIgnored private var outageMarkerWrittenAt: TimeInterval = 0
        @ObservationIgnored private var itemRecovery = false
        /// The item the player had before the latest change, for saying what a lost one was.
        @ObservationIgnored private var lastItem: AVPlayerItem?
        /// How many times an item that went away was put back since audio last played.
        @ObservationIgnored private var unplayedRecoveries = 0
        private static let maximumUnplayedRecoveries = 3
        /// The task that puts the item back: its own, because starting live over cancels the shift task and must not cancel the task that asked for it.
        @ObservationIgnored private let itemTask = TaskHolder()
        /// How far from the end of an archived file the next item is lined up, so it is loaded before it is needed.
        static let handoffLead: TimeInterval = 30
        /// How far the system's skip buttons move: a short rewind and a longer skip forward.
        static let skipBack: TimeInterval = 15
        static let skipForward: TimeInterval = 30
        /// What the system may ask of an archived show; `nil` on the live stream.
        @ObservationIgnored private var transportControls: ArchiveTransportControls?
        @ObservationIgnored private var continuation: (@MainActor () async -> ArchiveContinuation)?
        @ObservationIgnored private var onAdvanced: (@MainActor (ArchiveContinuation) async -> Void)?
        @ObservationIgnored private var queued: (item: AVPlayerItem, plan: ArchiveContinuation)?
        @ObservationIgnored private let endWatch = TaskHolder()
        @ObservationIgnored private var itemObservation: AnyCancellable?
        // The system player view, for `VideoPlayer` on iOS and visionOS. tvOS has none: its player view always writes
        // Now Playing itself, and the publisher must be the only writer (ADR-003).
        #if os(iOS) || os(visionOS)
        let avPlayerViewController = AVPlayerViewController()
        #endif

        private let stationName: String
        private let fallbackArtworkURL: URL?
        @ObservationIgnored private var snapshot: NowPlayingSnapshot
        @ObservationIgnored private var currentArtwork: CGImage?
        @ObservationIgnored private var statusObservation: AnyCancellable?
        @ObservationIgnored private var routeObservation: AnyCancellable?

        private let artworkLoader: ArtworkLoader
        private let publisher: any NowPlayingPublishing
        private let sessionCoordinator = AudioSessionCoordinator()
        private let logger = Logger(#function)

        /// - Parameters:
        ///   - stationName: Shown as the artist when the broadcast names none.
        ///   - fallbackArtworkURL: Artwork used when a broadcast has none, usually the station's logo.
        ///   - artworkLoader: Loads artwork; its allowed domains decide where images may come from.
        ///   - publisher: The single writer of system Now Playing state.
        init(
            stationName: String = "KEXP",
            fallbackArtworkURL: URL? = URL(string: "https://kexp.org/static/assets/img/kexp_logo.jpg"),
            artworkLoader: ArtworkLoader = ArtworkLoader(allowedDomains: ["kexp.org", "archive.org"]),
            publisher: any NowPlayingPublishing = LegacyNowPlayingPublisher()
        ) {
            self.stationName = stationName
            self.fallbackArtworkURL = fallbackArtworkURL
            self.artworkLoader = artworkLoader
            self.publisher = publisher
            self.snapshot = NowPlayingSnapshot(
                .nothing, stationName: stationName, fallbackArtworkURL: fallbackArtworkURL, state: .paused)
        }

        // MARK: - Setup

        /// Creates the player for a stream and starts reporting it to the system.
        /// - Parameter link: The live-stream URL.
        func initPlayer(link: URL) {
            logger.debug("Initiating PlayerController")

            sessionCoordinator.configure()
            liveLink = link
            // A queue player, so the next item can be loaded while the current one is still playing.
            let player = AVQueuePlayer(playerItem: AVPlayerItem(url: link))
            #if !os(visionOS)
            player.allowsExternalPlayback = true
            #endif
            player.currentItem?.preferredForwardBufferDuration = 300
            self.player = player

            #if os(iOS) || os(visionOS)
            avPlayerViewController.player = player
            avPlayerViewController.showsPlaybackControls = true
            // The publisher is the only writer of Now Playing state.
            avPlayerViewController.updatesNowPlayingInfoCenter = false
            #endif

            statusObservation = player.publisher(for: \.timeControlStatus)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] status in
                    MainActor.assumeIsolated { self?.timeControlStatusChanged(status) }
                }

            itemObservation = player.publisher(for: \.currentItem)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] item in
                    MainActor.assumeIsolated { self?.currentItemChanged(item) }
                }

            #if os(iOS) || os(visionOS)
            watchRouteChanges()
            #endif
            sessionCoordinator.observe { [weak self] action in self?.handle(sessionAction: action) }

            #if !os(macOS)
            externalPlaybackActive = { [weak self] in self?.player?.isExternalPlaybackActive ?? false }
            #endif
            watchNetwork()

            publisher.installCommands(
                play: { [weak self] in self?.playPlayer() },
                pause: { [weak self] in self?.pausePlayer() },
                toggle: { [weak self] in self?.playOrPause() })
        }

        /// What the player does about what the system's audio session reports.
        ///
        /// The journal records each one, since a pause from a route change looks like the listener's own pause afterwards. Switching an AirPlay receiver
        /// to the phone's own speaker arrives as an output device removed and pauses both devices; that is the system's model (Apple News does the same),
        /// so it is accepted and only recorded.
        func handle(sessionAction action: AudioSessionCoordinator.Action) {
            DiagnosticLog.app.record("Player", "audio session asked: \(action)")
            switch action {
            case .resume: playPlayer()
            case .pause: pausePlayer()
            case .none: break
            }
        }

        func timeControlStatusChanged(_ status: AVPlayer.TimeControlStatus) {
            let waitingReason = player?.reasonForWaitingToPlay?.rawValue ?? "none"
            let message = "timeControlStatus \(status.rawValue); waiting reason \(waitingReason)"
            logger.info("\(message, privacy: .public)")
            // The same, in the app's own journal, which the system log is not: a report cannot say what the player did through a dropped connection
            // unless every change is written down. A repeat of the last line is not.
            let line = "status \(status.rawValue), waiting \(waitingReason), item \(player?.currentItem?.status.rawValue ?? -1), network \(networkKind().rawValue)"
            if line != lastStatusLine {
                lastStatusLine = line
                DiagnosticLog.app.record("Player", line)
            }
            let wasPlaying = isPlaying
            isPlaying = status == .playing
            if isPlaying {
                hasPlayed = true
                settling = false
                unplayedRecoveries = 0
            }
            if status == .waitingToPlayAtSpecifiedRate { startStallWatch() }
            if isPlaying != wasPlaying { onPlayingChange?(isPlaying) }
            snapshot.state = isPlaying ? .playing : .paused
            snapshot.timeline = transportControls?.timeline()
            publisher.publish(snapshot, artwork: currentArtwork)
        }

        /// Watches a live start with a `LiveStartRunner`: records how long it takes for the item's clock to start moving, which is when
        /// audio is heard, and helps it along when it does not. An item the local server was never asked for, or was asked for without a
        /// segment, is rebuilt at eight seconds (one being given segments is not); at eighteen the stream is played directly; at forty-five
        /// the start is given up on, and tried again when the network returns. How it ended is reported either way.
        private func measureLiveStart(of item: AVPlayerItem) {
            liveTimer.task?.cancel()
            let recovering = startIsRecovery
            startIsRecovery = false
            let runner = LiveStartRunner(
                host: makeLiveStartHost(watching: item), network: networkKind(), route: outputRoute(), recovering: recovering,
                onStarted: { [weak self] in self?.awaitingNetwork = false },
                onGaveUp: { [weak self] in
                    self?.awaitingNetwork = true
                    FieldDiagnostics.shared.report(.rewindUnavailable(.gaveUpWatching))
                },
                report: { [weak self] in self?.onLiveStart($0) })
            liveTimer.task = Task { [weak self] in await self?.runLiveStart(runner) }
        }

        private func runLiveStart(_ runner: LiveStartRunner) async {
            liveStartRunning = true
            await runner.run()
            // A watch that was cancelled was replaced (a new one set the flag) or ended by a pause (which cleared it); only one that ran out clears it.
            if !Task.isCancelled { liveStartRunning = false }
        }

        #if os(iOS) || os(visionOS)
        /// Writes each audio route change to the journal as a reason code and where the sound goes now: switching from AirPlay to the phone's speaker paused
        /// playback, and the reason the system gave is what decides whether the player should carry on.
        private func watchRouteChanges() {
            routeObservation = NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] note in
                    let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).map(String.init) ?? "none"
                    let outputs = AVAudioSession.sharedInstance().currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ",")
                    DiagnosticLog.app.record("Player", "route changed, reason \(reason), outputs \(outputs)")
                    MainActor.assumeIsolated { self?.routeDidChange() }
                }
        }
        #endif

        /// The sound's route changed: if the recording is playing and the sound has moved to something that fetches the stream itself (or that is not known),
        /// the stream takes over at the live edge, once. The other way is not followed: the system pauses a move back to the phone, and the next play plans
        /// again, so the item never flips back and forth on its own.
        func routeDidChange() {
            guard liveSource == .shifted, !isPlayingArchive, wantsPlayback else { return }
            guard case .direct(let reason) = LivePlan.choose(source: playbackSource(), recordingAvailable: true) else { return }
            capabilities = PlaybackCapabilities(plan: .direct(reason))
            DiagnosticLog.app.record("Player", "live plan: direct (\(reason.rawValue)), the route changed while the recording played")
            itemTask.task = Task { [weak self] in _ = await self?.playLiveDirectly(because: reason) }
        }

        // MARK: - What a start runs in

        /// The surroundings of a start, as fixed codes and counts for the journal: whether the app is in front, how the audio session shares its route, where
        /// the audio is going, whether the player handed playback to something external, and what the item's own HLS logs say. A start that works from the
        /// phone and stalls from a car differs in one of these.
        private func environmentSummary(for item: AVPlayerItem) -> String {
            var parts: [String] = []
            #if os(iOS) || os(visionOS)
            parts.append("app \(UIApplication.shared.applicationState.rawValue)")
            let session = AVAudioSession.sharedInstance()
            parts.append("category \(session.category.rawValue), policy \(session.routeSharingPolicy.rawValue)")
            parts.append("outputs " + session.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ","))
            #endif
            #if !os(macOS)
            if let player { parts.append("external \(player.isExternalPlaybackActive)") }
            #endif
            if let error = item.error as NSError? { parts.append("item error \(error.domain) \(error.code)") }
            let access = item.accessLog()?.events.count ?? 0
            let media = item.accessLog()?.events.last?.numberOfMediaRequests ?? 0
            parts.append("access events \(access), media requests \(media)")
            if let last = item.errorLog()?.events.last {
                parts.append("error log \(last.errorDomain) \(last.errorStatusCode)")
            }
            return parts.joined(separator: ", ")
        }

        // MARK: - The stream's connection

        /// Follows the recording's connection to the stream for as long as there is one. Replaced when the recording is.
        private func watchConnection() {
            outageTask.task?.cancel()
            outageObserver = StreamOutageObserver()
            guard let events = liveShift?.connectionEvents else { return }
            outageTask.task = Task { [weak self] in await self?.followConnection(events) }
        }

        private func followConnection(_ events: AsyncStream<RecorderEvent>) async {
            for await event in events {
                guard !Task.isCancelled else { return }
                handle(event)
            }
        }

        /// An outage of the connection is watched whether or not it is heard: the part the player's buffer covers is seen here and nowhere else.
        private func handle(_ event: RecorderEvent) {
            guard !isPlayingArchive else { return }
            let now = Date().timeIntervalSince1970
            switch event {
            case .lost:
                outageObserver.lost(at: now, aheadSeconds: aheadSeconds(), network: networkKind(), route: outputRoute())
                if let open = outageObserver.openOutage {
                    DiagnosticLog.app.record("Player", "stream outage: began, ahead \(open.ahead.rawValue), network \(open.network.rawValue)")
                    OutageMarker<OpenStreamOutage>.app.write(open)
                    outageMarkerWrittenAt = now
                }
            case .attempting:
                outageObserver.attempted()
                outageObserver.heard(at: now)
                // The marker is kept current every few seconds while the connection is down, so an outage that ends the app is counted for as long as it was seen.
                if let open = outageObserver.openOutage, now - outageMarkerWrittenAt >= StallRunner.markerEvery {
                    OutageMarker<OpenStreamOutage>.app.write(open)
                    outageMarkerWrittenAt = now
                }
            case .restored:
                connectionRestored()
                guard let outage = outageObserver.restored(at: now) else { return }
                DiagnosticLog.app.record(
                    "Player", "stream outage: ended, \(outage.outcome.rawValue) after \(outage.took.rawValue), ahead \(outage.ahead.rawValue), attempts \(outage.attempts)")
                OutageMarker<OpenStreamOutage>.app.clear()
                onStreamOutage(outage)
            }
        }

        // MARK: - Stalls

        /// Seconds of audio buffered ahead of the playhead: the recording ahead of it when live plays through the recording, else what the item has loaded.
        private func aheadSeconds() -> Double? {
            guard let player, let item = player.currentItem else { return nil }
            if liveSource == .shifted, let window = liveWindow { return window.end - window.position }
            guard let loaded = item.loadedTimeRanges.last?.timeRangeValue else { return nil }
            return loaded.end.seconds - player.currentTime().seconds
        }

        private func stallSample() -> StallSample? {
            guard let player else { return nil }
            return StallSample(
                isPlaying: player.timeControlStatus == .playing, isWaiting: player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
                itemFailed: player.currentItem?.status == .failed, listenerPaused: !wantsPlayback, startInProgress: liveStartRunning || settling,
                aheadSeconds: aheadSeconds(), network: networkKind(), route: outputRoute())
        }

        /// Starts watching a stall when the player has been playing and now waits. Observes only: nothing here changes what the player does.
        private func startStallWatch() {
            guard !stallWatching, hasPlayed else { return }
            stallWatching = true
            let runner = StallRunner(
                sample: { [weak self] in self?.stallSample() },
                sleep: { milliseconds in try? await Task.sleep(for: .milliseconds(milliseconds)) },
                now: { Date().timeIntervalSince1970 }, record: { DiagnosticLog.app.record("Player", $0) },
                report: { [weak self] in self?.onStall($0) }, marker: .app, onBegan: { [weak self] in self?.outageObserver.stallBegan() })
            stallTask.task = Task { [weak self] in await self?.runStallWatch(runner) }
        }

        private func runStallWatch(_ runner: StallRunner) async {
            await runner.run()
            stallWatching = false
        }

        /// The item a start is being watched on, and what the local server had served when that item was made.
        private final class WatchedItem {
            var item: AVPlayerItem
            var baseline: ServedCounts
            init(item: AVPlayerItem, baseline: ServedCounts) {
                self.item = item
                self.baseline = baseline
            }
        }

        private func makeLiveStartHost(watching first: AVPlayerItem) -> ClosureLiveStartHost {
            let watched = WatchedItem(item: first, baseline: liveShift?.served ?? ServedCounts(playlists: 0, segments: 0))
            return ClosureLiveStartHost(
                snapshot: { [weak self] in
                    guard let self, let player = self.player, player.currentItem === watched.item else { return nil }
                    let position = player.currentTime().seconds
                    var evidence = LiveStartEvidence(playlistFetches: nil, segmentFetches: nil, itemFailed: watched.item.status == .failed, segmentMisses: nil)
                    #if !os(macOS)
                    evidence.externalPlayback = player.isExternalPlaybackActive
                    #endif
                    // Only a recording has a local server to ask; the direct stream has none.
                    if self.liveSource == .shifted, let served = self.liveShift?.served {
                        evidence.playlistFetches = served.playlists - watched.baseline.playlists
                        evidence.segmentFetches = served.segments - watched.baseline.segments
                        evidence.segmentMisses = served.missing - watched.baseline.missing
                    }
                    return LiveStartSnapshot(
                        audioMoving: position.isFinite && position > 0.1, evidence: evidence,
                        controlStatus: player.timeControlStatus.rawValue, itemStatus: watched.item.status.rawValue,
                        waitingReason: player.reasonForWaitingToPlay?.rawValue ?? "none", environment: self.environmentSummary(for: watched.item))
                },
                rebuild: { [weak self] in
                    guard let self, let item = await self.rebuildLiveItem() else { return false }
                    watched.item = item
                    watched.baseline = self.liveShift?.served ?? ServedCounts(playlists: 0, segments: 0)
                    return true
                },
                playDirectly: { [weak self] in
                    guard let self, let item = await self.playLiveDirectly() else { return false }
                    watched.item = item
                    return true
                },
                record: { DiagnosticLog.app.record("Player", $0) })
        }

        /// Gives the player a fresh item: the local stream served again at a new address, or the direct stream if that is what is playing.
        private func rebuildLiveItem() async -> AVPlayerItem? {
            guard let player, !isPlayingArchive else { return nil }
            let address: URL? = liveSource == .shifted ? await liveShift?.reserve() : liveLink
            guard let address else { return nil }
            let item = liveItem(url: address)
            replaceItems(with: item)
            player.play()
            return item
        }

        /// Drops the recording and plays the live stream itself.
        private func playLiveDirectly(because reason: DirectReason = .evidenceFallBack) async -> AVPlayerItem? {
            guard let player, !isPlayingArchive, let liveLink else { return nil }
            capabilities = PlaybackCapabilities(plan: .direct(reason))
            shiftTask.task?.cancel()
            stopWatchingLag()
            if liveSource == .shifted { setTransportControls(nil) }
            liveSource = .direct
            await liveShift?.stop()
            let item = liveItem(url: liveLink)
            item.preferredForwardBufferDuration = 300
            replaceItems(with: item)
            player.play()
            return item
        }

        /// When the network comes back after a start gave up, and the listener still wants audio, starts live again.
        private func watchNetwork() {
            networkTask.task?.cancel()
            networkTask.task = Task { [weak self] in await self?.followNetwork() }
        }

        private func followNetwork() async {
            var recovery = NetworkRecovery()
            for await kind in NetworkPathObserver.shared.updates() {
                guard !Task.isCancelled else { return }
                if recovery.shouldRetry(network: kind, waiting: awaitingNetwork) { await recoverLive() }
            }
        }

        /// Whether live is meant to be playing and the player has no usable item: none at all, or one that failed.
        private var liveItemIsGone: Bool {
            guard let player, !isPlayingArchive, liveSource == .shifted || liveSource == .direct else { return false }
            return player.currentItem == nil || player.currentItem?.status == .failed
        }

        /// The player's item is gone while live should be playing: a stream with no recording to report its connection coming back (the display, which
        /// plays the stream itself) otherwise stays silent until someone presses play, as it did for 82 seconds on a receiver. The journal says what the
        /// lost item last was, since nothing else recorded why it went; the item is put back unless the listener paused, and no more than
        /// `maximumUnplayedRecoveries` times without audio having played in between, so a stream that is down is not retried forever.
        private func liveItemWentAway(_ previous: AVPlayerItem?) {
            // The queue reports the empty state more than once for one loss; a put-back already under way is the answer to all of them.
            guard wantsPlayback, liveItemIsGone, !itemRecovery else { return }
            let error = previous?.error as NSError?
            let cause = error.map { "\($0.domain) \($0.code)" } ?? "none"
            DiagnosticLog.app.record("Player", "the live item went away (it was status \(previous?.status.rawValue ?? -1), error \(cause))")
            guard unplayedRecoveries < Self.maximumUnplayedRecoveries else {
                DiagnosticLog.app.record("Player", "not putting it back again: \(Self.maximumUnplayedRecoveries) tries without audio")
                return
            }
            unplayedRecoveries += 1
            putTheLiveItemBack(because: "it went away")
        }

        /// Called when the stream's connection comes back: if the listener still wants audio and the player lost its item while it was down, the item
        /// is put back without anyone pressing play.
        func connectionRestored() {
            guard wantsPlayback, liveItemIsGone else { return }
            putTheLiveItemBack(because: "the connection came back")
        }

        /// Puts a fresh item in the player: the recording served again, or the stream itself if that cannot be. One attempt at a time.
        private func putTheLiveItemBack(because reason: String) {
            guard !itemRecovery else { return }
            itemRecovery = true
            DiagnosticLog.app.record("Player", "the player has no live item (\(reason)); putting it back")
            itemTask.task = Task { [weak self] in await self?.rebuildGoneItem() }
        }

        private func rebuildGoneItem() async {
            if await rebuildLiveItem() == nil { await restartLive() }
            itemRecovery = false
        }

        private func recoverLive() async {
            guard awaitingNetwork, !isPlayingArchive, player != nil else { return }
            awaitingNetwork = false
            startIsRecovery = true
            await restartLive()
        }

        /// Starts live over: the recording is stopped and made again, and the item is chosen when it is ready.
        private func restartLive() async {
            shiftTask.task?.cancel()
            stopWatchingLag()
            if liveSource == .shifted { setTransportControls(nil) }
            liveSource = .unresolved
            await liveShift?.stop()
            (player as? AVQueuePlayer)?.removeAllItems()
            await playLive()
        }

        // MARK: - Now Playing

        /// Tells the system, and the on-screen player, what is on the air.
        /// - Parameter nowPlaying: What the station is broadcasting.
        func updateNowPlaying(_ nowPlaying: NowPlaying) async {
            let next = NowPlayingSnapshot(
                nowPlaying, stationName: stationName, fallbackArtworkURL: fallbackArtworkURL,
                isLive: transportControls == nil,
                state: isPlaying ? .playing : .paused)
            snapshot = next
            snapshot.timeline = transportControls?.timeline()

            var artwork: CGImage?
            if let url = next.artworkURL { artwork = await artworkLoader.image(for: url) }
            let outcome = ArtworkOutcome(
                offered: next.artworkURL != nil, allowed: next.artworkURL.map(artworkLoader.isAllowed) ?? false,
                loaded: artwork.map { CGSize(width: $0.width, height: $0.height) })
            DiagnosticLog.app.record("Player", "artwork: \(outcome.line)")
            // A newer track arrived while the artwork was loading; leave it to publish.
            guard snapshot.artworkURL == next.artworkURL, snapshot.title == next.title else { return }

            currentArtwork = artwork
            // For the system player view, which tvOS does not use; there the property comes from AVKit, which the TV
            // app never loads, so setting it crashes ("unrecognized selector").
            #if os(iOS) || os(visionOS)
            player?.currentItem?.externalMetadata = externalMetadata(for: snapshot, artwork: artwork)
            #endif
            publisher.publish(snapshot, artwork: artwork)
        }

        /// A live item with the current track's title and artwork already on it. Metadata belongs to an item, and a receiver reads it from there: an item
        /// made after the track arrived (every live start makes one) would otherwise show nothing until the next track.
        private func liveItem(url: URL) -> AVPlayerItem {
            let item = AVPlayerItem(url: url)
            #if os(iOS) || os(visionOS)
            if !snapshot.title.isEmpty { item.externalMetadata = externalMetadata(for: snapshot, artwork: currentArtwork) }
            #endif
            return item
        }

        #if os(iOS) || os(visionOS)
        private func externalMetadata(for snapshot: NowPlayingSnapshot, artwork: CGImage?) -> [AVMetadataItem] {
            func item(_ identifier: AVMetadataIdentifier, _ value: NSCopying & NSObjectProtocol) -> AVMetadataItem {
                let item = AVMutableMetadataItem()
                item.identifier = identifier
                item.value = value
                return item
            }

            var items = [
                item(.commonIdentifierTitle, snapshot.title as NSString),
                item(.commonIdentifierAlbumName, snapshot.album as NSString),
                item(.commonIdentifierArtist, snapshot.artist as NSString),
            ]
            if let artwork, let data = Self.jpegData(from: artwork) {
                let artworkItem = AVMutableMetadataItem()
                artworkItem.identifier = .commonIdentifierArtwork
                artworkItem.value = data as NSData
                artworkItem.dataType = kCMMetadataBaseDataType_JPEG as String
                items.append(artworkItem)
            }
            return items
        }
        #endif

        /// Encodes artwork as JPEG, the form AVFoundation metadata expects, without going through UIKit or AppKit.
        /// - Returns: The JPEG bytes, or `nil` if the image cannot be encoded.
        static func jpegData(from image: CGImage, quality: Double = 0.8) -> Data? {
            ArtworkThumbnail.jpegData(from: image, quality: quality)
        }

        // MARK: - Playback Control

        func playPlayer() {
            wantsPlayback = true
            sessionCoordinator.activate()
            // A long outage can leave the queue player with no item at all (its status then reads "waiting, no item to play"). `play()` on that is
            // silence, and it was the dead end that left a listener unable to restart live: the item is put back first.
            if liveItemIsGone {
                putTheLiveItemBack(because: "play pressed")
                return
            }
            guard !isPlayingArchive, liveSource == .unresolved else {
                player?.play()
                return
            }
            shiftTask.task = Task { [weak self] in await self?.playLive() }
        }

        /// Plays the live stream, through the time-shift if there is one and it is ready, and directly if not.
        ///
        /// The first play after live begins waits a few seconds for the recording to have something to play; after that
        /// it is an ordinary play.
        func playLive() async {
            guard let player, !isPlayingArchive else { return }
            guard liveSource == .unresolved else {
                if liveSource != .resolving { player.play() }
                return
            }
            // The recording is at the phone's own loopback address, so it plays only where the phone renders the sound; a receiver fetches the item itself and
            // cannot reach it, and a route not known here might be one. The stream's public address works from anywhere. The controls are decided with the plan.
            let plan = LivePlan.choose(source: playbackSource(), recordingAvailable: liveShift != nil)
            capabilities = PlaybackCapabilities(plan: plan)
            guard case .recording = plan, let liveShift else {
                if case .direct(let reason) = plan { DiagnosticLog.app.record("Player", "live plan: direct (\(reason.rawValue))") }
                liveSource = .direct
                // A receiver reads the item's metadata as it starts the item; the item made at launch has had it edited in since, which the display did
                // not show. A fresh one is made with the track on it, as every other live start does.
                if let liveLink, !snapshot.title.isEmpty { replaceItems(with: liveItem(url: liveLink)) }
                player.play()
                if let item = player.currentItem { measureLiveStart(of: item) }
                return
            }
            liveSource = .resolving
            let address = await liveShift.start()
            guard !isPlayingArchive, !Task.isCancelled else {
                liveSource = .unresolved
                return
            }
            if let address {
                let item = liveItem(url: address)
                replaceItems(with: item)
                liveSource = .shifted
                setTransportControls(liveTransportControls())
                watchLag()
                measureLiveStart(of: item)
            } else {
                // The recording could not start: the stream the app has always played.
                if player.currentItem == nil, let liveLink { replaceItems(with: liveItem(url: liveLink)) }
                liveSource = .direct
                if let item = player.currentItem { measureLiveStart(of: item) }
            }
            player.play()
        }

        func pausePlayer() {
            // A pause while the recording is still starting means the listener does not want to hear it begin.
            if liveSource == .resolving { shiftTask.task?.cancel() }
            awaitingNetwork = false
            wantsPlayback = false
            liveStartRunning = false
            liveTimer.task?.cancel()
            player?.pause()
        }

        func playOrPause() {
            isPlaying ? pausePlayer() : playPlayer()
        }

        // MARK: - Rewinding the live stream

        /// How much of the live stream is held and where the listener is in it, or `nil` unless live plays through the
        /// recording and the player has said what it can seek to.
        var liveWindow: LiveWindow? {
            guard liveSource == .shifted, let player, let item = player.currentItem,
                let range = item.seekableTimeRanges.last?.timeRangeValue
            else { return nil }
            let lag = item.currentDate().map { Date().timeIntervalSince($0) }
            return LiveWindow(
                start: range.start.seconds, end: range.end.seconds, position: player.currentTime().seconds,
                wallClockLag: lag)
        }

        /// How far the rewind button goes back: five minutes, or the whole window if it is shorter.
        var rewindStep: TimeInterval { LiveWindow.rewindStep(forWindow: liveShift?.window ?? .nan) }

        /// How far behind live the listener asked to stay, held to what the window allows, or `nil` for none.
        var cushion: TimeInterval? {
            Cushion.resolve(stored: defaults.string(forKey: Cushion.storageKey)).effective(forWindow: liveShift?.window)
        }

        /// Moves within the live window; a skip forward from behind the cushion stops at it, and one to the newest
        /// audio is live again.
        /// - Parameter seconds: How far to move; negative to go back.
        func skipLive(by seconds: TimeInterval) async {
            guard let window = liveWindow else { return }
            await move(to: window.target(skipping: seconds, cushion: cushion), in: window)
        }

        /// Goes back by the rewind step.
        func rewindLive() async {
            await skipLive(by: -rewindStep)
        }

        /// Moves to a fraction of the live window, from the oldest audio (0) to the newest (1).
        func scrubLive(toFraction fraction: Double) async {
            guard let window = liveWindow else { return }
            await move(to: window.target(fraction: fraction), in: window)
        }

        /// Goes to the newest audio the recording holds, giving up any cushion.
        func goFullyLive() async {
            guard let window = liveWindow else { return }
            await move(to: .live, in: window)
        }

        /// Goes ahead to the cushion from further behind, or to the newest audio when none is kept.
        func catchUpToCushion() async {
            guard let window = liveWindow else { return }
            await move(to: window.target(catchingUpWithCushion: cushion), in: window)
        }

        /// Goes back to the cushion from wherever the listener is, live included. From live this replays what was just
        /// heard, which is the price of being behind at once.
        func cushionNow() async {
            guard let window = liveWindow else { return }
            await move(to: window.target(atCushion: cushion), in: window)
        }

        private func move(to target: LiveWindow.Target, in window: LiveWindow) async {
            guard let player else { return }
            let seconds: TimeInterval
            switch target {
            case .within(let time): seconds = time
            case .live: seconds = window.end
            }
            await player.seek(
                to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            if case .live = target { player.play() }
            refreshTimeline()
        }

        /// What the system's lock screen and the car may ask of live while it plays through the recording: skip back,
        /// skip forward and scrub, with the window as the timeline.
        private func liveTransportControls() -> ArchiveTransportControls {
            ArchiveTransportControls(
                skip: { [weak self] seconds in await self?.skipLive(by: seconds) },
                seek: { [weak self] position in await self?.seekLive(toWindowPosition: position) },
                timeline: { [weak self] in
                    self?.liveWindow.map { PlaybackTimeline(elapsed: $0.position - $0.start, duration: $0.length) }
                })
        }

        /// Moves to a place in the window, counted in seconds from its oldest audio, as the lock screen's scrubber does.
        private func seekLive(toWindowPosition position: TimeInterval) async {
            guard let window = liveWindow else { return }
            settling = true
            await skipLive(by: window.start + position - window.position)
        }

        /// Keeps `heardLag` up to date while live is time-shifted, but only when it has moved by a second or more, so what
        /// reads it is not redrawn for nothing.
        private func watchLag() {
            lagWatch.task?.cancel()
            lagWatch.task = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.updateLag()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }

        private func updateLag() async {
            let lag = liveWindow?.behindLive ?? 0
            if abs(lag - heardLag) >= 1 { heardLag = lag }
        }

        private func stopWatchingLag() {
            lagWatch.task?.cancel()
            heardLag = 0
        }

        // MARK: - Archive

        /// Plays an archived show's file in place of the live stream, starting at an offset into it.
        ///
        /// The live stream is replaced, not paused beside it: there is one player, as there is one Now Playing state.
        /// - Parameters:
        ///   - url: The archived audio file.
        ///   - offset: Seconds into the file at which to begin.
        func playArchive(url: URL, at offset: TimeInterval) async {
            awaitingNetwork = false
            wantsPlayback = true
            settling = true
            guard let player else { return }
            sessionCoordinator.activate()
            shiftTask.task?.cancel()
            let item = AVPlayerItem(url: url)
            replaceItems(with: item)
            isPlayingArchive = true
            // The recording is not needed while an archived show plays, and costs data.
            if liveSource != .unresolved {
                // The live transport gives way to the archive's own, installed once the show is set up.
                if liveSource == .shifted { setTransportControls(nil) }
                stopWatchingLag()
                liveSource = .unresolved
                await liveShift?.stop()
            }
            await seekArchive(to: offset)
            player.play()
            armEndWatch(for: item)
        }

        /// Seconds into the archived file being played, or zero when there is none.
        var archiveFileTime: TimeInterval {
            guard isPlayingArchive, let seconds = player?.currentTime().seconds, seconds.isFinite else { return 0 }
            return seconds
        }

        /// The length of the archived file being played so far, or zero when it is not yet known.
        var archiveFileDuration: TimeInterval {
            guard isPlayingArchive, let seconds = player?.currentItem?.duration.seconds, seconds.isFinite else { return 0 }
            return seconds
        }

        /// Gives the player what the system may ask of an archived show, or with `nil` takes it away.
        ///
        /// While there are controls, the system is offered skip back, skip forward and a scrubber, and is told the
        /// show's timeline and that it is not a live stream.
        /// - Parameter controls: Skip, scrub and the timeline, or `nil` for the live stream.
        func setTransportControls(_ controls: ArchiveTransportControls?) {
            transportControls = controls
            guard let controls else {
                publisher.removeTransportCommands()
                return
            }
            publisher.installTransportCommands(
                skipBack: Self.skipBack, skipForward: Self.skipForward,
                skip: { seconds in Task { await controls.skip(seconds) } },
                seek: { position in Task { await controls.seek(position) } })
        }

        /// Tells the system where the player is in the show now. The system runs its clock on from the last time it was
        /// told, so this follows anything that moves the player.
        func refreshTimeline() {
            guard let transportControls else { return }
            snapshot.timeline = transportControls.timeline()
            publisher.publish(snapshot, artwork: currentArtwork)
        }

        /// Moves within the archived file being played.
        /// - Parameter seconds: Seconds from the start of the file.
        func seekArchive(to seconds: TimeInterval) async {
            guard let player, isPlayingArchive else { return }
            settling = true
            let target = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
            await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            refreshTimeline()
        }

        /// Puts the live stream back and plays it.
        func returnToLive() {
            guard player != nil, let liveLink else { return }
            // Going back to live empties the player for a moment, which is a start and not a stall.
            settling = true
            endWatch.task?.cancel()
            continuation = nil
            onAdvanced = nil
            isPlayingArchive = false
            stopWatchingLag()
            liveSource = .unresolved
            guard liveShift == nil else {
                // Through the time-shift: the item is chosen once the recording is ready.
                (player as? AVQueuePlayer)?.removeAllItems()
                playPlayer()
                return
            }
            let item = liveItem(url: liveLink)
            item.preferredForwardBufferDuration = 300
            replaceItems(with: item)
            playPlayer()
            measureLiveStart(of: item)
        }

        /// Replaces the live stream's address and recording, as when the listener changes the quality or the rewind window.
        ///
        /// Live starts over: the old recording stops (and its window is emptied), and the new settings are used from the
        /// next audio. Whether the player was playing is kept. An archived show is not interrupted; the new settings are
        /// used when live comes back.
        /// - Parameters:
        ///   - link: The live stream's address, at the chosen quality.
        ///   - liveShift: The recording of it, or `nil` to play the stream directly.
        func reconfigureLive(link: URL, liveShift newShift: (any LiveShifting)?) async {
            // Waiting to play counts: the listener pressed play, and the stream may simply be slow to start.
            let wasPlaying = player.map { $0.timeControlStatus != .paused } ?? false
            let old = liveShift
            liveLink = link
            liveShift = newShift
            guard player != nil, !isPlayingArchive else { return }
            shiftTask.task?.cancel()
            stopWatchingLag()
            if liveSource == .shifted { setTransportControls(nil) }
            liveSource = .unresolved
            await old?.stop()
            if newShift == nil {
                replaceItems(with: liveItem(url: link))
            } else {
                // The item is chosen once the new recording is ready.
                (player as? AVQueuePlayer)?.removeAllItems()
            }
            if wasPlaying { await playLive() }
        }

        // MARK: - Hand-off at the end of an archived file

        /// Arms (or, with `nil`, disarms) the hand-off at the end of an archived file.
        ///
        /// About `handoffLead` seconds before the file ends, `provide` is asked what comes next and that is lined up
        /// behind the current item, so the player rolls into it without a gap. `advanced` is called once it has.
        func setContinuation(
            _ provide: (@MainActor () async -> ArchiveContinuation)?,
            advanced: (@MainActor (ArchiveContinuation) async -> Void)?
        ) {
            continuation = provide
            onAdvanced = advanced
            if provide == nil { endWatch.task?.cancel() }
        }

        /// Replaces everything the player holds with one item.
        private func replaceItems(with item: AVPlayerItem) {
            guard let queue = player as? AVQueuePlayer else { return }
            queued = nil
            queue.removeAllItems()
            queue.insert(item, after: nil)
        }

        private func armEndWatch(for item: AVPlayerItem) {
            endWatch.task?.cancel()
            endWatch.task = Task { [weak self] in await self?.watchForEnd(of: item) }
        }

        /// Checks each second whether the archived file is within `handoffLead` of its end, and lines up what is next.
        private func watchForEnd(of item: AVPlayerItem) async {
            // Bounded: six hours of one-second checks is longer than any archived file.
            for _ in 0..<21_600 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let player, player.currentItem === item, isPlayingArchive else { return }
                let duration = item.duration.seconds
                let position = player.currentTime().seconds
                guard duration.isFinite, position.isFinite, duration - position <= Self.handoffLead else { continue }
                guard continuation != nil else { continue }
                await queueHandoff(after: item, duration: duration)
                return
            }
        }

        private func queueHandoff(after item: AVPlayerItem, duration: TimeInterval) async {
            guard let queue = player as? AVQueuePlayer, let provide = continuation else { return }
            let plan = await provide()
            guard queue.currentItem === item, queued == nil else { return }
            let next: AVPlayerItem
            switch plan {
            case .show(_, let url):
                next = AVPlayerItem(url: url)
            case .live:
                guard let liveLink else { return }
                next = liveItem(url: liveLink)
                next.preferredForwardBufferDuration = 300
            }
            queued = (next, plan)
            queue.insert(next, after: item)
            guard
                case .show(_, let url) = plan,
                let previous = (item.asset as? AVURLAsset)?.url,
                let join = ArchiveTiming.joinOffset(previousFile: previous, previousDuration: duration, nextFile: url)
            else {
                DiagnosticLog.app.record("Player", "hand-off: queued \(plan == .live ? "live" : "the next show") with no join offset")
                return
            }
            let sought = await next.seek(to: CMTime(seconds: join, preferredTimescale: 600))
            DiagnosticLog.app.record("Player", "hand-off: queued the next show, joining at \(Int(join)) s, seek \(sought)")
        }

        /// The player moved to its next item: if that is the one lined up, the show has rolled over.
        private func currentItemChanged(_ item: AVPlayerItem?) {
            let previous = lastItem
            lastItem = item
            if item == nil { liveItemWentAway(previous) }
            guard let item, let lined = queued, item === lined.item else { return }
            queued = nil
            switch lined.plan {
            case .show:
                isPlayingArchive = true
                armEndWatch(for: item)
            case .live:
                isPlayingArchive = false
            }
            DiagnosticLog.app.record("Player", "hand-off: rolled into \(lined.plan == .live ? "live" : "the next show")")
            Task { [weak self] in await self?.finishAdvance(lined.plan) }
        }

        private func finishAdvance(_ plan: ArchiveContinuation) async {
            await onAdvanced?(plan)
        }
    }

/// Holds a task and cancels it when its owner goes away.
private final class TaskHolder {
    var task: Task<Void, Never>?

    deinit {
        task?.cancel()
    }
}

/// What became of the artwork for a track, as a fixed phrase for the journal: the person reading a report needs to tell "none offered" from "blocked"
/// from "could not be loaded", and nothing else records it.
struct ArtworkOutcome: Equatable {
    /// Whether the track came with an artwork address.
    let offered: Bool
    /// Whether the loader allows that address's host.
    let allowed: Bool
    /// The size of the decoded image, or `nil` if there is none.
    let loaded: CGSize?

    var line: String {
        guard offered else { return "none offered" }
        guard allowed else { return "host not allowed" }
        guard let loaded else { return "not loaded (request failed or not an image)" }
        return "loaded \(Int(loaded.width))x\(Int(loaded.height))"
    }
}
