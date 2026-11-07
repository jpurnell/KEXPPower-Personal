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
}
