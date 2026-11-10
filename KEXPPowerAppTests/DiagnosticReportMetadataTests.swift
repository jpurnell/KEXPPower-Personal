import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

/// What a shared diagnostic report says about the app and the listener's settings, so a bug report arrives with the
/// context needed to read it. Nothing here identifies a person: no name, account, location or listening history.
@Suite("Diagnostic report metadata")
struct DiagnosticReportMetadataTests {
    private func suite() -> UserDefaults {
        let name = "metadata-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("The report names the app version and build")
    func versionAndBuild() {
        let metadata = DiagnosticReportMetadata.make(version: "3.4.0", build: "57", defaults: suite())
        #expect(metadata["appVersion"] == "3.4.0")
        #expect(metadata["appBuild"] == "57")
    }

    @Test("The listener's settings are included, as the stored choices")
    func settings() {
        let defaults = suite()
        defaults.set(RewindWindow.tenMinutes.rawValue, forKey: RewindWindow.storageKey)
        defaults.set(Cushion.twoMinutes.rawValue, forKey: Cushion.storageKey)
        defaults.set(StreamQuality.dataSaver.rawValue, forKey: StreamQuality.storageKey)
        defaults.set(ShowTimeZone.station.rawValue, forKey: ShowTimeZone.storageKey)
        let metadata = DiagnosticReportMetadata.make(version: "1", build: "1", defaults: defaults)
        #expect(metadata["rewindWindow"] == RewindWindow.tenMinutes.rawValue)
        #expect(metadata["cushion"] == Cushion.twoMinutes.rawValue)
        #expect(metadata["streamQuality"] == StreamQuality.dataSaver.rawValue)
        #expect(metadata["showTimeZone"] == ShowTimeZone.station.rawValue)
    }

    @Test("A setting that was never chosen reports its default, not nothing")
    func defaults() {
        let metadata = DiagnosticReportMetadata.make(version: "1", build: "1", defaults: suite())
        #expect(metadata["rewindWindow"] == RewindWindow.resolve(stored: nil).rawValue)
        #expect(metadata["cushion"] == Cushion.resolve(stored: nil).rawValue)
        #expect(metadata["streamQuality"] == StreamQuality.resolve(stored: nil).rawValue)
    }

    @Test("Only these fields: no identifier, name or free text can ride along")
    func onlyKnownFields() {
        let metadata = DiagnosticReportMetadata.make(version: "1", build: "1", defaults: suite())
        #expect(Set(metadata.keys) == ["appVersion", "appBuild", "rewindWindow", "cushion", "streamQuality", "showTimeZone"])
    }
}
