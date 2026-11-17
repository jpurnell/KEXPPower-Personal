//
//  LiveStartRunner.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// What the player and the local server say at one moment of a live start.
struct LiveStartSnapshot: Sendable, Equatable {
    /// Whether the player's clock is moving, which is when audio is heard.
    var audioMoving: Bool
    var evidence: LiveStartEvidence
    /// The player's `timeControlStatus` and the item's `status`, as raw values, for the journal.
    var controlStatus: Int
    var itemStatus: Int
    /// The player's reason for waiting, or `none`.
    var waitingReason: String
}

/// What a live start is watched through: the player, the local server and the clock. The app's player is one; a test scripts another.
@MainActor
protocol LiveStartHost: AnyObject {
    /// Waits.
    func sleep(milliseconds: Int) async
    func now() -> Date
    /// What the player and server say now, or `nil` if the item being watched is no longer the player's.
    func snapshot() -> LiveStartSnapshot?
    /// Gives the player a fresh item; `false` if that could not be done. The host watches the new item from then on.
    func rebuild() async -> Bool
    /// Drops the recording and plays the stream itself; `false` if that could not be done.
    func playDirectly() async -> Bool
    /// Writes a line to the app's own journal.
    func record(_ line: String)
}

/// A host made of closures, so the player can supply what it has without a type of its own.
@MainActor
final class ClosureLiveStartHost: LiveStartHost {
    private let snapshotWith: @MainActor () -> LiveStartSnapshot?
    private let rebuildWith: @MainActor () async -> Bool
    private let directWith: @MainActor () async -> Bool
    private let recordWith: @MainActor (String) -> Void
    private let sleepWith: @Sendable (Int) async -> Void
    private let nowWith: @Sendable () -> Date

    init(
        snapshot: @escaping @MainActor () -> LiveStartSnapshot?, rebuild: @escaping @MainActor () async -> Bool,
        playDirectly: @escaping @MainActor () async -> Bool, record: @escaping @MainActor (String) -> Void,
        sleep: @escaping @Sendable (Int) async -> Void = { milliseconds in try? await Task.sleep(for: .milliseconds(milliseconds)) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        snapshotWith = snapshot
        rebuildWith = rebuild
        directWith = playDirectly
        recordWith = record
        sleepWith = sleep
        nowWith = now
    }

    func sleep(milliseconds: Int) async { await sleepWith(milliseconds) }
    func now() -> Date { nowWith() }
    func snapshot() -> LiveStartSnapshot? { snapshotWith() }
    func rebuild() async -> Bool { await rebuildWith() }
    func playDirectly() async -> Bool { await directWith() }
    func record(_ line: String) { recordWith(line) }
}

/// Watches one live start from request to audio, a half second at a time, helps it along as `LiveStartWatch` decides, and reports how it ended.
@MainActor
final class LiveStartRunner {
    /// A minute of half-second looks: more than the watch can use, since it gives up at forty-five seconds.
    private static let maximumLooks = 120
    private static let lookInterval = 500
    /// How often, in looks, the journal gets the player's and the server's state: every two seconds.
    private static let journalEvery = 4

    private let host: any LiveStartHost
    private let network: NetworkKind
    private let route: OutputRoute
    private let recovering: Bool
    private let onStarted: @MainActor () -> Void
    private let onGaveUp: @MainActor () -> Void
    private let report: @MainActor (LiveStart) -> Void

    /// - Parameters:
    ///   - host: The player and server, or a script.
    ///   - network: How the phone was connected when live was asked for.
    ///   - route: Where the sound is going.
    ///   - recovering: Whether this start is the retry after the network came back.
    ///   - onStarted: Called once when audio begins.
    ///   - onGaveUp: Called once if the watch gives up.
    ///   - report: Called once with how the start ended; not called if the watch is cancelled or the item is replaced.
    init(
        host: any LiveStartHost, network: NetworkKind, route: OutputRoute, recovering: Bool,
        onStarted: @escaping @MainActor () -> Void, onGaveUp: @escaping @MainActor () -> Void, report: @escaping @MainActor (LiveStart) -> Void
    ) {
        self.host = host
        self.network = network
        self.route = route
        self.recovering = recovering
        self.onStarted = onStarted
        self.onGaveUp = onGaveUp
        self.report = report
    }

    func run() async {
        let requested = host.now()
        host.record("live start: requested\(recovering ? " (network is back)" : "")")
        var watch = LiveStartWatch()
        for look in 1...Self.maximumLooks {
            await host.sleep(milliseconds: Self.lookInterval)
            guard !Task.isCancelled, let snapshot = host.snapshot() else { return }
            let elapsed = host.now().timeIntervalSince(requested)
            let seconds = elapsed.formatted(.number.precision(.fractionLength(1)))
            switch watch.observe(elapsed: elapsed, audioMoving: snapshot.audioMoving, evidence: snapshot.evidence) {
            case .started:
                host.record("live start: audio moving after \(seconds) s")
                let outcome = recovering && watch.outcome == .started ? LiveStartOutcome.recoveredOnNetwork : watch.outcome
                onStarted()
                report(LiveStart(outcome: outcome, took: StartDuration(seconds: elapsed), network: network, route: route))
                return
            case .rebuild(let reason):
                host.record("live start: no audio after \(seconds) s; rebuilding the item (\(reason.rawValue))")
                _ = await host.rebuild()
            case .fallBackDirect:
                host.record("live start: no audio after \(seconds) s; playing the stream directly")
                _ = await host.playDirectly()
            case .giveUp:
                host.record("live start: gave up after \(seconds) s")
                onGaveUp()
                report(LiveStart(outcome: .gaveUp, took: StartDuration(seconds: elapsed), network: network, route: route))
                return
            case .waiting:
                if look % Self.journalEvery == 0 { host.record(Self.state(snapshot, seconds: seconds, network: network)) }
            }
        }
    }

    private static func state(_ snapshot: LiveStartSnapshot, seconds: String, network: NetworkKind) -> String {
        let playlists = snapshot.evidence.playlistFetches.map(String.init) ?? "n/a"
        let segments = snapshot.evidence.segmentFetches.map(String.init) ?? "n/a"
        let misses = snapshot.evidence.segmentMisses.map(String.init) ?? "n/a"
        return "live start: \(seconds) s, control \(snapshot.controlStatus), item \(snapshot.itemStatus), waiting \(snapshot.waitingReason), "
            + "network \(network.rawValue), playlist fetches \(playlists), segment fetches \(segments), segment misses \(misses)"
    }
}
