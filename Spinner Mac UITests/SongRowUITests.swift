import XCTest

/// Drives the real Mac app against fixed songs (`-uitest-fixtures`) to check what unit tests cannot: where a click
/// lands, and what the keyboard does.
@MainActor
final class SongRowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-fixtures"]
        app.launch()
        app.activate()
        _ = app.windows.firstMatch.waitForExistence(timeout: 10)
        if !app.windows["main"].exists {
            // A restored launch can open only the mini player; Show Full Window (⌥⌘M) is the real way back.
            app.typeKey("m", modifierFlags: [.command, .option])
        }
        XCTAssertTrue(app.windows["main"].waitForExistence(timeout: 10), "The main window did not appear")
    }

    override func tearDown() async throws {
        app.terminate()
    }

    private var rows: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: "song-row") }

    /// The Spotify link only exists in an expanded row, so its presence says the row is open.
    private func isExpanded(_ row: XCUIElement) -> Bool {
        row.links["Spotify"].exists || row.buttons["Spotify"].exists
    }

    func testEveryFixtureSongHasARow() {
        XCTAssertTrue(rows.element(boundBy: 0).waitForExistence(timeout: 10))
        // The list is lazy, so only the rows near the window exist; Now Playing and at least one more should.
        XCTAssertGreaterThanOrEqual(rows.count, 2)
    }

    func testAClickAnywhereInAPreviousRowExpandsIt() {
        let row = rows.element(boundBy: 2)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertFalse(isExpanded(row))
        // The old defect answered only the top of a row; try the middle and the bottom as well as the top.
        for fraction in [0.15, 0.5, 0.9] {
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: fraction)).click()
            XCTAssertTrue(isExpanded(row), "A click \(Int(fraction * 100))% down the row did not expand it")
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).click()
            XCTAssertFalse(isExpanded(row), "A second click did not collapse the row")
        }
    }

    /// The row that holds keyboard focus, if any. XCUIElement has no public focus property on the Mac; its description
    /// lists "Keyboard Focused" for an element and for the parts inside it that hold focus.
    private func focusedRow() -> XCUIElement? {
        (0..<rows.count).map { rows.element(boundBy: $0) }.first { $0.debugDescription.contains("Keyboard Focused") }
    }

    func testTabReachesARowAndReturnExpandsIt() throws {
        XCTAssertTrue(rows.element(boundBy: 0).waitForExistence(timeout: 10))
        app.typeKey(.tab, modifierFlags: [])
        let row = try XCTUnwrap(focusedRow(), "Tab never put keyboard focus on a row")
        XCTAssertFalse(isExpanded(row))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(isExpanded(row), "Return did not expand the focused row")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertFalse(isExpanded(row), "A second Return did not collapse it")
    }

    func testOpenInMusicButtonIsOnTheSongs() {
        let buttons = app.buttons.matching(identifier: "open-in-music")
        XCTAssertTrue(buttons.element(boundBy: 0).waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(buttons.count, 2)
        XCTAssertTrue(buttons.element(boundBy: 0).isHittable)
    }
}
