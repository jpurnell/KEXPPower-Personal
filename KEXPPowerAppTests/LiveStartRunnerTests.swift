import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

/// A player and a local server that say what a test scripts, with a clock that moves half a second per sleep and no waiting.
@MainActor
private final class ScriptedHost: LiveStartHost {
    var clock = Date(timeIntervalSince1970: 1_000_000)
    var ticks = 0
    /// What the host says at each tick (1-based); the last entry repeats. `nil` means the watched item is no longer the player's.
    var script: [LiveStartSnapshot?] = []
    var rebuildResult = true
    var directResult = true
    private(set) var rebuilds: [Int] = []
    private(set) var directs: [Int] = []
    private(set) var lines: [String] = []

    func sleep(milliseconds: Int) async {
        ticks += 1
        clock = clock.addingTimeInterval(Double(milliseconds) / 1_000)
    }
    func now() -> Date { clock }
    func snapshot() -> LiveStartSnapshot? {
        guard !script.isEmpty else { return LiveStartSnapshot.silent }
        return script[min(ticks, script.count) - 1]
    }
    func rebuild() async -> Bool { rebuilds.append(ticks); return rebuildResult }
    func playDirectly() async -> Bool { directs.append(ticks); return directResult }
    func record(_ line: String) { lines.append(line) }
}

private extension LiveStartSnapshot {
    static let silent = LiveStartSnapshot(
        audioMoving: false, evidence: LiveStartEvidence(playlistFetches: nil, segmentFetches: nil, itemFailed: false),
        controlStatus: 1, itemStatus: 0, waitingReason: "none")
    static let moving = LiveStartSnapshot(
        audioMoving: true, evidence: LiveStartEvidence(playlistFetches: 1, segmentFetches: 3, itemFailed: false),
        controlStatus: 2, itemStatus: 1, waitingReason: "none")
    static func silent(playlists: Int, segments: Int, failed: Bool = false) -> LiveStartSnapshot {
        LiveStartSnapshot(
            audioMoving: false, evidence: LiveStartEvidence(playlistFetches: playlists, segmentFetches: segments, itemFailed: failed),
            controlStatus: 1, itemStatus: failed ? 2 : 0, waitingReason: "none")
    }
}

/// The sequence of a live start: watched every half second, helped along by the evidence, and reported once.
@MainActor
@Suite("LiveStartRunner")
struct LiveStartRunnerTests {
    private struct Outcome { var reports: [LiveStart] = []; var started = 0; var gaveUp = 0 }

    private func run(host: ScriptedHost, recovering: Bool = false, network: NetworkKind = .cellular) async -> Outcome {
        var outcome = Outcome()
        let runner = LiveStartRunner(
            host: host, network: network, route: .carPlay, recovering: recovering,
            onStarted: { outcome.started += 1 }, onGaveUp: { outcome.gaveUp += 1 }, report: { outcome.reports.append($0) })
        await runner.run()
        return outcome
    }

    @Test("Audio at the third tick is a plain start, reported once, with how long it took")
    func plainStart() async {
        let host = ScriptedHost()
        host.script = [.silent, .silent, .moving]
        let outcome = await run(host: host)
        #expect(outcome.reports == [LiveStart(outcome: .started, took: .under2, network: .cellular, route: .carPlay)])
        #expect(outcome.started == 1)
        #expect(outcome.gaveUp == 0)
        #expect(host.rebuilds.isEmpty && host.directs.isEmpty)
    }

    @Test("With no evidence, silence rebuilds at eight seconds, plays directly at eighteen, and gives up at forty-five, reporting once")
    func fullSequence() async {
        let host = ScriptedHost()
        let outcome = await run(host: host)
        #expect(host.rebuilds == [16])
        #expect(host.directs == [36])
        #expect(outcome.gaveUp == 1)
        #expect(outcome.started == 0)
        #expect(outcome.reports == [LiveStart(outcome: .gaveUp, took: .over40, network: .cellular, route: .carPlay)])
    }

