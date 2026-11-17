import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

/// What to do about a live start that is taking too long, decided from nothing but the seconds elapsed and whether audio is moving.
@Suite("LiveStartWatch")
struct LiveStartWatchTests {
    @Test("Audio moving ends the watch at once, and the outcome is a plain start")
    func startsCleanly() {
        var watch = LiveStartWatch()
        #expect(watch.observe(elapsed: 0.5, audioMoving: true) == .started)
        #expect(watch.outcome == .started)
    }

    @Test("Nothing happens while a start is still within what a bad connection allows")
    func waitsPatiently() {
        var watch = LiveStartWatch()
        for seconds in stride(from: 0.5, through: 7.5, by: 0.5) {
            #expect(watch.observe(elapsed: seconds, audioMoving: false) == .waiting)
        }
    }

    @Test("Silence for eight seconds rebuilds the item, once")
    func rebuildsOnce() {
        var watch = LiveStartWatch()
        #expect(watch.observe(elapsed: 8, audioMoving: false) == .rebuild(.noEvidence))
        #expect(watch.observe(elapsed: 8.5, audioMoving: false) == .waiting)
        #expect(watch.observe(elapsed: 12, audioMoving: false) == .waiting)
    }

    // MARK: Evidence from the local server and the item

    @Test("A player that never asked the local server for the playlist is rebuilt at eight seconds, and the reason says so")
    func neverConnected() {
        var watch = LiveStartWatch()
        let evidence = LiveStartEvidence(playlistFetches: 0, segmentFetches: 0, itemFailed: false)
        #expect(watch.observe(elapsed: 7.5, audioMoving: false, evidence: evidence) == .waiting)
        #expect(watch.observe(elapsed: 8, audioMoving: false, evidence: evidence) == .rebuild(.playerNeverConnected))
    }

    @Test("A player that fetched the playlist but no segment is rebuilt at eight seconds")
    func noSegments() {
        var watch = LiveStartWatch()
        let evidence = LiveStartEvidence(playlistFetches: 2, segmentFetches: 0, itemFailed: false)
        #expect(watch.observe(elapsed: 8, audioMoving: false, evidence: evidence) == .rebuild(.noSegmentsFetched))
    }

    @Test("Segments arriving means a rebuild would not help: it is not done, and the fall-back to the direct stream still comes at eighteen")
    func dataFlowing() {
        var watch = LiveStartWatch()
        let evidence = LiveStartEvidence(playlistFetches: 3, segmentFetches: 5, itemFailed: false)
        #expect(watch.observe(elapsed: 8, audioMoving: false, evidence: evidence) == .waiting)
        #expect(watch.observe(elapsed: 12, audioMoving: false, evidence: evidence) == .waiting)
        #expect(watch.observe(elapsed: 18, audioMoving: false, evidence: evidence) == .fallBackDirect)
    }

    @Test("An item that has failed is rebuilt at once, not after eight seconds")
    func failedItem() {
        var watch = LiveStartWatch()
        let evidence = LiveStartEvidence(playlistFetches: 1, segmentFetches: 1, itemFailed: true)
        #expect(watch.observe(elapsed: 0.5, audioMoving: false, evidence: evidence) == .rebuild(.itemFailed))
        #expect(watch.observe(elapsed: 1, audioMoving: false, evidence: evidence) == .waiting)
    }

    @Test("With no local server to ask (the direct stream), there is no evidence and the rebuild is by the clock, as before")
    func noEvidenceDirect() {
        var watch = LiveStartWatch()
        let evidence = LiveStartEvidence(playlistFetches: nil, segmentFetches: nil, itemFailed: false)
        #expect(watch.observe(elapsed: 8, audioMoving: false, evidence: evidence) == .rebuild(.noEvidence))
    }

    @Test("Still silent eighteen seconds in, it falls back to the stream played directly, once")
    func fallsBackOnce() {
        var watch = LiveStartWatch()
        _ = watch.observe(elapsed: 8, audioMoving: false)
        #expect(watch.observe(elapsed: 18, audioMoving: false) == .fallBackDirect)
        #expect(watch.observe(elapsed: 19, audioMoving: false) == .waiting)
    }

    @Test("Forty-five seconds with no audio is the end of the watch")
    func givesUp() {
        var watch = LiveStartWatch()
        _ = watch.observe(elapsed: 8, audioMoving: false)
        _ = watch.observe(elapsed: 18, audioMoving: false)
        #expect(watch.observe(elapsed: 45, audioMoving: false) == .giveUp)
        #expect(watch.outcome == .gaveUp)
    }

