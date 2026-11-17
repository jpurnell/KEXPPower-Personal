//
//  StallRunner.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// Watches one stall from its first second to its end: asks the player a question every second, writes the stall to the marker while it lasts, and
/// reports it once when it ends.
///
/// It only observes. The player, the clock and the waiting come from outside, so the sequence is tested with a script and no player.
@MainActor
final class StallRunner {
    /// How long to ask: two hours of seconds. A stall that outlasts it keeps its marker and is reported at the next launch.
    static let defaultLooks = 7_200
    /// A stall is written down once it has lasted this long, in seconds, and again every ``markerEvery``.
    static let markerAfter: TimeInterval = 5
    static let markerEvery: TimeInterval = 10

    private let sample: @MainActor () -> StallSample?
    private let sleep: @MainActor (Int) async -> Void
    private let now: @MainActor () -> TimeInterval
    private let record: @MainActor (String) -> Void
    private let report: @MainActor (PlaybackStall) -> Void
    private let marker: OutageMarker<OpenOutage>
    private let onBegan: @MainActor () -> Void
    private let maxLooks: Int

    /// - Parameters:
    ///   - sample: What the player and the network say now, or `nil` if there is no player.
    ///   - sleep: Waits the given milliseconds.
    ///   - now: Seconds since 1970.
    ///   - record: Writes a line to the app's own journal.
    ///   - report: Called once with the stall when it ends.
    ///   - marker: Where the stall in progress is kept.
    ///   - onBegan: Called once when a stall begins, so an outage of the connection that is open can say it was heard.
    ///   - maxLooks: The most seconds to watch.
    init(
        sample: @escaping @MainActor () -> StallSample?, sleep: @escaping @MainActor (Int) async -> Void,
        now: @escaping @MainActor () -> TimeInterval, record: @escaping @MainActor (String) -> Void,
        report: @escaping @MainActor (PlaybackStall) -> Void, marker: OutageMarker<OpenOutage>, onBegan: @escaping @MainActor () -> Void = {},
        maxLooks: Int = StallRunner.defaultLooks
    ) {
        self.sample = sample
        self.sleep = sleep
        self.now = now
        self.record = record
        self.report = report
        self.marker = marker
        self.onBegan = onBegan
        self.maxLooks = maxLooks
    }

    func run() async {
        // Started because audio had played and the player is now waiting, so the observer begins knowing that.
        var observer = StallObserver(hasPlayed: true)
        var began = false
        var markerWrittenAt: TimeInterval = 0
        for _ in 0..<maxLooks {
            guard let current = sample() else {
                marker.clear()
                return
            }
            let time = now()
            if let stall = observer.observe(current, at: time) {
                record("stall: ended, \(stall.outcome.rawValue) after \(stall.took.rawValue)")
                report(stall)
                marker.clear()
                return
            }
            if let open = observer.openOutage {
                if !began {
                    began = true
                    record("stall: began, \(Self.words(open.reason)), ahead \(open.ahead.rawValue), network \(open.network.rawValue)")
                    onBegan()
                }
                if open.lastSeenAt - open.startedAt >= Self.markerAfter, time - markerWrittenAt >= Self.markerEvery {
                    marker.write(open)
                    markerWrittenAt = time
                }
            } else if !current.isWaiting {
                // Nothing in progress and nothing waiting: it was over before it counted.
                marker.clear()
                return
            }
            await sleep(1_000)
        }
    }

    private static func words(_ reason: StallReason) -> String {
        switch reason {
        case .networkLost: "network lost"
        case .bufferEmpty: "buffer empty"
        case .itemFailed: "item failed"
        case .localServer: "local server"
        case .unknown: "unknown"
        }
    }
}
