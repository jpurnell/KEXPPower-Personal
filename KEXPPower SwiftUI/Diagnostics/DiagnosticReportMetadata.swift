//
//  DiagnosticReportMetadata.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// What a shared diagnostic report says about the app and the listener's settings, so a bug report arrives with the
/// context needed to read it.
///
/// A fixed set of fields and nothing else: no name, account, identifier, location or listening history, and no free
/// text. The report also carries the log, which holds show and song names the app was handling; the Settings note says
/// so, and the listener chooses where the file goes.
enum DiagnosticReportMetadata {
    /// The report's metadata.
    /// - Parameters:
    ///   - version: The app's marketing version.
    ///   - build: The app's build number.
    ///   - defaults: Where the settings are kept; injected so tests use a throwaway store.
    static func make(version: String, build: String, defaults: UserDefaults = .standard) -> [String: String] {
        [
            "appVersion": version,
            "appBuild": build,
            "rewindWindow": RewindWindow.resolve(stored: defaults.string(forKey: RewindWindow.storageKey)).rawValue,
            "cushion": Cushion.resolve(stored: defaults.string(forKey: Cushion.storageKey)).rawValue,
            "streamQuality": StreamQuality.resolve(stored: defaults.string(forKey: StreamQuality.storageKey)).rawValue,
            "showTimeZone": ShowTimeZone.resolve(stored: defaults.string(forKey: ShowTimeZone.storageKey)).rawValue,
        ]
    }

    /// The metadata for this running app, read from its bundle and its stored settings.
    static func current() -> [String: String] {
        let info = Bundle.main.infoDictionary
        return make(
            version: info?["CFBundleShortVersionString"] as? String ?? "unknown",
            build: info?["CFBundleVersion"] as? String ?? "unknown")
    }
}
