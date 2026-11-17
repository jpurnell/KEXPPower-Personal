import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

/// The buckets a stall is reported in: edges at 120 s and 300 s so the lengths of a cushion are exact boundaries.
@Suite("Stall buckets")
struct StallBucketTests {
    @Test("An outage's length is reported in steps whose edges include the two cushion lengths, 120 and 300 seconds")
    func durations() {
        #expect(OutageDuration(seconds: 0.4) == .under2)
        #expect(OutageDuration(seconds: 2) == .from2to5)
        #expect(OutageDuration(seconds: 5) == .from5to15)
        #expect(OutageDuration(seconds: 15) == .from15to40)
        #expect(OutageDuration(seconds: 40) == .from40to120)
        #expect(OutageDuration(seconds: 119.9) == .from40to120)
        #expect(OutageDuration(seconds: 120) == .from120to300)
        #expect(OutageDuration(seconds: 299.9) == .from120to300)
        #expect(OutageDuration(seconds: 300) == .over300)
        #expect(OutageDuration(seconds: -5) == .under2)
        #expect(OutageDuration(seconds: .nan) == .under2)
        #expect(OutageDuration(seconds: .infinity) == .over300)
    }

    @Test("Audio buffered ahead of the playhead is reported in steps with the same edges, and none or unknown is none")
    func ahead() {
        #expect(AheadBucket(seconds: nil) == .none)
        #expect(AheadBucket(seconds: 0) == .none)
        #expect(AheadBucket(seconds: -3) == .none)
        #expect(AheadBucket(seconds: .nan) == .none)
        #expect(AheadBucket(seconds: 0.5) == .under30)
        #expect(AheadBucket(seconds: 30) == .from30to120)
        #expect(AheadBucket(seconds: 120) == .from120to300)
        #expect(AheadBucket(seconds: 300) == .over300)
        #expect(AheadBucket(seconds: 600) == .over300)
    }
}

/// Deciding from what the player says, second by second, when a stall began and ended, and what to say about it.
@Suite("StallObserver")
struct StallObserverTests {
    private func sample(
        playing: Bool = false, waiting: Bool = true, failed: Bool = false, paused: Bool = false, starting: Bool = false,
        ahead: Double? = 0, network: NetworkKind = .cellular, route: OutputRoute = .carPlay
    ) -> StallSample {
        StallSample(
            isPlaying: playing, isWaiting: waiting, itemFailed: failed, listenerPaused: paused, startInProgress: starting, aheadSeconds: ahead,
            network: network, route: route)
    }

    @Test("Playing, then waiting for ten seconds, then playing again is one stall of ten seconds that resumed, with what was buffered when it began")
    func resumes() {
        var observer = StallObserver()
        #expect(observer.observe(sample(playing: true, waiting: false), at: 0) == nil)
        #expect(observer.observe(sample(ahead: 45), at: 1) == nil)
        #expect(observer.observe(sample(ahead: 20), at: 5) == nil)
        let stall = observer.observe(sample(playing: true, waiting: false), at: 11)
        #expect(stall == PlaybackStall(reason: .bufferEmpty, took: .from5to15, ahead: .from30to120, network: .cellular, route: .carPlay, outcome: .resumed, cycles: 0))
    }

    @Test("A stall that began with no network is a lost network; one that began with the network up is an empty buffer; a failed item is a failed item")
    func reasons() {
        for (network, failed, expected) in [(NetworkKind.none, false, StallReason.networkLost), (.wifi, false, .bufferEmpty), (.wifi, true, .itemFailed)] {
            var observer = StallObserver()
            _ = observer.observe(sample(playing: true, waiting: false), at: 0)
            _ = observer.observe(sample(failed: failed, network: network), at: 1)
            let stall = observer.observe(sample(playing: true, waiting: false), at: 9)
            #expect(stall?.reason == expected, "\(network) \(failed)")
        }
    }

    @Test("A stall that turns into a failed item is reported as one, whatever it began as")
    func failureUpgrades() {
        var observer = StallObserver()
        _ = observer.observe(sample(playing: true, waiting: false), at: 0)
        _ = observer.observe(sample(network: .wifi), at: 1)
        _ = observer.observe(sample(failed: true, network: .wifi), at: 4)
        #expect(observer.observe(sample(playing: true, waiting: false), at: 9)?.reason == .itemFailed)
    }

    @Test("A second of waiting or less is not a stall: it is what a seek or a chunk boundary costs")
    func tooShort() {
        var observer = StallObserver()
        _ = observer.observe(sample(playing: true, waiting: false), at: 0)
        _ = observer.observe(sample(), at: 1)
        #expect(observer.observe(sample(playing: true, waiting: false), at: 1.6) == nil)
        #expect(observer.openOutage == nil)
    }

