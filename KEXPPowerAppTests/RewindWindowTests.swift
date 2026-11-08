import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("RewindWindow")
struct RewindWindowTests {
    @Test("Stored values map to the matching window, and the windows are off, five minutes and ten")
    func storedValues() {
        #expect(RewindWindow.resolve(stored: "off") == .off)
        #expect(RewindWindow.resolve(stored: "5") == .fiveMinutes)
        #expect(RewindWindow.resolve(stored: "10") == .tenMinutes)
        #expect(RewindWindow.allCases.count == 3)
    }

    @Test("Nothing stored, or something unrecognised, is ten minutes: the cushion is the point of the feature")
    func fallback() {
        #expect(RewindWindow.resolve(stored: nil) == .tenMinutes)
        #expect(RewindWindow.resolve(stored: "") == .tenMinutes)
        #expect(RewindWindow.resolve(stored: "60") == .tenMinutes)
    }

    @Test("Each window says how many seconds it holds; off holds none")
    func durations() {
        #expect(RewindWindow.off.duration == nil)
        #expect(RewindWindow.fiveMinutes.duration == 300)
        #expect(RewindWindow.tenMinutes.duration == 600)
    }

    @Test("Every window has a label to show in Settings")
    func labels() {
        #expect(RewindWindow.allCases.allSatisfy { !$0.label.isEmpty })
    }
}