    @Test("A player that never reached the local server is rebuilt, and the journal says why and what the counts were")
    func neverConnectedIsJournaled() async {
        let host = ScriptedHost()
        host.script = [.silent(playlists: 0, segments: 0)]
        _ = await run(host: host)
        #expect(host.rebuilds == [16])
        #expect(host.lines.contains { $0.contains("rebuilding the item") && $0.contains("player never connected") })
        #expect(host.lines.contains { $0.contains("playlist fetches 0") && $0.contains("segment fetches 0") })
    }

    @Test("Segments flowing means no rebuild; the direct stream comes at eighteen seconds")
    func flowingIsNotRebuilt() async {
        let host = ScriptedHost()
        host.script = [.silent(playlists: 3, segments: 9)]
        _ = await run(host: host)
        #expect(host.rebuilds.isEmpty)
        #expect(host.directs == [36])
    }

    @Test("A failed item is rebuilt at the first look")
    func failedIsImmediate() async {
        let host = ScriptedHost()
        host.script = [.silent(playlists: 1, segments: 1, failed: true), .moving]
        let outcome = await run(host: host)
        #expect(host.rebuilds == [1])
        #expect(outcome.reports.map(\.outcome) == [.rebuilt])
    }

    @Test("A rebuild that could not be done is not retried, and the sequence goes on to the direct stream")
    func failedRebuildMovesOn() async {
        let host = ScriptedHost()
        host.rebuildResult = false
        _ = await run(host: host)
        #expect(host.rebuilds == [16])
        #expect(host.directs == [36])
    }

    @Test("A start that follows the network coming back is reported as recovered on the network")
    func recovered() async {
        let host = ScriptedHost()
        host.script = [.silent, .moving]
        let outcome = await run(host: host, recovering: true)
        #expect(outcome.reports.map(\.outcome) == [.recoveredOnNetwork])
    }

    @Test("When the item being watched is no longer the player's, the watch ends without a report")
    func itemReplaced() async {
        let host = ScriptedHost()
        host.script = [.silent, nil]
        let outcome = await run(host: host)
        #expect(outcome.reports.isEmpty)
        #expect(outcome.started == 0 && outcome.gaveUp == 0)
    }

    @Test("A cancelled watch ends without a report")
    func cancelled() async {
        let host = ScriptedHost()
        host.script = [.silent]
        var reports: [LiveStart] = []
        let runner = LiveStartRunner(
            host: host, network: .wifi, route: .speaker, recovering: false, onStarted: {}, onGaveUp: {}, report: { reports.append($0) })
        let task = Task { await runner.run() }
        task.cancel()
        await task.value
        #expect(reports.isEmpty)
    }

    @Test("The environment the start runs in (app state, route, what the item's own logs say) is written once at the first look and with every two-second line")
    func environmentIsJournaled() async {
        let host = ScriptedHost()
        host.script = [LiveStartSnapshot(
            audioMoving: false, evidence: LiveStartEvidence(playlistFetches: 2, segmentFetches: 0, itemFailed: false, segmentMisses: 0),
            controlStatus: 1, itemStatus: 0, waitingReason: "none", environment: "app active, outputs CarAudio, external false")]
        _ = await run(host: host)
        let first = host.lines.first { $0.contains("environment") }
        #expect(first == "live start: environment app active, outputs CarAudio, external false")
        #expect(host.lines.filter { $0.contains("playlist fetches") }.allSatisfy { $0.hasSuffix("app active, outputs CarAudio, external false") })
    }

    @Test("With no environment to report, the lines are as before")
    func noEnvironment() async {
        let host = ScriptedHost()
        host.script = [.silent(playlists: 1, segments: 0)]
        _ = await run(host: host)
        #expect(!host.lines.contains { $0.contains("environment") })
    }

    @Test("The journal gets the player's state and the server's counts every two seconds while a start is slow")
    func evidenceEveryTwoSeconds() async {
        let host = ScriptedHost()
        host.script = [.silent(playlists: 2, segments: 0)]
        _ = await run(host: host)
        let evidenceLines = host.lines.filter { $0.contains("playlist fetches") }
        #expect(evidenceLines.count >= 20)
        #expect(evidenceLines.first?.contains("network cellular") == true)
    }
}
