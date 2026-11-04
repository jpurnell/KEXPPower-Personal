import AVFoundation
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
}
