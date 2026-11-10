//
//  DiagnosticReportMetadata.swift
//  KEXPPowerExampleSwiftUI
//

import DiagnosticsKit
import Foundation

/// What a shared diagnostic report says about the listener's settings, so a bug report arrives with the context needed to
/// read it. The report itself adds the app version and build, the bundle ID, the device model and the OS version.
///
/// A fixed set of fields and nothing else: no name, account, identifier, location or listening history, and no free
/// text. The report also carries the log, which holds show and song names the app was handling; the Settings note says
/// so, and the listener chooses where the file goes.
enum DiagnosticReportMetadata {
    /// The listener's settings, as stored.
    /// - Parameter defaults: Where the settings are kept; injected so tests use a throwaway store.
    static func make(defaults: UserDefaults = .standard) -> [String: String] {
        [
            "rewindWindow": RewindWindow.resolve(stored: defaults.string(forKey: RewindWindow.storageKey)).rawValue,
            "cushion": Cushion.resolve(stored: defaults.string(forKey: Cushion.storageKey)).rawValue,
            "streamQuality": StreamQuality.resolve(stored: defaults.string(forKey: StreamQuality.storageKey)).rawValue,
            "showTimeZone": ShowTimeZone.resolve(stored: defaults.string(forKey: ShowTimeZone.storageKey)).rawValue,
        ]
    }

    /// The report the Send Diagnostics button shares: the system log and device details from DiagnosticsKit, with the
    /// app's own log merged in and the listener's settings added.
    static func report() async throws -> DiagnosticReport {
        let base = try await DiagnosticReportCollector(subsystem: "com.JPEnterprises.Spinner").collect(metadata: make())
        return merged(base, with: DiagnosticLog.app.reportEntries())
    }

    /// `base` with `entries` added, in time order. Everything else in the report is kept as it was.
    static func merged(_ base: DiagnosticReport, with entries: [DiagnosticReport.LogEntry]) -> DiagnosticReport {
        DiagnosticReport(
            metadata: base.metadata,
            logEntries: (base.logEntries + entries).sorted { $0.timestamp < $1.timestamp },
            generatedAt: base.generatedAt,
            reportVersion: base.reportVersion,
            telemetry: base.telemetry)
    }
}
