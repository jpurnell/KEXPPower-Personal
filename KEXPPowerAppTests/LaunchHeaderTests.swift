import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

/// The first line of each launch in the diagnostic log: which build this is, what it is running on, and how the last
/// run ended, so a log read later says what produced it.
@Suite("LaunchHeader")
struct LaunchHeaderTests {
    @Test("The header names the version, build, system, device and the previous run")
    func line() {
        let text = LaunchHeader.line(
            version: "3.5.1", build: "1", system: "iOS 27.3", device: "iPhone16,1", previous: .endedWhileActive)
        #expect(text == "launched 3.5.1 (1) on iOS 27.3, iPhone16,1; previous run: ended while the app was in use")
    }

    @Test("A first launch says so")
    func firstLaunch() {
        let text = LaunchHeader.line(version: "1", build: "1", system: "macOS 27", device: "arm64", previous: .firstLaunch)
        #expect(text.hasSuffix("previous run: first launch"))
    }

    @Test("The device model comes from the system and is never empty")
    func deviceModel() {
        #expect(!LaunchHeader.deviceModel().isEmpty)
    }

    @Test("The system name carries the platform and version")
    func systemName() {
        let text = LaunchHeader.systemName()
        #expect(!text.isEmpty)
        #expect(text.contains(" "))
    }
}
