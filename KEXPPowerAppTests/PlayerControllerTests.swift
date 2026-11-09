import AVFoundation
import CoreGraphics
import Observation
import os
import StationKit
import Testing
@testable import KEXPPowerExampleSwiftUI

/// Stands in for the system: records what the controller publishes and which transport commands it asks for.
@MainActor
private final class FakePublisher: NowPlayingPublishing {
    private(set) var published: [NowPlayingSnapshot] = []
    private(set) var installed: (skipBack: TimeInterval, skipForward: TimeInterval)?
    private(set) var removals = 0
    private(set) var skip: (@MainActor @Sendable (TimeInterval) -> Void)?
    private(set) var seek: (@MainActor @Sendable (TimeInterval) -> Void)?

    func publish(_ snapshot: NowPlayingSnapshot, artwork: CGImage?) { published.append(snapshot) }

    func installCommands(
        play: @escaping @MainActor @Sendable () -> Void, pause: @escaping @MainActor @Sendable () -> Void,
        toggle: @escaping @MainActor @Sendable () -> Void
    ) {}

    func installTransportCommands(
        skipBack: TimeInterval, skipForward: TimeInterval,
        skip: @escaping @MainActor @Sendable (TimeInterval) -> Void,
        seek: @escaping @MainActor @Sendable (TimeInterval) -> Void
    ) {
        installed = (skipBack, skipForward)
        self.skip = skip
        self.seek = seek
    }

    func removeTransportCommands() {
        removals += 1
        installed = nil
        skip = nil
        seek = nil
    }
}

/// Stands in for the time-shift: hands out a fixed address, or none, and counts its calls.
@MainActor
private final class FakeShift: LiveShifting {
    private(set) var starts = 0
    private(set) var stops = 0
    let address: URL?
    let window: TimeInterval
    let delay: Duration
    init(address: URL?, window: TimeInterval = 600, delay: Duration = .zero) {
        self.address = address
        self.window = window
        self.delay = delay
    }
    func start() async -> URL? {
        starts += 1
        try? await Task.sleep(for: delay)
        return Task.isCancelled ? nil : address
    }
    func stop() async { stops += 1 }
}

@MainActor
@Suite("PlayerController")
struct PlayerControllerTests {
    /// Records whether an observation fired, so a test can read it after the change.
    private final class Flag: Sendable {
        private let state = OSAllocatedUnfairLock(initialState: false)
        var fired: Bool { state.withLock { $0 } }
        func fire() { state.withLock { $0 = true } }
    }

    @Test("A SwiftUI view reading isPlaying is told when playback starts")
    func isPlayingIsObservable() {
        let controller = PlayerController()
        let changed = Flag()
        withObservationTracking {
            _ = controller.isPlaying
        } onChange: {
            changed.fire()
        }

        controller.timeControlStatusChanged(.playing)

        #expect(controller.isPlaying)
        #expect(changed.fired)
    }

    @Test("Playback stopping is reported back as not playing")
    func pausedClearsIsPlaying() {
        let controller = PlayerController()
        controller.timeControlStatusChanged(.playing)
        controller.timeControlStatusChanged(.paused)
        #expect(!controller.isPlaying)
    }

    @Test("A change in whether it is playing is announced once, with the new value")
    func announcesPlayingChanges() {
        let controller = PlayerController()
        var announced: [Bool] = []
        controller.onPlayingChange = { announced.append($0) }

        controller.timeControlStatusChanged(.playing)
        controller.timeControlStatusChanged(.playing)
        controller.timeControlStatusChanged(.paused)
        controller.timeControlStatusChanged(.waitingToPlayAtSpecifiedRate)
        #expect(announced == [true, false])
    }

