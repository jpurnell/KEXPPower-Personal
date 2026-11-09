import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("Cushion")
struct CushionTests {
    private func near(_ value: Double?, _ expected: Double) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 1e-6
    }

    @Test("A stored value resolves to its choice, and nothing valid resolves to Off")
    func resolve() {
        #expect(Cushion.resolve(stored: "2") == .twoMinutes)
        #expect(Cushion.resolve(stored: "5") == .fiveMinutes)
        #expect(Cushion.resolve(stored: "off") == .off)
        #expect(Cushion.resolve(stored: "7") == .off)
        #expect(Cushion.resolve(stored: nil) == .off)
    }

    @Test("Each choice has a label, and Off has no duration")
    func labelsAndDurations() {
        #expect(Cushion.off.duration == nil)
        #expect(near(Cushion.twoMinutes.duration, 120))
        #expect(near(Cushion.fiveMinutes.duration, 300))
        #expect(Cushion.allCases.allSatisfy { !$0.label.isEmpty })
    }

    @Test("The cushion in force is the choice, held to half the window so there is always room to rewind further")
    func effective() {
        #expect(near(Cushion.fiveMinutes.effective(forWindow: 600), 300))
        #expect(near(Cushion.twoMinutes.effective(forWindow: 600), 120))
        #expect(near(Cushion.fiveMinutes.effective(forWindow: 300), 150))
        #expect(near(Cushion.twoMinutes.effective(forWindow: 300), 120))
    }

    @Test("No cushion when it is Off, or when there is no window or the window is not a usable number")
    func effectiveNone() {
        #expect(Cushion.off.effective(forWindow: 600) == nil)
        #expect(Cushion.fiveMinutes.effective(forWindow: nil) == nil)
        #expect(Cushion.fiveMinutes.effective(forWindow: 0) == nil)
        #expect(Cushion.fiveMinutes.effective(forWindow: -60) == nil)
        #expect(Cushion.fiveMinutes.effective(forWindow: .nan) == nil)
        #expect(Cushion.fiveMinutes.effective(forWindow: .infinity) == nil)
    }
}

@Suite("LiveWindow cushion")
struct LiveWindowCushionTests {
    /// Ten minutes held, 600 s to 1200 s on the player's clock.
    private func window(position: TimeInterval) -> LiveWindow {
        LiveWindow(start: 600, end: 1_200, position: position, wallClockLag: nil)
    }

    @Test("Catching up from far behind lands at the cushion, not at the newest audio")
    func catchUpLandsAtCushion() {
        // A five-minute cushion is 900 s on this clock; the listener is at 650 s, nine minutes behind.
        #expect(window(position: 650).target(catchingUpWithCushion: 300) == .within(900))
    }

    @Test("With no cushion, catching up is live, as before")
    func catchUpWithoutCushion() {
        #expect(window(position: 650).target(catchingUpWithCushion: nil) == .live)
    }

    @Test("A listener already nearer than the cushion stays where they are")
    func catchUpNearerThanCushion() {
        #expect(window(position: 1_100).target(catchingUpWithCushion: 300) == .within(1_100))
        #expect(window(position: 1_200).target(catchingUpWithCushion: 300) == .within(1_200))
    }

    @Test("A cushion longer than what is held lands at the oldest audio")
    func cushionLongerThanWindow() {
        let short = LiveWindow(start: 1_100, end: 1_200, position: 1_100, wallClockLag: nil)
        #expect(short.target(catchingUpWithCushion: 300) == .within(1_100))
    }

    @Test("An empty window has nothing to hold a cushion in: live")
    func emptyWindow() {
        let empty = LiveWindow(start: 0, end: 0, position: 0, wallClockLag: nil)
        #expect(empty.target(catchingUpWithCushion: 300) == .live)
    }

    @Test("Skipping forward from behind the cushion stops at the cushion")
    func skipForwardStopsAtCushion() {
        #expect(window(position: 850).target(skipping: 120, cushion: 300) == .within(900))
        #expect(window(position: 650).target(skipping: 30, cushion: 300) == .within(680))
    }

    @Test("Skipping forward from the cushion, or nearer, goes on as it always did")
    func skipForwardPastCushion() {
        #expect(window(position: 900).target(skipping: 30, cushion: 300) == .within(930))
        #expect(window(position: 1_150).target(skipping: 120, cushion: 300) == .live)
    }

    @Test("Skipping back, and skipping with no cushion, are unchanged")
    func skipUnchanged() {
        #expect(window(position: 900).target(skipping: -300, cushion: 300) == .within(600))
        #expect(window(position: 850).target(skipping: 120, cushion: nil) == window(position: 850).target(skipping: 120))
    }

    @Test("A listener is at their cushion when they are within the slack of it")
    func isAtCushion() {
        #expect(window(position: 900).isAtCushion(300))
        #expect(window(position: 895).isAtCushion(300))
        #expect(!window(position: 650).isAtCushion(300))
        #expect(!window(position: 1_150).isAtCushion(300))
        #expect(!window(position: 900).isAtCushion(nil))
    }

    @Test("Cushion now lands at the cushion from anywhere, even from live")
    func cushionNow() {
        #expect(window(position: 1_200).target(atCushion: 300) == .within(900))
        #expect(window(position: 650).target(atCushion: 300) == .within(900))
        #expect(window(position: 1_200).target(atCushion: nil) == .live)
    }
}

@Suite("LiveBolt")
struct LiveBoltTests {
    private func window(position: TimeInterval) -> LiveWindow {
        LiveWindow(start: 600, end: 1_200, position: position, wallClockLag: nil)
    }

    @Test("With no cushion the bolt is what it always was: hidden at live, catch up when behind")
    func noCushion() {
        #expect(LiveBolt.choose(window: window(position: 1_195), cushion: nil) == .hidden)
        #expect(LiveBolt.choose(window: window(position: 700), cushion: nil) == .catchUpToLive)
    }

    @Test("Further behind than the cushion, the bolt goes back to the cushion")
    func behindTheCushion() {
        #expect(LiveBolt.choose(window: window(position: 650), cushion: 300) == .backToCushion)
    }

    @Test("At the cushion, the bolt gives it up and goes fully live")
    func atTheCushion() {
        #expect(LiveBolt.choose(window: window(position: 900), cushion: 300) == .goFullyLive)
    }

    @Test("Nearer than the cushion but not live, the bolt goes fully live")
    func nearerThanTheCushion() {
        #expect(LiveBolt.choose(window: window(position: 1_100), cushion: 300) == .goFullyLive)
    }

    @Test("Live, with a cushion set, offers to make the cushion now")
    func liveWithCushion() {
        #expect(LiveBolt.choose(window: window(position: 1_195), cushion: 300) == .cushionNow)
    }
}
