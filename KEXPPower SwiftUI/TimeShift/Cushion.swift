//
//  Cushion.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// How far behind live the listener asks to stay, so that a lost signal (a subway tunnel) does not stop the music: the
/// recording already holds what plays next.
///
/// Being behind comes from pausing or rewinding; this holds it. The bolt returns to the cushion instead of the newest
/// audio.
enum Cushion: String, CaseIterable, Identifiable, Sendable {
    case off
    case twoMinutes = "2"
    case fiveMinutes = "5"

    /// Where the choice is stored in `UserDefaults`.
    static let storageKey = "cushion"

    var id: String { rawValue }

    /// The name shown in Settings.
    var label: String {
        switch self {
        case .off: "Off (the bolt goes to live)"
        case .twoMinutes: "2 minutes"
        case .fiveMinutes: "5 minutes"
        }
    }

    /// How many seconds behind live, or `nil` for none.
    var duration: TimeInterval? {
        switch self {
        case .off: nil
        case .twoMinutes: 120
        case .fiveMinutes: 300
        }
    }

    /// The choice for a stored value; Off when nothing valid is stored.
    /// - Parameter stored: The raw value read from `UserDefaults`.
    static func resolve(stored: String?) -> Cushion {
        stored.flatMap(Cushion.init(rawValue:)) ?? .off
    }

    /// The cushion in force for a rewind window: the choice, never more than half the window, so there is always room
    /// to rewind further.
    /// - Parameter window: The window's length in seconds, or `nil` when there is none. A value that is not a positive,
    ///   finite number means no window, and so no cushion.
    func effective(forWindow window: TimeInterval?) -> TimeInterval? {
        guard let duration, let window, window.isFinite, window > 0 else { return nil }
        return min(duration, window / 2)
    }
}

/// What the live bolt does, given where the listener is and whether they keep a cushion.
enum LiveBolt: Equatable, Sendable {
    /// Nothing to catch up to.
    case hidden
    /// Skip ahead to the newest audio (no cushion is kept).
    case catchUpToLive
    /// Skip ahead to the cushion, from further behind.
    case backToCushion
    /// Give the cushion up and go to the newest audio.
    case goFullyLive
    /// At live with a cushion kept: go back to the cushion, replaying what was just heard.
    case cushionNow

    /// The bolt for a place in the window.
    /// - Parameters:
    ///   - window: Where the listener is.
    ///   - cushion: The seconds to stay behind live, or `nil` for none.
    static func choose(window: LiveWindow, cushion: TimeInterval?) -> LiveBolt {
        guard let cushion, cushion > 0 else { return window.isLive ? .hidden : .catchUpToLive }
        if window.isAtCushion(cushion) { return .goFullyLive }
        if window.isLive { return .cushionNow }
        return window.behindLive > cushion ? .backToCushion : .goFullyLive
    }
}
