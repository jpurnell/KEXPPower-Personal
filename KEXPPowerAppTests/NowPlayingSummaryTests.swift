import KEXPPower
import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("NowPlayingSummary")
struct NowPlayingSummaryTests {
    @Test("A track shows its song and artist")
    func track() {
        let summary = NowPlayingSummary(.fixture())
        #expect(summary.title == "I Was Riding My Bike To Work When I Realized I Have No Job")
        #expect(summary.artist == "Teezo Touchdown")
    }

    @Test("An airbreak shows Airbreak and the station")
    func airbreak() {
        let summary = NowPlayingSummary(Play(playType: .airbreak))
        #expect(summary.title == "Airbreak")
        #expect(summary.artist == "KEXP")
    }

    @Test("Nothing playing shows the same as an airbreak")
    func nothing() {
        let summary = NowPlayingSummary(nil)
        #expect(summary.title == "Airbreak")
        #expect(summary.artist == "KEXP")
    }

    @Test("A blank song or artist counts as missing")
    func blanks() {
        let summary = NowPlayingSummary(Play(song: "  ", artist: ""))
        #expect(summary.title == "Airbreak")
        #expect(summary.artist == "KEXP")
    }

    @Test("A song with no artist keeps its title and shows the station")
    func songWithoutArtist() {
        let summary = NowPlayingSummary(Play(song: "Karma Police", playType: .trackplay))
        #expect(summary.title == "Karma Police")
        #expect(summary.artist == "KEXP")
    }
}
