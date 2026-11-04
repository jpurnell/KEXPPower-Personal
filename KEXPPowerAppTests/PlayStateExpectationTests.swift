import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("PlayStateExpectation")
struct PlayStateExpectationTests {
    private let now = Date(timeIntervalSince1970: 1_730_000_000)

    @Test("With nothing expected, the player's real state is what is published")
    func none() {
        let expectation = PlayStateExpectation()
        #expect(expectation.effective(actual: true, at: now))
        #expect(!expectation.effective(actual: false, at: now))
    }

    @Test("After asking to play, playing is published while the stream starts, and once it has")
    func expectingPlay() {
        var expectation = PlayStateExpectation()
        expectation.expect(playing: true, until: now.addingTimeInterval(6))
        #expect(expectation.effective(actual: false, at: now.addingTimeInterval(2)))
        #expect(expectation.effective(actual: true, at: now.addingTimeInterval(2)))
    }

    @Test("If the stream never starts, the real state returns once the expectation has expired")
    func expired() {
        var expectation = PlayStateExpectation()
        expectation.expect(playing: true, until: now.addingTimeInterval(6))
        #expect(!expectation.effective(actual: false, at: now.addingTimeInterval(7)))
    }

    @Test("After asking to pause, paused is published even while the player winds down")
    func expectingPause() {
        var expectation = PlayStateExpectation()
        expectation.expect(playing: false, until: now.addingTimeInterval(6))
        #expect(!expectation.effective(actual: true, at: now.addingTimeInterval(1)))
    }

    @Test("A newer expectation replaces an older one")
    func replaced() {
        var expectation = PlayStateExpectation()
        expectation.expect(playing: true, until: now.addingTimeInterval(6))
        expectation.expect(playing: false, until: now.addingTimeInterval(6))
        #expect(!expectation.effective(actual: true, at: now.addingTimeInterval(1)))
    }
}
