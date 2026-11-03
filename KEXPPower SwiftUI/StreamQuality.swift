//
//  StreamQuality.swift
//  KEXPPowerExampleSwiftUI
//

import KEXPPower

/// The live-stream quality a listener can choose.
enum StreamQuality: String, CaseIterable, Identifiable, Sendable {
    case standard = "160"
    case dataSaver = "64"

    /// Where the choice is stored in `UserDefaults`.
    static let storageKey = "streamQuality"

    var id: String { rawValue }

    /// The name shown in Settings.
    var label: String {
        switch self {
        case .standard: "Standard (160 kbps)"
        case .dataSaver: "Data saver (64 kbps)"
        }
    }

    /// The library bitrate this quality selects.
    var bitrate: KEXPPower.StreamingBitRate {
        switch self {
        case .standard: .oneSixty
        case .dataSaver: .sixtyFour
        }
    }

    /// The quality for a stored value; standard when nothing valid is stored.
    /// - Parameter stored: The raw value read from `UserDefaults`.
    static func resolve(stored: String?) -> StreamQuality {
        stored.flatMap(StreamQuality.init(rawValue:)) ?? .standard
    }
}
