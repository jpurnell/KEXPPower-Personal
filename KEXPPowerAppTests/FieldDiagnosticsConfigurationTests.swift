import Foundation
import SwiftDiagnosticsClient
import Testing
@testable import KEXPPowerExampleSwiftUI

/// Where Spinner sends, and how it finds its key. The rules for a usable key are the package's (`IngestKeyTests`); what is Spinner's is which
/// Info.plist entry and which endpoint.
@Suite("FieldDiagnosticsConfiguration")
struct FieldDiagnosticsConfigurationTests {
    @Test("The key is the Info.plist entry the untracked settings file fills, as the package reads it")
    func infoKeyName() {
        #expect(FieldDiagnosticsConfiguration.infoKey == "DiagnosticsIngestKey")
        #expect(FieldDiagnosticsConfiguration.infoKey == IngestKey.defaultInfoKey)
    }

    @Test("The endpoint is the hub's ingest route, over https")
    func endpoint() throws {
        let endpoint = try #require(FieldDiagnosticsConfiguration.endpoint)
        #expect(endpoint.scheme == "https")
        #expect(endpoint.path == DiagnosticsWire.ingestPath)
    }
}
