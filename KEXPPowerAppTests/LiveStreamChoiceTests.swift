import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("Live stream for the settings")
@MainActor
struct LiveStreamChoiceTests {
    @Test("The quality picks the stream: 160 kbps or 64 kbps")
    func qualityPicksStream() {
        let standard = ResultRetriever.liveStream(for: ListeningSettings(quality: .standard, window: .off))
        let saver = ResultRetriever.liveStream(for: ListeningSettings(quality: .dataSaver, window: .off))
        #expect(standard?.url.absoluteString.contains("160") == true)
        #expect(saver?.url.absoluteString.contains("64") == true)
    }

    @Test("A window means the stream is recorded, and its length is the window's")
    func windowMeansRecording() {
        let ten = ResultRetriever.liveStream(for: ListeningSettings(quality: .standard, window: .tenMinutes))
        let five = ResultRetriever.liveStream(for: ListeningSettings(quality: .standard, window: .fiveMinutes))
        #expect(ten?.shift?.window == 600)
        #expect(five?.shift?.window == 300)
    }

    @Test("With the window off there is no recording: live plays the stream directly")
    func offMeansDirect() {
        let off = ResultRetriever.liveStream(for: ListeningSettings(quality: .standard, window: .off))
        #expect(off != nil)
        #expect(off?.shift == nil)
    }
}
