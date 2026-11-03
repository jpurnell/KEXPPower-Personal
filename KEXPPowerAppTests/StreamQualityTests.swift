import Testing
import KEXPPower
@testable import KEXPPowerExampleSwiftUI

@Suite("StreamQuality")
struct StreamQualityTests {
    @Test("Stored values map to the matching bitrate")
    func storedValues() {
        #expect(StreamQuality.resolve(stored: "160") == .standard)
        #expect(StreamQuality.resolve(stored: "64") == .dataSaver)
        #expect(StreamQuality.standard.bitrate == .oneSixty)
        #expect(StreamQuality.dataSaver.bitrate == .sixtyFour)
    }

    @Test("A missing or unrecognised stored value falls back to standard quality")
    func fallback() {
        #expect(StreamQuality.resolve(stored: nil) == .standard)
        #expect(StreamQuality.resolve(stored: "") == .standard)
        #expect(StreamQuality.resolve(stored: "320") == .standard)
    }

    @Test("Every quality has a label to show in Settings")
    func labels() {
        #expect(StreamQuality.allCases.allSatisfy { !$0.label.isEmpty })
        #expect(StreamQuality.allCases.count == 2)
    }
}