    @Test("Artwork is encoded as JPEG without UIKit or AppKit")
    func artworkEncodesAsJPEG() throws {
        let context = try #require(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(red: 0.96, green: 0.7, blue: 0.13, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try #require(context.makeImage())

        let data = try #require(PlayerController.jpegData(from: image))
        #expect(Array(data.prefix(3)) == [0xFF, 0xD8, 0xFF])
    }

    // MARK: Transport commands and the timeline

    private func controls(
        timeline: PlaybackTimeline? = PlaybackTimeline(elapsed: 125, duration: 7_200),
        skip: @escaping @MainActor (TimeInterval) async -> Void = { _ in },
        seek: @escaping @MainActor (TimeInterval) async -> Void = { _ in }
    ) -> ArchiveTransportControls {
        ArchiveTransportControls(skip: skip, seek: seek, timeline: { timeline })
    }

    @Test("Giving the player transport controls asks the system for skip back 15, skip forward 30 and scrub")
    func installsTransportCommands() {
        let publisher = FakePublisher()
        let controller = PlayerController(fallbackArtworkURL: nil, publisher: publisher)
        controller.setTransportControls(controls())
        #expect(publisher.installed?.skipBack == 15)
        #expect(publisher.installed?.skipForward == 30)
    }

    @Test("Taking the transport controls away removes the system's skip and scrub commands")
    func removesTransportCommands() {
        let publisher = FakePublisher()
        let controller = PlayerController(fallbackArtworkURL: nil, publisher: publisher)
        controller.setTransportControls(controls())
        controller.setTransportControls(nil)
        #expect(publisher.installed == nil)
        #expect(publisher.removals == 1)
    }

    @Test("A skip command from the system reaches the controls with how far to move")
    func skipCommand() async {
        let publisher = FakePublisher()
        let controller = PlayerController(fallbackArtworkURL: nil, publisher: publisher)
        let moved: TimeInterval = await withCheckedContinuation { continuation in
            controller.setTransportControls(controls(skip: { continuation.resume(returning: $0) }))
            publisher.skip?(-15)
        }
        #expect(moved == -15)
    }

    @Test("A scrub command from the system reaches the controls with the position in the show")
    func seekCommand() async {
        let publisher = FakePublisher()
        let controller = PlayerController(fallbackArtworkURL: nil, publisher: publisher)
        let position: TimeInterval = await withCheckedContinuation { continuation in
            controller.setTransportControls(controls(seek: { continuation.resume(returning: $0) }))
            publisher.seek?(3_600)
        }
        #expect(position == 3_600)
    }

    @Test("What the system is told while an archived show plays carries its timeline and is not a live stream")
    func publishesTimeline() async throws {
        let publisher = FakePublisher()
        let controller = PlayerController(fallbackArtworkURL: nil, publisher: publisher)
        controller.setTransportControls(controls())
        await controller.updateNowPlaying(.program(ProgramInfo(title: "The Morning Show", host: nil, artworkURL: nil)))
        let snapshot = try #require(publisher.published.last)
        #expect(snapshot.timeline == PlaybackTimeline(elapsed: 125, duration: 7_200))
        #expect(!snapshot.isLive)
    }

    @Test("Pausing or resuming republishes the timeline, so the lock screen's clock stops and starts where it should")
    func republishesOnPlayStateChange() throws {
        let publisher = FakePublisher()
        let controller = PlayerController(fallbackArtworkURL: nil, publisher: publisher)
        controller.setTransportControls(controls())
        controller.timeControlStatusChanged(.paused)
        let snapshot = try #require(publisher.published.last)
        #expect(snapshot.timeline == PlaybackTimeline(elapsed: 125, duration: 7_200))
        #expect(snapshot.state == .paused)
    }

    @Test("Back on the live stream the system is told there is no timeline, and that it is live")
    func liveHasNoTimeline() async throws {
        let publisher = FakePublisher()
        let controller = PlayerController(fallbackArtworkURL: nil, publisher: publisher)
        controller.setTransportControls(controls())
        controller.setTransportControls(nil)
        await controller.updateNowPlaying(.program(ProgramInfo(title: "Live", host: nil, artworkURL: nil)))
        let snapshot = try #require(publisher.published.last)
        #expect(snapshot.timeline == nil)
        #expect(snapshot.isLive)
    }

