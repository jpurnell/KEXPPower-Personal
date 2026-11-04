import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("WidgetConstants")
struct WidgetConstantsTests {
    @Test("The App Group follows each platform's rule: team-prefixed on the Mac, group.-prefixed elsewhere")
    func groupIDFormat() {
        #if os(macOS)
        // On macOS a group that starts with the Team ID needs no portal registration or explicit profile; a group.
        // identifier would be refused without one, and the widget would find nothing to read.
        #expect(WidgetConstants.groupID == "BNDA9Y6YV9.com.JPEnterprises.Spinner")
        #else
        #expect(WidgetConstants.groupID == "group.com.JPEnterprises.Spinner")
        #endif
    }

    @Test("The widget's kind is stable, because WidgetKit reloads a widget by it")
    func kind() {
        #expect(WidgetConstants.kind == "NowPlayingWidget")
    }
}
