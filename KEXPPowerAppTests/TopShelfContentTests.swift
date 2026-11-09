import Foundation
import StationKit
import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("TopShelfRow")
struct TopShelfRowTests {
    private let logo = URL(string: "https://kexp.org/logo.jpg")

    private func track(_ id: String, _ title: String, by artist: String, art: String? = nil) -> Track {
        Track(id: id, title: title, credits: [Credit(role: .performer, name: artist)],
              artworkURL: art.flatMap { URL(string: $0) })
    }

    @Test("The song on the air comes first, marked as on the air, then the recent songs")
    func order() {
        let row = TopShelfRow.make(
            nowPlaying: .track(track("3", "Star", by: "Sampa the Great")),
            recent: [track("2", "Heart Attack", by: "Bronson"), track("1", "Satellite of Love", by: "Lou Reed")],
            program: nil, fallbackArtwork: logo)
        #expect(row.tiles.map(\.id) == ["3", "2", "1"])
        #expect(row.tiles.map(\.isOnAir) == [true, false, false])
    }

    @Test("A recent list that repeats the song on the air, or itself, shows each song once")
    func noRepeats() {
        let star = track("3", "Star", by: "Sampa the Great")
        let row = TopShelfRow.make(
            nowPlaying: .track(star), recent: [star, track("2", "Heart Attack", by: "Bronson"), track("2", "Heart Attack", by: "Bronson")],
            program: nil, fallbackArtwork: logo)
        #expect(row.tiles.map(\.id) == ["3", "2"])
    }

    @Test("At most ten tiles")
    func limit() {
        let recent = (0..<30).map { track("\($0)", "Song \($0)", by: "Artist") }
        let row = TopShelfRow.make(nowPlaying: .nothing, recent: recent, program: nil, fallbackArtwork: logo)
        #expect(row.tiles.count == TopShelfRow.maximumTiles)
        #expect(TopShelfRow.maximumTiles == 10)
    }

    @Test("During an airbreak the row is the recent songs, none of them on the air")
    func airbreak() {
        let row = TopShelfRow.make(
            nowPlaying: .message("Airbreak"), recent: [track("2", "Heart Attack", by: "Bronson")],
            program: nil, fallbackArtwork: logo)
        #expect(row.tiles.map(\.id) == ["2"])
        #expect(row.tiles.allSatisfy { !$0.isOnAir })
    }

    @Test("A tile reads song · artist, and uses the station's logo when the song has no artwork")
    func tile() {
        let row = TopShelfRow.make(
            nowPlaying: .track(track("3", "Star", by: "Sampa the Great", art: "https://kexp.org/star.jpg")),
            recent: [track("2", "Heart Attack", by: "Bronson")], program: nil, fallbackArtwork: logo)
        #expect(row.tiles[0].title == "Star · Sampa the Great")
        #expect(row.tiles[0].artworkURL == URL(string: "https://kexp.org/star.jpg"))
        #expect(row.tiles[1].artworkURL == logo)
    }

    @Test("The row is titled with the show and host when they are known")
    func title() {
        func title(_ program: ProgramInfo?) -> String {
            TopShelfRow.make(nowPlaying: .nothing, recent: [], program: program, fallbackArtwork: nil).title
        }
        #expect(title(nil) == "Now on KEXP")
        #expect(title(ProgramInfo(title: "The Morning Show", host: "Lisa LeClair")) == "Now on KEXP · The Morning Show with Lisa LeClair")
        #expect(title(ProgramInfo(title: "Variety Mix", host: nil)) == "Now on KEXP · Variety Mix")
    }

    @Test("Nothing known gives an empty row, so the shelf falls back to its static image")
    func empty() {
        #expect(TopShelfRow.make(nowPlaying: .nothing, recent: [], program: nil, fallbackArtwork: logo).tiles.isEmpty)
    }
}

@Suite("SpinnerLink")
struct SpinnerLinkTests {
    @Test("Each link makes a spinner:// URL and reads back as itself")
    func roundTrip() {
        for link in [SpinnerLink.open, .playLive] {
            let url = link.url
            #expect(url?.scheme == "spinner")
            #expect(url.flatMap(SpinnerLink.init(url:)) == link)
        }
        #expect(SpinnerLink.playLive.url?.absoluteString == "spinner://live/play")
        #expect(SpinnerLink.open.url?.absoluteString == "spinner://open")
    }

    @Test("Other schemes and unknown paths are not Spinner links")
    func foreign() {
        #expect(URL(string: "https://kexp.org/live/play").flatMap(SpinnerLink.init(url:)) == nil)
        #expect(URL(string: "spinner://somewhere/else").flatMap(SpinnerLink.init(url:)) == nil)
    }
}
