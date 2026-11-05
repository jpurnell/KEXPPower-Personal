import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("UITestFixtures")
struct UITestFixturesTests {
    @Test("The launch flag turns the fixtures on, and its absence leaves the live station")
    func activation() {
        #expect(UITestFixtures.isActive(arguments: ["Spinner", "-uitest-fixtures"]))
        #expect(!UITestFixtures.isActive(arguments: ["Spinner"]))
        #expect(!UITestFixtures.isActive(arguments: []))
    }

    @Test("The fixtures are a fixed number of different songs, so rows can be told apart")
    func distinctPlays() {
        let plays = UITestFixtures.plays
        #expect(plays.count == UITestFixtures.playCount)
        #expect(Set(plays.compactMap(\.id)).count == UITestFixtures.playCount)
    }
}
