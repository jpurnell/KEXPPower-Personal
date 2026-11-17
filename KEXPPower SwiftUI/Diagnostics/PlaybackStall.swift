//
//  PlaybackStall.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// How long an outage lasted, in steps whose edges include the two cushion lengths (120 and 300 seconds), so what fraction of outages a cushion
/// of that length would have bridged can be read straight off the counts. (A live start has its own, coarser steps: ``StartDuration``.)
enum OutageDuration: String, Sendable, CaseIterable, Codable {
    case under2, from2to5, from5to15, from15to40, from40to120, from120to300, over300

    /// - Parameter seconds: How long it lasted; a negative or non-numeric value reads as the shortest step.
    init(seconds: TimeInterval) {
        switch seconds {
        case 300...: self = .over300
        case 120...: self = .from120to300
        case 40...: self = .from40to120
        case 15...: self = .from15to40
        case 5...: self = .from5to15
        case 2...: self = .from2to5
        default: self = .under2
        }
    }
}

/// How much audio was buffered ahead of the playhead when a stall began: the quantity that decides whether an outage was heard. It is a fact about
/// playback and not a setting, so it can be reported where a preference cannot.
enum AheadBucket: String, Sendable, CaseIterable, Codable {
    case none, under30, from30to120, from120to300, over300

    /// - Parameter seconds: Seconds buffered ahead, or `nil` if unknown; none, unknown or not numeric reads as `none`.
    init(seconds: TimeInterval?) {
        guard let seconds, seconds.isFinite, seconds > 0 else { self = .none; return }
        switch seconds {
        case 300...: self = .over300
        case 120...: self = .from120to300
        case 30...: self = .from30to120
        default: self = .under30
        }
    }
}

/// Why playback stopped moving while the listener wanted it.
enum StallReason: String, Sendable, CaseIterable, Codable {
    /// There was no network when it began.
    case networkLost
    /// The network was there and the buffer ran dry.
    case bufferEmpty
    /// The player's item failed.
    case itemFailed
    /// The local recording's server did not answer.
    case localServer
    /// None of the above could be told.
    case unknown
}

/// How a stall ended.
enum StallOutcome: String, Sendable, CaseIterable, Codable {
    /// Audio began moving again by itself.
    case resumed
    /// The player's item was rebuilt and audio began.
    case rebuilt
    /// Live was started again and audio began.
    case restarted
    /// The app stopped trying.
    case gaveUp
    /// The listener paused while it lasted.
    case listenerPaused
    /// The app was stopped before it ended; how long it lasted is the longest the app saw (right-censored).
    case unfinished
}

/// One stall, as a report carries it. Every part is a code or a bounded number.
struct PlaybackStall: Sendable, Equatable {
    let reason: StallReason
    let took: OutageDuration
    let ahead: AheadBucket
    let network: NetworkKind
    let route: OutputRoute
    let outcome: StallOutcome
    /// How many rounds of recovery were tried. Zero while the app only observes.
    let cycles: Int

    /// An outage that was still open when the app stopped, reported at the next launch as `unfinished`.
    static func unfinished(_ open: OpenOutage) -> PlaybackStall {
        PlaybackStall(
            reason: open.reason, took: OutageDuration(seconds: open.lastSeenAt - open.startedAt), ahead: open.ahead, network: open.network,
            route: open.route, outcome: .unfinished, cycles: 0)
    }
}

/// What the player and the network say at one moment, as the observer needs it.
struct StallSample: Sendable, Equatable {
    /// The player's clock is moving: audio is being heard.
    var isPlaying: Bool
    /// The player is waiting to play (its time control status says so).
    var isWaiting: Bool
    /// The current item has failed.
    var itemFailed: Bool
    /// The listener has paused, as against the system or a stall having stopped the clock.
    var listenerPaused: Bool
    /// A live start is being watched, which has its own report.
    var startInProgress: Bool
    /// Seconds of audio buffered ahead of the playhead, if known.
    var aheadSeconds: Double?
    var network: NetworkKind
    var route: OutputRoute
}

/// A stall that has begun and not ended, described so it can be written down in case the app stops first.
struct OpenOutage: Sendable, Equatable, Codable {
    /// When it began, in seconds since 1970 (so it can be read at a later launch).
    var startedAt: TimeInterval
    /// The last moment the app saw it still going.
    var lastSeenAt: TimeInterval
    var reason: StallReason
    var ahead: AheadBucket
    var network: NetworkKind
    var route: OutputRoute
}

