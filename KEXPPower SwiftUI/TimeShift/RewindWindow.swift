//
//  RewindWindow.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// How much of the live stream the app keeps so the listener can pause, go back and ride through a dead zone.
enum RewindWindow: String, CaseIterable, Identifiable, Sendable {
    case off
    case fiveMinutes = "5"
    case tenMinutes = "10"

    /// Where the choice is stored in `UserDefaults`.
    static let storageKey = "rewindWindow"

    var id: String { rawValue }

    /// The name shown in Settings.
    var label: String {
        switch self {
        case .off: "Off (plays the stream directly)"
        case .fiveMinutes: "5 minutes"
        case .tenMinutes: "10 minutes"
        }
    }

    /// How many seconds are kept, or `nil` when nothing is.
    var duration: TimeInterval? {
        switch self {
        case .off: nil
        case .fiveMinutes: 300
        case .tenMinutes: 600
        }
    }

    /// The window for a stored value; ten minutes when nothing valid is stored.
    /// - Parameter stored: The raw value read from `UserDefaults`.
    static func resolve(stored: String?) -> RewindWindow {
        stored.flatMap(RewindWindow.init(rawValue:)) ?? .tenMinutes
    }
}
