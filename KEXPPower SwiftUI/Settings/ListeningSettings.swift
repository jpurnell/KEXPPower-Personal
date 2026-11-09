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

    /// The line under the window picker: what is kept, and how much room it takes.
    static func windowNote(window: RewindWindow, quality: StreamQuality) -> String {
        guard let seconds = window.duration else {
            return "Plays the stream directly. There is no pause or rewind."
        }
        let minutes = Int(seconds / 60)
        let size = byteText(approximateBytes(window: window, quality: quality))
        return "Keeps the last \(minutes) minutes so you can pause, go back and ride through a dead zone. Uses about \(size)."
    }

    /// The line under the cushion picker: what the bolt does, and the length actually kept when the window is short.
    static func cushionNote(cushion: Cushion, window: RewindWindow) -> String {
        guard let kept = cushion.effective(forWindow: window.duration), let asked = cushion.duration else {
            return "The bolt goes straight to live. Choose a cushion to stay a few minutes behind, so a tunnel does not stop the music."
        }
        let keptText = minutesText(kept)
        guard kept < asked else {
            return "The bolt returns to \(keptText) behind live, which a tunnel will not interrupt. Pausing or rewinding builds it; Cushion now makes it at once."
        }
        return "The window is shorter than that, so the cushion is held to \(keptText) to leave room to rewind."
    }

    private static func minutesText(_ seconds: TimeInterval) -> String {
        // 5 reads "5" and 2.5 reads "2.5".
        let minutes = (seconds / 60).formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US")))
        return "\(minutes) minutes"
    }

    /// The line under the quality picker: how much data an hour of listening uses.
    static func qualityNote(for quality: StreamQuality) -> String {
        "About \(byteText(3_600 * bytesPerSecond(of: quality))) an hour."
    }

    private static func byteText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// What the stream delivers each second: 160 kbps is 20,000 bytes, and 64 kbps is 8,000.
    private static func bytesPerSecond(of quality: StreamQuality) -> Int {
        switch quality {
        case .standard: 20_000
        case .dataSaver: 8_000
        }
    }
}
