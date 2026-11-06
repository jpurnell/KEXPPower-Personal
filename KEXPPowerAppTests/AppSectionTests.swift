import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("AppSection")
struct AppSectionTests {
    @Test("The sections are Live, Archive, Playlists and Review, in that order")
    func order() {
        #expect(AppSection.allCases == [.live, .archive, .playlists, .review])
    }

    @Test("Review is shown only where playlists can be saved to; the others always are")
    func visibility() {
        #expect(AppSection.visible(canSaveToPlaylists: true) == [.live, .archive, .playlists, .review])
        #expect(AppSection.visible(canSaveToPlaylists: false) == [.live, .archive, .playlists])
    }

    @Test("The app opens on Live")
    func defaultSection() {
        #expect(AppSection.defaultSection == .live)
    }

    @Test("Every section has a distinct title and an icon")
    func titlesAndIcons() {
        let titles = AppSection.allCases.map(\.title)
        #expect(titles == ["Live", "Archive", "Playlists", "Review"])
        #expect(Set(titles).count == titles.count)
        #expect(AppSection.allCases.allSatisfy { !$0.systemImage.isEmpty })
    }

    @Test("Live, Archive and Review are built; Playlists says it is coming")
    func availability() {
        #expect(AppSection.live.isAvailable)
        #expect(AppSection.archive.isAvailable)
        #expect(!AppSection.playlists.isAvailable)
        #expect(AppSection.review.isAvailable)
        #expect(AppSection.live.comingSoonMessage == nil)
        #expect(AppSection.archive.comingSoonMessage == nil)
        #expect(AppSection.review.comingSoonMessage == nil)
        #expect(AppSection.playlists.comingSoonMessage?.isEmpty == false)
    }

    @Test("Sections identify themselves by raw value, for selection")
    func identity() {
        #expect(AppSection.live.id == "live")
        #expect(Set(AppSection.allCases.map(\.id)).count == 4)
    }
}
