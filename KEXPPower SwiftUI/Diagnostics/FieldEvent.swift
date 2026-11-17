//
//  FieldEvent.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import SwiftDiagnosticsClient

/// Why a live rewind was not available and the app played the stream directly.
enum RewindReason: String, Sendable, CaseIterable {
    /// No audio arrived at the local recorder in time.
    case noAudioInTime
    /// The local server that plays the recorded window could not start.
    case serverFailed
    /// Going back to live was requested and no audio was moving after the watch gave up.
    case gaveUpWatching
}

/// What Spinner may report to the diagnostics hub: typed health events and nothing else.
///
/// The privacy line is the shape of this type. Every case carries a value from a fixed list, never a string a person or a
/// station wrote, so a show, a song, a station name or a setting cannot travel in one. The hub holds the same line from its
/// side with the schema in `project/diagnostics/spinner-schema.json`, and a test checks every case against that file.
enum FieldEvent: Sendable, Equatable {
    /// The app started, and the run before it ended this way.
    case launch(previousRun: PreviousRun)
    /// A live rewind could not be used and the stream was played directly.
    case rewindUnavailable(RewindReason)
    /// A call to KEXP's API failed.
    case apiFailed(APIEndpoint, APIFailure)
    /// Live was asked for and audio did, or did not, begin: how long it took, what the network was, where the sound went.
    case liveStart(LiveStart)
    /// Playback stopped moving while the listener wanted it, and what became of that: why, how long, what was buffered, over what network and to
    /// what output.
    case playbackStall(PlaybackStall)
    /// The stream's connection was lost and came back, whether or not it was heard: how long, how much audio the player had at the loss, over what
    /// network and to what output, and whether a stall followed.
    case streamOutage(StreamOutage)

    /// What makes two failures the same one, for ``FieldEventCoalescer``; `nil` for events that are never held back.
    var coalescingKey: String? {
        switch self {
        case .apiFailed(let endpoint, let failure):
            "apiFailed.\(endpoint.rawValue).\(failure.outcome.rawValue).\(failure.status.map(String.init) ?? "-")"
        case .launch, .rewindUnavailable, .liveStart, .playbackStall, .streamOutage:
            nil
        }
    }

    /// The event as the client library sends it: a kind, a severity and typed fields.
    var record: EventRecord {
        switch self {
        case .launch(let previous):
            // A run that ended while the app was in use is a crash or a force-quit; every other ending is routine.
            return EventRecord(
                kind: "launch", severity: previous == .endedWhileActive ? .warning : .info, at: Date(),
                fields: ["previousRun": .code(previous.rawValue)])
        case .rewindUnavailable(let reason):
            return EventRecord(kind: "rewindUnavailable", severity: .warning, at: Date(), fields: ["reason": .code(reason.rawValue)])
        case .apiFailed(let endpoint, let failure):
            var fields: [String: FieldValue] = ["endpoint": .code(endpoint.rawValue), "outcome": .code(failure.outcome.rawValue)]
            if let status = failure.status { fields["status"] = .int(status) }
            return EventRecord(kind: "apiFailed", severity: .warning, at: Date(), fields: fields)
        case .playbackStall(let stall):
            let severity: Severity = switch stall.outcome {
            case .resumed, .listenerPaused: .info
            case .rebuilt, .restarted, .unfinished: .warning
            case .gaveUp: .error
            }
            return EventRecord(
                kind: "playbackStall", severity: severity, at: Date(),
                fields: [
                    "reason": .code(stall.reason.rawValue), "took": .code(stall.took.rawValue), "ahead": .code(stall.ahead.rawValue),
                    "network": .code(stall.network.rawValue), "route": .code(stall.route.rawValue), "outcome": .code(stall.outcome.rawValue),
                    "cycles": .int(stall.cycles),
                ])
        case .streamOutage(let outage):
            return EventRecord(
                kind: "streamOutage", severity: outage.outcome == .covered ? .info : .warning, at: Date(),
                fields: [
                    "took": .code(outage.took.rawValue), "ahead": .code(outage.ahead.rawValue), "network": .code(outage.network.rawValue),
                    "route": .code(outage.route.rawValue), "outcome": .code(outage.outcome.rawValue), "attempts": .int(outage.attempts),
                ])
        case .liveStart(let start):
            let severity: Severity = switch start.outcome {
            case .started: .info
            case .rebuilt, .fellBackDirect, .recoveredOnNetwork: .warning
            case .gaveUp: .error
            }
            return EventRecord(
                kind: "liveStart", severity: severity, at: Date(),
                fields: [
                    "outcome": .code(start.outcome.rawValue), "took": .code(start.took.rawValue),
                    "network": .code(start.network.rawValue), "route": .code(start.route.rawValue),
                ])
        }
    }
}
