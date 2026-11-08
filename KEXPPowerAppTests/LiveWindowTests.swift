import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("LiveWindow")
struct LiveWindowTests {
    private func near(_ value: Double, _ expected: Double) -> Bool { abs(value - expected) < 1e-6 }

    /// Ten minutes held, 600 s to 1200 s on the player's clock, playing 100 s from the end.
    private func window(position: TimeInterval = 1_100, wallLag: TimeInterval? = nil) -> LiveWindow {
        LiveWindow(start: 600, end: 1_200, position: position, wallClockLag: wallLag)
    }

    // MARK: Position

    @Test("The window's length is what is held, and the listener's place in it runs from zero to one")
    func lengthAndFraction() {
        #expect(near(window().length, 600))
        #expect(near(window(position: 600).fraction, 0))
        #expect(near(window(position: 900).fraction, 0.5))
        #expect(near(window(position: 1_200).fraction, 1))
    }

    @Test("A position outside the window reads as its nearest edge")
    func positionClamped() {
        #expect(near(window(position: 100).fraction, 0))
        #expect(near(window(position: 5_000).fraction, 1))
    }

    @Test("How far behind live is measured to the end of the window, when there is no clock to measure by")
    func behindByWindow() {
        #expect(near(window(position: 1_100).behindLive, 100))
        #expect(near(window(position: 1_200).behindLive, 0))
    }

    @Test("Where the clock is known it is the better measure, since a gap in the stream shortens the window and not the delay")
    func behindByClock() {
        #expect(near(window(position: 1_100, wallLag: 220).behindLive, 220))
    }

    @Test("A clock reading that is not a usable number falls back to the window")
    func clockNotUsable() {
        #expect(near(window(position: 1_100, wallLag: .nan).behindLive, 100))
        #expect(near(window(position: 1_100, wallLag: -4).behindLive, 100))
    }

    @Test("A few seconds behind is live: the stream is played about three seconds late even at its newest")
    func isLive() {
        #expect(window(position: 1_197, wallLag: 3).isLive)
        #expect(window(position: 1_200).isLive)
        #expect(!window(position: 1_100).isLive)
        #expect(!window(position: 1_195, wallLag: 300).isLive)
    }

    // MARK: Moving

    @Test("Going back lands earlier in the window, and forward later")
    func skipping() {
        #expect(window().target(skipping: -15) == .within(1_085))
        #expect(window().target(skipping: 30) == .within(1_130))
    }

    @Test("Going back past the oldest audio held stops at it")
    func skipBackClamps() {
        #expect(window(position: 650).target(skipping: -300) == .within(600))
    }

    @Test("Going forward to or past the newest audio is live")
    func skipForwardIsLive() {
        #expect(window(position: 1_190).target(skipping: 30) == .live)
        #expect(window(position: 1_170).target(skipping: 30) == .live)
    }

    @Test("A skip that is not a number goes nowhere")
    func skipNotNumber() {
        #expect(window().target(skipping: .nan) == .within(1_100))
    }

    @Test("Scrubbing lands that far through what is held, and the far end is live")
    func scrubbing() {
        #expect(window().target(fraction: 0) == .within(600))
        #expect(window().target(fraction: 0.5) == .within(900))
        #expect(window().target(fraction: 1) == .live)
        #expect(window().target(fraction: 2) == .live)
        #expect(window().target(fraction: .nan) == .within(600))
    }

    @Test("A window with nothing in it, or numbers that are not finite, has nowhere to go")
    func emptyWindow() {
        let empty = LiveWindow(start: 0, end: 0, position: 0, wallClockLag: nil)
        #expect(empty.isEmpty)
        #expect(near(empty.fraction, 0))
        #expect(empty.target(skipping: -15) == .live)
        let broken = LiveWindow(start: .nan, end: 100, position: 50, wallClockLag: nil)
        #expect(broken.isEmpty)
    }

    // MARK: The rewind step

    @Test("The rewind button goes back five minutes, or the whole window if the window is shorter")
    func rewindStep() {
        #expect(near(LiveWindow.rewindStep(forWindow: 600), 300))
        #expect(near(LiveWindow.rewindStep(forWindow: 300), 300))
        #expect(near(LiveWindow.rewindStep(forWindow: 120), 120))
        #expect(near(LiveWindow.rewindStep(forWindow: .nan), 300))
        #expect(near(LiveWindow.rewindStep(forWindow: 0), 300))
    }

    // MARK: Text

    @Test("Behind live reads as a clock with a minus sign, and live as live")
    func text() {
        #expect(window(position: 900, wallLag: 272).behindText == "-4:32")
        #expect(window(position: 1_200).behindText == "Live")
    }
}
