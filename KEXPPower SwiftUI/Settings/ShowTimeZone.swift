//
//  ShowTimeZone.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// Which time zone the app draws times of day in: the listener's own, or the station's.
enum ShowTimeZone: String, CaseIterable, Identifiable, Sendable {
    case mine
    case station

    /// Where the choice is stored in `UserDefaults`.
    static let storageKey = "showTimeZone"

    var id: String { rawValue }

    /// The name shown in Settings.
    var label: String {
        switch self {
        case .mine: "My time zone"
        case .station: "Seattle (the station's)"
        }
    }

    /// The zone to draw times in. The listener's follows the device, including when it travels.
    var zone: TimeZone {
        switch self {
        case .mine: .autoupdatingCurrent
        case .station: ArchiveTiming.stationTimeZone
        }
    }

    /// The choice for a stored value; the listener's own zone when nothing valid is stored.
    /// - Parameter stored: The raw value read from `UserDefaults`.
    static func resolve(stored: String?) -> ShowTimeZone {
        stored.flatMap(ShowTimeZone.init(rawValue:)) ?? .mine
    }
}