    @Test("A coarse sample can skip a moment, and the later step is still taken")
    func skippedMoments() {
        var watch = LiveStartWatch()
        #expect(watch.observe(elapsed: 19, audioMoving: false) == .fallBackDirect)
    }

    @Test("The outcome says how far recovery went before audio came")
    func outcomeTracksRecovery() {
        var rebuilt = LiveStartWatch()
        _ = rebuilt.observe(elapsed: 8, audioMoving: false)
        _ = rebuilt.observe(elapsed: 10, audioMoving: true)
        #expect(rebuilt.outcome == .rebuilt)

        var direct = LiveStartWatch()
        _ = direct.observe(elapsed: 8, audioMoving: false)
        _ = direct.observe(elapsed: 18, audioMoving: false)
        _ = direct.observe(elapsed: 20, audioMoving: true)
        #expect(direct.outcome == .fellBackDirect)
    }

    @Test("Durations are reported in coarse steps, so a report says slow or fast and not exactly how long")
    func durationBuckets() {
        #expect(StartDuration(seconds: 0.4) == .under2)
        #expect(StartDuration(seconds: 2) == .from2to5)
        #expect(StartDuration(seconds: 4.9) == .from2to5)
        #expect(StartDuration(seconds: 5) == .from5to15)
        #expect(StartDuration(seconds: 15) == .from15to40)
        #expect(StartDuration(seconds: 40) == .over40)
        #expect(StartDuration(seconds: -3) == .under2)
        #expect(StartDuration(seconds: .nan) == .under2)
    }
}

/// Where the sound is going and how the phone is connected, as the few codes a report may carry.
@Suite("LiveStartContext")
struct LiveStartContextTests {
    @Test("An output port becomes a route code, and a port it does not know is `other`, never its name")
    func routes() {
        #expect(OutputRoute(portType: "CarAudio") == .carPlay)
        #expect(OutputRoute(portType: "AirPlay") == .airPlay)
        #expect(OutputRoute(portType: "BluetoothA2DPOutput") == .bluetooth)
        #expect(OutputRoute(portType: "BluetoothHFP") == .bluetooth)
        #expect(OutputRoute(portType: "Headphones") == .headphones)
        #expect(OutputRoute(portType: "Speaker") == .speaker)
        #expect(OutputRoute(portType: "Receiver") == .speaker)
        #expect(OutputRoute(portType: "Justin's HomePod") == .other)
        #expect(OutputRoute(portType: nil) == .other)
    }

    @Test("A network path becomes none, wifi, cellular, wired or other")
    func networks() {
        #expect(NetworkKind(isSatisfied: false, usesWiFi: true, usesCellular: false, usesWired: false) == .none)
        #expect(NetworkKind(isSatisfied: true, usesWiFi: true, usesCellular: false, usesWired: false) == .wifi)
        #expect(NetworkKind(isSatisfied: true, usesWiFi: false, usesCellular: true, usesWired: false) == .cellular)
        #expect(NetworkKind(isSatisfied: true, usesWiFi: false, usesCellular: false, usesWired: true) == .wired)
        #expect(NetworkKind(isSatisfied: true, usesWiFi: false, usesCellular: false, usesWired: false) == .other)
    }
}

/// When a start that gave up should be tried again: when the network comes back.
@Suite("NetworkRecovery")
struct NetworkRecoveryTests {
    @Test("A start that gave up is tried again when the network returns, once")
    func retriesOnReturn() {
        var recovery = NetworkRecovery()
        #expect(recovery.shouldRetry(network: .none, waiting: true) == false)
        #expect(recovery.shouldRetry(network: .cellular, waiting: true) == true)
        #expect(recovery.shouldRetry(network: .cellular, waiting: true) == false)
    }

    @Test("Nothing is retried when no one is waiting for audio")
    func notWaiting() {
        var recovery = NetworkRecovery()
        _ = recovery.shouldRetry(network: .none, waiting: false)
        #expect(recovery.shouldRetry(network: .wifi, waiting: false) == false)
    }

    @Test("Moving from one working network to another is not a return")
    func wifiToCellular() {
        var recovery = NetworkRecovery()
        _ = recovery.shouldRetry(network: .wifi, waiting: true)
        #expect(recovery.shouldRetry(network: .cellular, waiting: true) == false)
    }

    @Test("A start that gave up before the first path report is retried when the first usable path arrives")
    func firstReport() {
        var recovery = NetworkRecovery()
        #expect(recovery.shouldRetry(network: .wifi, waiting: true) == true)
    }
}