    @Test("After a seek the new place is published, because the lock screen's clock runs on from the last time it was told")
    func refreshesTimeline() throws {
        let place = OSAllocatedUnfairLock(initialState: TimeInterval(125))
        let publisher = FakePublisher()
        let controller = PlayerController(fallbackArtworkURL: nil, publisher: publisher)
        controller.setTransportControls(ArchiveTransportControls(
            skip: { _ in }, seek: { _ in }, timeline: { PlaybackTimeline(elapsed: place.withLock { $0 }, duration: 7_200) }))
        place.withLock { $0 = 3_600 }
        controller.refreshTimeline()
        let snapshot = try #require(publisher.published.last)
        #expect(snapshot.timeline == PlaybackTimeline(elapsed: 3_600, duration: 7_200))
    }

    @Test("With no controls there is nothing to refresh, so nothing is published")
    func refreshWithoutControls() {
        let publisher = FakePublisher()
        let controller = PlayerController(fallbackArtworkURL: nil, publisher: publisher)
        controller.refreshTimeline()
        #expect(publisher.published.isEmpty)
    }

    // MARK: Live through the time-shift

    private func itemURL(_ controller: PlayerController) -> URL? {
        (controller.player?.currentItem?.asset as? AVURLAsset)?.url
    }

    private let direct = URL(string: "https://example.com/direct.aac") ?? .temporaryDirectory
    private let local = URL(string: "http://127.0.0.1:50000/live.m3u8") ?? .temporaryDirectory

    @Test("Playing live through the time-shift plays its local address in place of the direct stream")
    func playsLocalAddress() async {
        let controller = PlayerController(publisher: FakePublisher())
        controller.initPlayer(link: direct)
        let shift = FakeShift(address: local)
        controller.liveShift = shift
        await controller.playLive()
        #expect(itemURL(controller) == local)
        #expect(shift.starts == 1)
    }

    @Test("If the time-shift cannot start, the direct stream plays as it always has")
    func fallsBackToDirect() async {
        let controller = PlayerController(publisher: FakePublisher())
        controller.initPlayer(link: direct)
        controller.liveShift = FakeShift(address: nil)
        await controller.playLive()
        #expect(itemURL(controller) == direct)
    }

    @Test("With no time-shift (the setting is off) nothing changes: the direct stream plays")
    func offPlaysDirect() async {
        let controller = PlayerController(publisher: FakePublisher())
        controller.initPlayer(link: direct)
        await controller.playLive()
        #expect(itemURL(controller) == direct)
    }

    @Test("Pausing while the recording is still starting stops playback from beginning")
    func pauseDuringStart() async {
        let controller = PlayerController(publisher: FakePublisher())
        controller.initPlayer(link: direct)
        controller.liveShift = FakeShift(address: local, delay: .milliseconds(200))
        controller.playPlayer()
        try? await Task.sleep(for: .milliseconds(50))
        controller.pausePlayer()
        try? await Task.sleep(for: .milliseconds(400))
        #expect(!controller.isPlaying)
        #expect(itemURL(controller) != local)
    }

    @Test("Playing again does not start the time-shift again")
    func startsOnce() async {
        let controller = PlayerController(publisher: FakePublisher())
        controller.initPlayer(link: direct)
        let shift = FakeShift(address: local)
        controller.liveShift = shift
        await controller.playLive()
        await controller.playLive()
        #expect(shift.starts == 1)
    }

