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

    /// The event as the client library sends it: a kind, a severity and typed fields.
    var record: EventRecord {
        switch self {
        case .launch(let previous):
            // A run that ended while the app was in use is a crash or a force-quit; every other ending is routine.
            EventRecord(
                kind: "launch", severity: previous == .endedWhileActive ? .warning : .info, at: Date(),
                fields: ["previousRun": .code(previous.rawValue)])
        case .rewindUnavailable(let reason):
            EventRecord(kind: "rewindUnavailable", severity: .warning, at: Date(), fields: ["reason": .code(reason.rawValue)])
        }
    }
}
