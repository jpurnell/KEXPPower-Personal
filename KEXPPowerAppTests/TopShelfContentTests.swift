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

/// The `spinner://` links a notification can carry (DeepLinks, Appendix A of
/// `Tools/SwiftPush/project/plans/upcoming/DeepLinks.md`). A link from a notification names a place and never an action,
/// so the notification path reads only the links that navigate; the Top Shelf, where the person pressed Play, reads both.
@Suite("SpinnerLink: places")
struct SpinnerLinkPlaceTests {
    private func link(_ text: String) -> URL { testURL(text) }

    @Test("Each place makes a spinner:// URL and reads back as itself")
    func roundTrip() throws {
        let day = try #require(SpinnerLink.Day(year: 2026, month: 11, day: 18))
        let links: [SpinnerLink] = [.live, .archive, .archiveDay(day), .settings]
        let expected = ["spinner://live", "spinner://archive", "spinner://archive/2026-11-18", "spinner://settings"]
        for (link, text) in zip(links, expected) {
            #expect(link.url?.absoluteString == text)
            #expect(link.url.flatMap(SpinnerLink.init(url:)) == link)
        }
    }

    @Test("A day is the station's calendar day, written year-month-day, and must exist")
    func days() throws {
        #expect(SpinnerLink(url: link("spinner://archive/2026-11-18")) == .archiveDay(try #require(SpinnerLink.Day(year: 2026, month: 11, day: 18))))
        for bad in ["2026-02-30", "2026-13-01", "2026-11-18T10:00", "20261118", "2026-1-5", "yesterday", "2026-11-18/extra"] {
            #expect(SpinnerLink(url: link("spinner://archive/\(bad)")) == nil, "\(bad)")
        }
        #expect(SpinnerLink.Day(year: 2026, month: 2, day: 29) == nil)
        #expect(SpinnerLink.Day(year: 2028, month: 2, day: 29) != nil)
    }

    @Test("Playing is an action; every place is a navigation")
    func kinds() throws {
        #expect(SpinnerLink.playLive.kind == .act)
        let day = try #require(SpinnerLink.Day(year: 2026, month: 11, day: 18))
        for place in [SpinnerLink.open, .live, .archive, .archiveDay(day), .settings] {
            #expect(place.kind == .navigate)
        }
    }

    @Test("A link from a notification is never an action: play is refused, places are read")
    func notificationPath() {
        #expect(SpinnerLink(notificationURL: link("spinner://live/play")) == nil)
        #expect(SpinnerLink(notificationURL: link("spinner://live")) == .live)
        #expect(SpinnerLink(notificationURL: link("spinner://settings")) == .settings)
        #expect(SpinnerLink(url: link("spinner://live/play")) == .playLive)
    }

    @Test("Foreign schemes, unknown places and stray paths are not links")
    func foreign() {
        for text in ["https://kexp.org/archive", "spinner://nowhere", "spinner://settings/extra", "spinner://live/rewind",
                     "spinner://open/now", "spinner:///archive", "spinner://archive/"] {
            #expect(SpinnerLink(url: link(text)) == nil, "\(text)")
        }
    }

    @Test("The debug probes are links in a debug build only, and navigate")
    func probes() {
        #if os(iOS) && DEBUG
        #expect(SpinnerLink(notificationURL: link("spinner://probe/archive")) == .probe(.archive))
        #expect(SpinnerLink(notificationURL: link("spinner://probe/live")) == .probe(.live))
        #expect(SpinnerLink.probe(.live).kind == .navigate)
        #expect(SpinnerLink.probe(.archive).url?.absoluteString == "spinner://probe/archive")
        #else
        #expect(SpinnerLink(url: link("spinner://probe/archive")) == nil)
        #expect(SpinnerLink(url: link("spinner://probe/live")) == nil)
        #endif
    }
}

/// A URL from literal test text; a malformed one is recorded as a failure and stands in as an unreadable URL.
private func testURL(_ text: String) -> URL {
    guard let url = URL(string: text) else {
        Issue.record("not a URL: \(text)")
        return URL(fileURLWithPath: "/not-a-url")
    }
    return url
}

@Suite("AppNavigation")
@MainActor
struct AppNavigationTests {
    @Test("A place sets where the app should be")
    func places() throws {
        let navigation = AppNavigation()
        navigation.go(to: .archive)
        #expect(navigation.section == .archive)
        navigation.go(to: .live)
        #expect(navigation.section == .live)
        #expect(navigation.archiveDay == nil)
        navigation.go(to: .settings)
        #expect(navigation.showingSettings)
    }

    @Test("A day opens the archive and asks for that day: the start of it in the station's time zone")
    func day() throws {
        let navigation = AppNavigation()
        navigation.go(to: .archiveDay(try #require(SpinnerLink.Day(year: 2026, month: 11, day: 18))))
        #expect(navigation.section == .archive)
        // Midnight on 2026-11-18 in Los Angeles (PST, UTC-8) is 08:00 UTC, which is written out here and not computed.
        #expect(navigation.archiveDay == ISO8601DateFormatter().date(from: "2026-11-18T08:00:00Z"))
        // Across the autumn change back (PDT, UTC-7, until 2026-11-01): midnight on 2026-10-31 is 07:00 UTC.
        navigation.go(to: .archiveDay(try #require(SpinnerLink.Day(year: 2026, month: 10, day: 31))))
        #expect(navigation.archiveDay == ISO8601DateFormatter().date(from: "2026-10-31T07:00:00Z"))
    }

    @Test("Playing is not navigation: asking to go to it changes nothing")
    func playIsNotNavigation() {
        let navigation = AppNavigation()
        navigation.go(to: .archive)
        navigation.go(to: .playLive)
        #expect(navigation.section == .archive)
    }

    @Test("Opening the app changes nothing")
    func open() {
        let navigation = AppNavigation()
        navigation.go(to: .archive)
        navigation.go(to: .open)
        #expect(navigation.section == .archive)
    }

    @Test("The requested day is taken once")
    func taken() throws {
        let navigation = AppNavigation()
        navigation.go(to: .archiveDay(try #require(SpinnerLink.Day(year: 2026, month: 11, day: 18))))
        #expect(navigation.takeArchiveDay() != nil)
        #expect(navigation.takeArchiveDay() == nil)
    }

    @Test("A URL that is not an acceptable notification link changes nothing")
    func handle() {
        let navigation = AppNavigation()
        navigation.go(to: .archive)
        #expect(!navigation.handle(testURL("spinner://live/play")))
        #expect(!navigation.handle(testURL("https://kexp.org")))
        #expect(navigation.section == .archive)
        #expect(navigation.handle(testURL("spinner://live")))
        #expect(navigation.section == .live)
    }
}
