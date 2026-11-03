import Testing
import AVFoundation
@testable import KEXPPowerExampleSwiftUI

@Suite("AudioSessionCoordinator decisions")
struct AudioSessionCoordinatorTests {
    @Test("An interruption that ends and says to resume resumes playback")
    func resumeAfterInterruption() {
        #expect(AudioSessionCoordinator.action(forInterruption: .ended, options: [.shouldResume]) == .resume)
    }

    @Test("An interruption that ends without the resume hint does nothing")
    func noResumeWithoutHint() {
        #expect(AudioSessionCoordinator.action(forInterruption: .ended, options: []) == .none)
    }

    @Test("The start of an interruption needs no action; the system already paused the player")
    func interruptionBegan() {
        #expect(AudioSessionCoordinator.action(forInterruption: .began, options: []) == .none)
        #expect(AudioSessionCoordinator.action(forInterruption: .began, options: [.shouldResume]) == .none)
    }

    @Test("Unplugging headphones pauses; other route changes do not")
    func routeChanges() {
        #expect(AudioSessionCoordinator.action(forRouteChange: .oldDeviceUnavailable) == .pause)
        #expect(AudioSessionCoordinator.action(forRouteChange: .newDeviceAvailable) == .none)
        #expect(AudioSessionCoordinator.action(forRouteChange: .categoryChange) == .none)
    }
}
