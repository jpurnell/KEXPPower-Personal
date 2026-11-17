//
//  StreamOutage.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// How the stream's connection ended or came back, as the recorder says it.
enum RecorderEvent: Sendable, Equatable {
    /// A connection that had been delivering audio failed or ended.
    case lost
    /// The recorder is trying again after a loss.
    case attempting
    /// Audio is arriving again after a loss.
    case restored
}

/// How an outage of the stream's connection ended, as far as the listener went.
enum StreamOutageOutcome: String, Sendable, CaseIterable, Codable {
    /// The player had enough audio recorded to play through it: nothing was heard.
    case covered
    /// A stall began while it lasted: some of it was heard as silence.
    case stalled
    /// The app was stopped before it ended; how long it lasted is the longest the app saw (right-censored).
    case unfinished
}

/// One outage of the stream's connection, from the moment a connection that had been delivering audio failed to the moment audio came back,
/// **whether or not anyone heard it**. A stall is only the audible part (the outage less the audio the player already had); the part the buffer
/// covered is seen only here, and without it no estimate of how long outages last, or of what a cushion would have covered, is unbiased.
struct StreamOutage: Sendable, Equatable {
    /// The most attempts reported; the schema bounds the number so the cap on retries can change without a schema change.
    static let maximumAttempts = 50

    let took: OutageDuration
    /// How much audio the player had recorded ahead of the playhead **at the moment of the loss**.
    let ahead: AheadBucket
    let network: NetworkKind
    let route: OutputRoute
    let outcome: StreamOutageOutcome
    /// How many times the recorder tried again before audio came back.
    let attempts: Int

    /// An outage still open when the app stopped, reported at the next launch as `unfinished`.
    static func unfinished(_ open: OpenStreamOutage) -> StreamOutage {
        StreamOutage(
            took: OutageDuration(seconds: open.lastSeenAt - open.startedAt), ahead: open.ahead, network: open.network, route: open.route,
            outcome: .unfinished, attempts: min(open.attempts, maximumAttempts))
    }
}

/// An outage that has begun and not ended, described so it can be written down in case the app stops first.
struct OpenStreamOutage: Sendable, Equatable, Codable {
    /// When the connection was lost, in seconds since 1970 (so it can be read at a later launch).
    var startedAt: TimeInterval
    /// The last moment the app saw it still going.
    var lastSeenAt: TimeInterval
    var ahead: AheadBucket
    var network: NetworkKind
    var route: OutputRoute
    var attempts: Int
    /// Whether a stall began while it lasted.
    var stalled: Bool
}

/// Follows the stream's connection down and up. Pure: the times and what was buffered are given to it.
///
/// What was buffered, the network and the output are taken **at the loss**, because that is what decides whether the outage is heard.
struct StreamOutageObserver: Sendable {
    private(set) var openOutage: OpenStreamOutage?

    /// The connection was lost. A loss while one is already open changes nothing: the first loss's start and buffer stand.
    mutating func lost(at time: TimeInterval, aheadSeconds: Double?, network: NetworkKind, route: OutputRoute) {
        guard openOutage == nil else { return }
        openOutage = OpenStreamOutage(
            startedAt: time, lastSeenAt: time, ahead: AheadBucket(seconds: aheadSeconds), network: network, route: route, attempts: 0, stalled: false)
    }

    /// The recorder tried again.
    mutating func attempted() {
        openOutage?.attempts += 1
    }

    /// A stall began while the outage was open.
    mutating func stallBegan() {
        openOutage?.stalled = true
    }

    /// The app saw the outage still going at this time.
    mutating func heard(at time: TimeInterval) {
        guard var open = openOutage, time > open.lastSeenAt else { return }
        open.lastSeenAt = time
        openOutage = open
    }

    /// Audio came back. Returns the outage, or `nil` if none was open.
    mutating func restored(at time: TimeInterval) -> StreamOutage? {
        guard let open = openOutage else { return nil }
        openOutage = nil
        return StreamOutage(
            took: OutageDuration(seconds: time - open.startedAt), ahead: open.ahead, network: open.network, route: open.route,
            outcome: open.stalled ? .stalled : .covered, attempts: min(open.attempts, StreamOutage.maximumAttempts))
    }
}
