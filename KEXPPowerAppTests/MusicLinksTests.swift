import Testing
import Foundation
@testable import KEXPPowerExampleSwiftUI

@Suite("MusicLinks search URLs")
struct MusicLinksSearchTests {
    @Test("Spotify search carries artist and track")
    func spotify() {
        #expect(MusicLinks.spotifySearchURL(artist: "Teezo Touchdown", track: "Making Flippy Floppy")?.absoluteString
                == "https://open.spotify.com/search/Teezo%20Touchdown%20Making%20Flippy%20Floppy")
    }

    @Test("A slash in a name stays inside the search term")
    func spotifySlash() {
        #expect(MusicLinks.spotifySearchURL(artist: "AC/DC", track: "Back In Black")?.absoluteString
                == "https://open.spotify.com/search/AC%2FDC%20Back%20In%20Black")
    }

    @Test("Bandcamp search carries artist and album as a query")
    func bandcamp() {
        #expect(MusicLinks.bandcampSearchURL(artist: "Teezo Touchdown", album: "Making Flippy Floppy")?.absoluteString
                == "https://bandcamp.com/search?q=Teezo%20Touchdown%20Making%20Flippy%20Floppy")
    }

    @Test("An ampersand in a name cannot break out of the Bandcamp query")
    func bandcampAmpersand() {
        let url = MusicLinks.bandcampSearchURL(artist: "Simon & Garfunkel", album: "Bookends")
        #expect(url?.absoluteString == "https://bandcamp.com/search?q=Simon%20%26%20Garfunkel%20Bookends")
    }

    @Test("One missing field still gives a search; none gives no link")
    func missingFields() {
        #expect(MusicLinks.spotifySearchURL(artist: "Elias Negash", track: nil)?.absoluteString
                == "https://open.spotify.com/search/Elias%20Negash")
        #expect(MusicLinks.spotifySearchURL(artist: nil, track: nil) == nil)
        #expect(MusicLinks.bandcampSearchURL(artist: "", album: "  ") == nil)
    }
}

@Suite("MusicLinks comment links")
struct MusicLinksCommentTests {
    private let comment = """
    The rapper covered Talking Heads' 1983 song for A24's tribute album.\
     Details: https://www.stereogum.com/2253489/making-flippy-floppy/music/ and https://example.com/tour.\
     Write to someone@example.com or see javascript:alert(1).
    """

    @Test("Web links in a comment are found in order, without trailing punctuation")
    func findsWebLinks() {
        #expect(MusicLinks.links(in: comment).map(\.absoluteString) == [
            "https://www.stereogum.com/2253489/making-flippy-floppy/music/",
            "https://example.com/tour",
        ])
    }

    @Test("Both web schemes are recognised; other schemes are not", arguments: [("http", true), ("https", true), ("ftp", false)])
    func schemes(scheme: String, found: Bool) {
        #expect(MusicLinks.links(in: "Listen at \(scheme)://example.com/a now").isEmpty == !found)
    }

    @Test("Email addresses and script URLs are not treated as links")
    func ignoresOtherSchemes() {
        let found = MusicLinks.links(in: comment)
        #expect(found.allSatisfy { $0.scheme == "https" || $0.scheme == "http" })
    }

    @Test("A repeated link appears once")
    func deduplicates() {
        #expect(MusicLinks.links(in: "https://kexp.org and again https://kexp.org").count == 1)
    }

    @Test("Text without links yields none")
    func noLinks() {
        #expect(MusicLinks.links(in: "").isEmpty)
        #expect(MusicLinks.links(in: "Just words.").isEmpty)
    }

    @Test("The linked comment keeps its text and makes the web links tappable")
    func linkedComment() {
        let attributed = MusicLinks.linkedComment(comment)
        #expect(String(attributed.characters) == comment)
        let linked = attributed.runs.compactMap(\.link)
        #expect(linked.map(\.absoluteString) == [
            "https://www.stereogum.com/2253489/making-flippy-floppy/music/",
            "https://example.com/tour",
        ])
    }
}
