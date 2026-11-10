import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

/// The ingest key is not in the source: a build setting from an untracked file puts it in the app's Info.plist, and these
/// are the rules for reading it back. Anything that is not a usable key means the app sends nothing.
@Suite("FieldDiagnosticsConfiguration")
struct FieldDiagnosticsConfigurationTests {
    private let name = FieldDiagnosticsConfiguration.infoKey

    @Test("A key in the Info.plist is used")
    func usable() {
        #expect(FieldDiagnosticsConfiguration.key(from: [name: "abcdefghijklmnop0123456789"]) == "abcdefghijklmnop0123456789")
    }

    @Test("A missing key means no key")
    func missing() {
        #expect(FieldDiagnosticsConfiguration.key(from: [:]) == nil)
    }

    @Test("An empty or blank key means no key: a build without the untracked file")
    func empty() {
        #expect(FieldDiagnosticsConfiguration.key(from: [name: ""]) == nil)
        #expect(FieldDiagnosticsConfiguration.key(from: [name: "   "]) == nil)
    }

    @Test("An unexpanded build setting means no key, not a key that is the setting's name")
    func unexpanded() {
        #expect(FieldDiagnosticsConfiguration.key(from: [name: "$(DIAGNOSTICS_INGEST_KEY)"]) == nil)
    }

    @Test("A value of the wrong type means no key")
    func wrongType() {
        #expect(FieldDiagnosticsConfiguration.key(from: [name: 12345]) == nil)
    }

    @Test("A key too short for the hub to have issued, or with a space in it, means no key")
    func shape() {
        #expect(FieldDiagnosticsConfiguration.key(from: [name: "short"]) == nil)
        #expect(FieldDiagnosticsConfiguration.key(from: [name: "has a space in it 0123456789"]) == nil)
    }

    @Test("Surrounding whitespace from the settings file is trimmed")
    func trimmed() {
        #expect(FieldDiagnosticsConfiguration.key(from: [name: "  abcdefghijklmnop0123456789 \n"]) == "abcdefghijklmnop0123456789")
    }
}
