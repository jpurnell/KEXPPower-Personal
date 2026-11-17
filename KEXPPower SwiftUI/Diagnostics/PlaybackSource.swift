//
//  PlaybackSource.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// Where the sound is rendered: by the phone, or by something that fetches the stream itself.
///
/// The local recording is at the phone's own loopback address, so only a destination the phone renders for can use it. A receiver (AirPlay) fetches the
/// item itself and cannot reach that address, and a route this app does not know might be either, so it is treated as the safe case.
enum PlaybackSource: Sendable, Equatable {
    /// The phone renders the sound: its speaker, headphones, Bluetooth, or a car over CarPlay.
    case phone
    /// The destination fetches and renders the stream: AirPlay, or anything handed to external playback.
    case receiver
    /// A route this app does not know, such as whatever a wearable reports.
    case unknown

    /// - Parameters:
    ///   - route: Where the audio session says the sound is going.
    ///   - externalPlayback: Whether the player has handed the item to an external destination; that decides, whatever the route says.
    init(route: OutputRoute, externalPlayback: Bool) {
        if externalPlayback {
            self = .receiver
            return
        }
        switch route {
        case .speaker, .headphones, .bluetooth, .carPlay: self = .phone
        case .airPlay: self = .receiver
        case .other: self = .unknown
        }
    }
}

/// Why live is played from the stream itself and not through the recording: a code, for the journal and a report.
enum DirectReason: String, Sendable, Equatable, CaseIterable, Codable {
    /// A receiver fetches the item itself and cannot reach the phone's recording.
    case receiver
    /// The route is not one this app knows, so the stream that works from anywhere plays.
    case unknownRoute
    /// There is no recording to play (the setting is off, or it could not start).
    case recordingUnavailable
    /// The start was under way through the recording and the evidence showed it would not play.
    case evidenceFallBack
}

/// How live is played.
enum LivePlan: Sendable, Equatable {
    case recording
    case direct(DirectReason)

    /// The plan for a source: **the recording only where the phone is the source**, the stream everywhere else.
    static func choose(source: PlaybackSource, recordingAvailable: Bool) -> LivePlan {
        switch source {
        case .receiver: .direct(.receiver)
        case .unknown: .direct(.unknownRoute)
        case .phone: recordingAvailable ? .recording : .direct(.recordingUnavailable)
        }
    }
}

/// What the listener may do under a plan, decided with the plan so the controls do not change while a start is under way.
struct PlaybackCapabilities: Sendable, Equatable {
    /// Whether the recording's window can be rewound and skipped within.
    var canRewind: Bool

    init(canRewind: Bool) {
        self.canRewind = canRewind
    }

    init(plan: LivePlan) {
        canRewind = plan == .recording
    }
}