    @Test("Waiting before audio has ever played, or while a live start is being watched, is not a stall: the start has its own report")
    func notAStart() {
        var observer = StallObserver()
        #expect(observer.observe(sample(), at: 0) == nil)
        #expect(observer.observe(sample(), at: 20) == nil)
        #expect(observer.openOutage == nil)
        _ = observer.observe(sample(playing: true, waiting: false), at: 21)
        _ = observer.observe(sample(starting: true), at: 22)
        #expect(observer.observe(sample(playing: true, waiting: false, starting: true), at: 40) == nil)
        #expect(observer.openOutage == nil)
    }

    @Test("If the listener pauses during a stall it ends there, as listenerPaused, with the time up to the pause")
    func listenerPauses() {
        var observer = StallObserver()
        _ = observer.observe(sample(playing: true, waiting: false), at: 0)
        _ = observer.observe(sample(), at: 2)
        let stall = observer.observe(sample(waiting: false, paused: true), at: 30)
        #expect(stall == PlaybackStall(reason: .bufferEmpty, took: .from15to40, ahead: .none, network: .cellular, route: .carPlay, outcome: .listenerPaused, cycles: 0))
    }

    @Test("While a stall is open it is described, so it can be written down in case the app is stopped before it ends")
    func open() {
        var observer = StallObserver()
        _ = observer.observe(sample(playing: true, waiting: false), at: 100)
        _ = observer.observe(sample(ahead: 200, network: .none), at: 101)
        _ = observer.observe(sample(ahead: 190, network: .none), at: 107)
        let open = try? #require(observer.openOutage)
        #expect(open == OpenOutage(startedAt: 101, lastSeenAt: 107, reason: .networkLost, ahead: .from120to300, network: .none, route: .carPlay))
    }

    @Test("An outage the app did not see the end of is reported once, as unfinished, for as long as it was seen")
    func unfinished() {
        let open = OpenOutage(startedAt: 101, lastSeenAt: 341, reason: .networkLost, ahead: .none, network: .none, route: .carPlay)
        #expect(PlaybackStall.unfinished(open) == PlaybackStall(reason: .networkLost, took: .from120to300, ahead: .none, network: .none, route: .carPlay, outcome: .unfinished, cycles: 0))
    }

    @Test("A second stall after the first is its own, and the observer holds nothing between them")
    func twoStalls() {
        var observer = StallObserver()
        _ = observer.observe(sample(playing: true, waiting: false), at: 0)
        _ = observer.observe(sample(), at: 1)
        #expect(observer.observe(sample(playing: true, waiting: false), at: 4)?.took == .from2to5)
        _ = observer.observe(sample(), at: 10)
        #expect(observer.observe(sample(playing: true, waiting: false), at: 60)?.took == .from40to120)
    }
}

/// An outage that was still open when the app stopped is kept on disk, one small file, and reported at the next launch.
@Suite("OutageMarker")
struct OutageMarkerTests {
    private func folder() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("marker-\(UUID().uuidString)", isDirectory: true) }

    @Test("A marker written is read back once, and then it is gone")
    func roundTrip() throws {
        let marker = OutageMarker<OpenOutage>(directory: folder())
        let open = OpenOutage(startedAt: 10, lastSeenAt: 70, reason: .networkLost, ahead: .under30, network: .none, route: .carPlay)
        marker.write(open)
        #expect(marker.takeUnfinished() == open)
        #expect(marker.takeUnfinished() == nil)
    }

    @Test("Clearing removes it, and a marker that is not one is ignored and removed")
    func clearAndJunk() throws {
        let directory = folder()
        let marker = OutageMarker<OpenOutage>(directory: directory)
        marker.write(OpenOutage(startedAt: 1, lastSeenAt: 2, reason: .unknown, ahead: .none, network: .wifi, route: .speaker))
        marker.clear()
        #expect(marker.takeUnfinished() == nil)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("outage-marker.json"))
        #expect(marker.takeUnfinished() == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("outage-marker.json").path))
    }

    @Test("The marker holds codes and seconds and nothing else")
    func holdsNoNames() throws {
        let directory = folder()
        let marker = OutageMarker<OpenOutage>(directory: directory)
        marker.write(OpenOutage(startedAt: 10, lastSeenAt: 70, reason: .networkLost, ahead: .under30, network: .none, route: .carPlay))
        let text = String(decoding: try Data(contentsOf: directory.appendingPathComponent("outage-marker.json")), as: UTF8.self)
        for key in ["startedAt", "lastSeenAt", "reason", "ahead", "network", "route"] { #expect(text.contains(key), "\(key)") }
        #expect(text.count < 300)
    }
}