    @Test("Playing an archived show stops the recording, and going back to live starts it again")
    func archiveStopsRecording() async {
        let controller = PlayerController(publisher: FakePublisher())
        controller.initPlayer(link: direct)
        let shift = FakeShift(address: local)
        controller.liveShift = shift
        await controller.playLive()
        await controller.playArchive(url: URL(string: "https://example.com/show.aac") ?? .temporaryDirectory, at: 0)
        #expect(shift.stops == 1)
        controller.returnToLive()
        // Going back to live starts on its own task; wait for it to land.
        for _ in 0..<300 where shift.starts < 2 || itemURL(controller) != local {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(shift.starts == 2)
        #expect(itemURL(controller) == local)
    }

    @Test("Until live is playing through the time-shift there is no live window, and the controls stay away")
    func noWindowBeforeShift() async {
        let controller = PlayerController(publisher: FakePublisher())
        controller.initPlayer(link: direct)
        #expect(!controller.isTimeShifted)
        #expect(controller.liveWindow == nil)
        controller.liveShift = FakeShift(address: nil)
        await controller.playLive()
        #expect(!controller.isTimeShifted)
    }

    @Test("Once live plays through the time-shift, the player says so, and that is observable")
    func shiftedIsObservable() async {
        let controller = PlayerController(publisher: FakePublisher())
        controller.initPlayer(link: direct)
        controller.liveShift = FakeShift(address: local)
        let changed = Flag()
        withObservationTracking { _ = controller.isTimeShifted } onChange: { changed.fire() }
        await controller.playLive()
        #expect(controller.isTimeShifted)
        #expect(changed.fired)
    }

    @Test("The rewind step is five minutes, or the whole window when that is shorter")
    func rewindStep() async {
        let controller = PlayerController(publisher: FakePublisher())
        controller.initPlayer(link: direct)
        controller.liveShift = FakeShift(address: local, window: 600)
        #expect(abs(controller.rewindStep - 300) < 1e-9)
        controller.liveShift = FakeShift(address: local, window: 120)
        #expect(abs(controller.rewindStep - 120) < 1e-9)
    }

    @Test("The cushion in force is the setting held to half the window, and none when it is Off or there is no recording")
    func cushionInForce() async throws {
        let store = try #require(UserDefaults(suiteName: "cushionInForce-\(UUID().uuidString)"))
        let controller = PlayerController(publisher: FakePublisher())
        controller.initPlayer(link: direct)
        controller.defaults = store
        controller.liveShift = FakeShift(address: local, window: 600)
        #expect(controller.cushion == nil)
        store.set(Cushion.fiveMinutes.rawValue, forKey: Cushion.storageKey)
        #expect(controller.cushion == 300)
        controller.liveShift = FakeShift(address: local, window: 300)
        #expect(controller.cushion == 150)
        controller.liveShift = nil
        #expect(controller.cushion == nil)
    }

    @Test("The cushion moves do nothing until live plays through the recording")
    func cushionMovesNeedAWindow() async {
        let controller = PlayerController(publisher: FakePublisher())
        controller.initPlayer(link: direct)
        await controller.catchUpToCushion()
        await controller.cushionNow()
        await controller.goFullyLive()
        #expect(controller.liveWindow == nil)
    }

    @Test("Once live plays through the time-shift, the lock screen is offered skip back 15, skip forward 30 and scrub")
    func liveOffersTransport() async {
        let publisher = FakePublisher()
        let controller = PlayerController(publisher: publisher)
        controller.initPlayer(link: direct)
        controller.liveShift = FakeShift(address: local)
        await controller.playLive()
        #expect(publisher.installed?.skipBack == 15)
        #expect(publisher.installed?.skipForward == 30)
    }

    @Test("Without the time-shift live offers no skip or scrub, as before")
    func directOffersNone() async {
        let publisher = FakePublisher()
        let controller = PlayerController(publisher: publisher)
        controller.initPlayer(link: direct)
        await controller.playLive()
        #expect(publisher.installed == nil)
    }

    @Test("Playing an archived show takes the live transport away; the archive's own is installed after")
    func archiveReplacesLiveTransport() async {
        let publisher = FakePublisher()
        let controller = PlayerController(publisher: publisher)
        controller.initPlayer(link: direct)
        controller.liveShift = FakeShift(address: local)
        await controller.playLive()
        await controller.playArchive(url: URL(string: "https://example.com/show.aac") ?? .temporaryDirectory, at: 0)
        #expect(publisher.installed == nil)
    }

    @Test("Not behind live, the heard lag is zero")
    func lagZeroWhenDirect() {
        let controller = PlayerController(publisher: FakePublisher())
        #expect(controller.heardLag < 0.001)
    }

    // MARK: Changing the live stream's settings

    private var lowQuality: URL { URL(string: "https://example.com/low.aac") ?? .temporaryDirectory }
    private var otherLocal: URL { URL(string: "http://127.0.0.1:9/other.m3u8") ?? .temporaryDirectory }

    @Test("Before anything has played, a new address replaces the old one")
    func reconfigureBeforePlay() async {
        let controller = PlayerController(publisher: FakePublisher())
        controller.initPlayer(link: direct)
        await controller.reconfigureLive(link: lowQuality, liveShift: nil)
        #expect(itemURL(controller) == lowQuality)
    }

    @Test("Live is rebuilt: the old recording stops, and the new one starts when live plays")
    func reconfigureReplacesShift() async {
        let controller = PlayerController(publisher: FakePublisher())
        controller.initPlayer(link: direct)
        let old = FakeShift(address: local)
        controller.liveShift = old
        await controller.playLive()
        #expect(controller.isTimeShifted)
        let new = FakeShift(address: otherLocal)
        await controller.reconfigureLive(link: lowQuality, liveShift: new)
        #expect(old.stops == 1)
        #expect(new.starts == 1)
        #expect(itemURL(controller) == otherLocal)
        #expect(controller.isTimeShifted)
    }

    @Test("Turning the window off leaves live playing the direct stream, at the new address")
    func reconfigureToOff() async {
        let controller = PlayerController(publisher: FakePublisher())
        controller.initPlayer(link: direct)
        let old = FakeShift(address: local)
        controller.liveShift = old
        await controller.playLive()
        await controller.reconfigureLive(link: lowQuality, liveShift: nil)
        #expect(old.stops == 1)
        #expect(!controller.isTimeShifted)
        #expect(itemURL(controller) == lowQuality)
    }

    @Test("A paused player stays paused, and the new recording is not started until it plays")
    func reconfigureKeepsPause() async {
        let controller = PlayerController(publisher: FakePublisher())
        controller.initPlayer(link: direct)
        controller.liveShift = FakeShift(address: local)
        await controller.playLive()
        controller.pausePlayer()
        let new = FakeShift(address: otherLocal)
        await controller.reconfigureLive(link: lowQuality, liveShift: new)
        #expect(!controller.isPlaying)
        #expect(new.starts == 0)
        await controller.playLive()
        #expect(new.starts == 1)
    }

    @Test("An archived show is not interrupted; the new settings are used when live comes back")
    func reconfigureDuringArchive() async {
        let controller = PlayerController(publisher: FakePublisher())
        controller.initPlayer(link: direct)
        controller.liveShift = FakeShift(address: local)
        await controller.playLive()
        let show = URL(string: "https://example.com/show.aac") ?? .temporaryDirectory
        await controller.playArchive(url: show, at: 0)
        let new = FakeShift(address: otherLocal)
        await controller.reconfigureLive(link: lowQuality, liveShift: new)
        #expect(itemURL(controller) == show)
        #expect(controller.isPlayingArchive)
        #expect(new.starts == 0)
        controller.returnToLive()
        for _ in 0..<300 where new.starts < 1 || itemURL(controller) != otherLocal {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(new.starts == 1)
        #expect(itemURL(controller) == otherLocal)
    }
}
