//
//  ListeningSettings.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// The settings that decide how the live stream is played: its quality and how much of it is kept.
struct ListeningSettings: Equatable, Sendable {
    var quality: StreamQuality
    var window: RewindWindow

    /// The settings as stored, with the default for any value that is missing or not one of the choices.
    /// - Parameter defaults: Where the settings are kept; injected so tests use a throwaway store.
    static func current(defaults: UserDefaults = .standard) -> ListeningSettings {
        ListeningSettings(
            quality: StreamQuality.resolve(stored: defaults.string(forKey: StreamQuality.storageKey)),
            window: RewindWindow.resolve(stored: defaults.string(forKey: RewindWindow.storageKey)))
    }

    /// Whether going from one set of settings to another means the live stream must be rebuilt: a new address or a
    /// new window cannot be had by the stream already playing.
    static func restartsLive(from old: ListeningSettings, to new: ListeningSettings) -> Bool {
        old != new
    }

    /// About how many bytes the window holds on disk at a quality; zero when the window is off.
    static func approximateBytes(window: RewindWindow, quality: StreamQuality) -> Int {
        guard let seconds = window.duration else { return 0 }
        return Int(seconds) * bytesPerSecond(of: quality)
    }

    /// What the stream delivers each second: 160 kbps is 20,000 bytes, and 64 kbps is 8,000.
    private static func bytesPerSecond(of quality: StreamQuality) -> Int {
        switch quality {
        case .standard: 20_000
        case .dataSaver: 8_000
        }
    }
}
