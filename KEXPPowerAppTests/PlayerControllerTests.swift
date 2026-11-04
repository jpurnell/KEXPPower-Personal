import AVFoundation
import CoreGraphics
import Observation
import os
import Testing
@testable import KEXPPowerExampleSwiftUI

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
}