/// Decides, from a stream of samples, when a stall began and ended.
///
/// It only observes: it never acts. A stall is the player waiting after audio has played, while the listener wants it and no live start is being
/// watched, for longer than a second (a seek or a chunk boundary costs about that). It reports once, when the stall ends: audio moving again
/// (`resumed`) or the listener pausing (`listenerPaused`). The reason and the buffered-ahead are taken as the stall began; the reason becomes
/// `itemFailed` if the item fails while it lasts.
struct StallObserver: Sendable {
    /// A wait must last longer than this, in seconds, to count as a stall: a seek or a chunk boundary costs about that, and sampled every second a
    /// single sample of waiting cannot be told from one.
    static let minimumSeconds: TimeInterval = 1

    /// The stall in progress, if one is.
    private(set) var openOutage: OpenOutage?
    private var hasPlayed: Bool

    /// - Parameter hasPlayed: Whether audio has already played, so that waiting counts as a stall. A runner started for a stall passes `true`.
    init(hasPlayed: Bool = false) {
        self.hasPlayed = hasPlayed
    }

    /// - Parameters:
    ///   - sample: What the player and the network say now.
    ///   - at: The time, in seconds since 1970 (any consistent clock, in tests).
    /// - Returns: The stall that just ended, or `nil`.
    mutating func observe(_ sample: StallSample, at time: TimeInterval) -> PlaybackStall? {
        if sample.isPlaying { hasPlayed = true }
        if sample.startInProgress {
            openOutage = nil
            return nil
        }
        if sample.listenerPaused { return close(.listenerPaused, at: time) }
        if sample.isPlaying { return close(.resumed, at: time) }
        guard sample.isWaiting, hasPlayed else {
            // Neither moving nor waiting nor paused by the listener: the system stopped it. Not a stall, so nothing is said.
            openOutage = nil
            return nil
        }
        if var open = openOutage {
            open.lastSeenAt = time
            if sample.itemFailed { open.reason = .itemFailed }
            openOutage = open
        } else {
            openOutage = OpenOutage(
                startedAt: time, lastSeenAt: time,
                reason: sample.itemFailed ? .itemFailed : (sample.network == .none ? .networkLost : .bufferEmpty),
                ahead: AheadBucket(seconds: sample.aheadSeconds), network: sample.network, route: sample.route)
        }
        return nil
    }

    private mutating func close(_ outcome: StallOutcome, at time: TimeInterval) -> PlaybackStall? {
        guard let open = openOutage else { return nil }
        openOutage = nil
        let seconds = time - open.startedAt
        guard seconds > Self.minimumSeconds else { return nil }
        return PlaybackStall(
            reason: open.reason, took: OutageDuration(seconds: seconds), ahead: open.ahead, network: open.network, route: open.route,
            outcome: outcome, cycles: 0)
    }
}

/// Keeps the stall in progress in one small file, so that if the app is stopped before it ends it is reported at the next launch as `unfinished`.
/// Without this an outage that ends the app (a dead zone that outlasts the process) would never be counted, and every estimate of how long
/// outages last would lean short.
struct OutageMarker: Sendable {
    private let file: URL

    /// - Parameter directory: Where the file lives; made when it is first written.
    init(directory: URL) {
        file = directory.appendingPathComponent("outage-marker.json")
    }

    /// The app's marker, beside its other diagnostics.
    static let app = OutageMarker(
        directory: URL.applicationSupportDirectory.appendingPathComponent("Diagnostics", isDirectory: true))

    /// Writes the stall in progress, replacing an earlier marker.
    func write(_ open: OpenOutage) {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(open).write(to: file, options: .atomic)
        } catch {
            DiagnosticLog.app.record("Field", "could not write the outage marker: \(error.localizedDescription)")
        }
    }

    /// Removes the marker: the stall ended, or was reported.
    func clear() {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            try FileManager.default.removeItem(at: file)
        } catch {
            DiagnosticLog.app.record("Field", "could not remove the outage marker: \(error.localizedDescription)")
        }
    }

    /// The marker left by an earlier run, once: it is removed as it is read. A file that is not a marker is removed and ignored.
    func takeUnfinished() -> OpenOutage? {
        guard let data = FileManager.default.contents(atPath: file.path) else { return nil }
        defer { clear() }
        do {
            return try JSONDecoder().decode(OpenOutage.self, from: data)
        } catch {
            DiagnosticLog.app.record("Field", "the outage marker was not readable and was removed")
            return nil
        }
    }
}
