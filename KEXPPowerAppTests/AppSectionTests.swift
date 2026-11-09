import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("AppSection")
struct AppSectionTests {
    @Test("The sections are Live, Archive, Review and Now Playing, in that order; there is no Playlists placeholder")
    func order() {
        #expect(AppSection.allCases == [.live, .archive, .review, .nowPlaying])
    }

    @Test("Review is shown only where playlists can be saved to; Live and Archive always are")
    func visibility() {
        #expect(AppSection.visible(canSaveToPlaylists: true) == [.live, .archive, .review])
        #expect(AppSection.visible(canSaveToPlaylists: false) == [.live, .archive])
    }

    @Test("Now Playing is shown only when asked for (tvOS, once something has played), and last")
    func nowPlayingVisibility() {
        #expect(AppSection.visible(canSaveToPlaylists: true, showsNowPlaying: true)
                == [.live, .archive, .review, .nowPlaying])
        #expect(AppSection.visible(canSaveToPlaylists: false, showsNowPlaying: true)
                == [.live, .archive, .nowPlaying])
        #expect(!AppSection.visible(canSaveToPlaylists: true, showsNowPlaying: false).contains(.nowPlaying))
    }

    @Test("The app opens on Live")
    func defaultSection() {
        #expect(AppSection.defaultSection == .live)
    }

    @Test("Every section has a distinct title and an icon")
    func titlesAndIcons() {
        let titles = AppSection.allCases.map(\.title)
        #expect(titles == ["Live", "Archive", "Review", "Now Playing"])
        #expect(Set(titles).count == titles.count)
        #expect(AppSection.allCases.allSatisfy { !$0.systemImage.isEmpty })
    }

    @Test("Sections identify themselves by raw value, for selection")
    func identity() {
        #expect(AppSection.live.id == "live")
        #expect(Set(AppSection.allCases.map(\.id)).count == 4)
    }
}
