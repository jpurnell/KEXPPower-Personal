import DiagnosticsKit
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

    @Test("The listener's settings are included, as the stored choices")
    func settings() {
        let defaults = suite()
        defaults.set(RewindWindow.tenMinutes.rawValue, forKey: RewindWindow.storageKey)
        defaults.set(Cushion.twoMinutes.rawValue, forKey: Cushion.storageKey)
        defaults.set(StreamQuality.dataSaver.rawValue, forKey: StreamQuality.storageKey)
        defaults.set(ShowTimeZone.station.rawValue, forKey: ShowTimeZone.storageKey)
        let metadata = DiagnosticReportMetadata.make(defaults: defaults)
        #expect(metadata["rewindWindow"] == RewindWindow.tenMinutes.rawValue)
        #expect(metadata["cushion"] == Cushion.twoMinutes.rawValue)
        #expect(metadata["streamQuality"] == StreamQuality.dataSaver.rawValue)
        #expect(metadata["showTimeZone"] == ShowTimeZone.station.rawValue)
    }

    @Test("A setting that was never chosen reports its default, not nothing")
    func defaults() {
        let metadata = DiagnosticReportMetadata.make(defaults: suite())
        #expect(metadata["rewindWindow"] == RewindWindow.resolve(stored: nil).rawValue)
        #expect(metadata["cushion"] == Cushion.resolve(stored: nil).rawValue)
        #expect(metadata["streamQuality"] == StreamQuality.resolve(stored: nil).rawValue)
    }

    @Test("Only the settings: the version, build and device come from the report itself, and no identifier or free text can ride along")
    func onlyKnownFields() {
        let metadata = DiagnosticReportMetadata.make(defaults: suite())
        #expect(Set(metadata.keys) == ["rewindWindow", "cushion", "streamQuality", "showTimeZone"])
    }

    @Test("Merging adds the app's own entries in time order and keeps the rest of the report as it was")
    func merging() {
        let early = Date(timeIntervalSince1970: 1_000)
        let middle = Date(timeIntervalSince1970: 2_000)
        let late = Date(timeIntervalSince1970: 3_000)
        let base = DiagnosticReport(
            metadata: ["app_version": "3.5.0"],
            logEntries: [.init(timestamp: early, category: "system", level: "info", message: "a"),
                         .init(timestamp: late, category: "system", level: "info", message: "c")],
            generatedAt: late, reportVersion: DiagnosticReport.currentReportVersion)
        let own = [DiagnosticReport.LogEntry(timestamp: middle, category: "Player", level: "info", message: "b")]
        let merged = DiagnosticReportMetadata.merged(base, with: own)
        #expect(merged.logEntries.map(\.message) == ["a", "b", "c"])
        #expect(merged.metadata == ["app_version": "3.5.0"])
        #expect(merged.generatedAt == late)
    }
}
