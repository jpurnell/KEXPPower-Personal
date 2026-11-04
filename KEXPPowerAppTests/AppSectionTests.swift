import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("AppSection")
struct AppSectionTests {
    @Test("The sections are Live, Archive and Playlists, in that order")
    func order() {
        #expect(AppSection.allCases == [.live, .archive, .playlists])
    }

    @Test("The app opens on Live")
    func defaultSection() {
        #expect(AppSection.defaultSection == .live)
    }

    @Test("Every section has a distinct title and an icon")
    func titlesAndIcons() {
        let titles = AppSection.allCases.map(\.title)
        #expect(titles == ["Live", "Archive", "Playlists"])
        #expect(Set(titles).count == titles.count)
        #expect(AppSection.allCases.allSatisfy { !$0.systemImage.isEmpty })
    }

    @Test("Only Live is built; the others say they are coming")
    func availability() {
        #expect(AppSection.live.isAvailable)
        #expect(!AppSection.archive.isAvailable)
        #expect(!AppSection.playlists.isAvailable)
        #expect(AppSection.live.comingSoonMessage == nil)
        #expect(AppSection.archive.comingSoonMessage?.isEmpty == false)
        #expect(AppSection.playlists.comingSoonMessage?.isEmpty == false)
    }

    @Test("Sections identify themselves by raw value, for selection")
    func identity() {
        #expect(AppSection.live.id == "live")
        #expect(Set(AppSection.allCases.map(\.id)).count == 3)
    }
}
