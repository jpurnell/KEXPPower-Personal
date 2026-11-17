import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

/// Watching one stall from its first second to its end: sampled every second, written down while it lasts, reported once.
@MainActor
@Suite("StallRunner")
struct StallRunnerTests {
    /// What the player says second by second, scripted; the last entry repeats. `nil` means there is no player to ask.
    @MainActor
    private final class Script {
        var samples: [StallSample?]
        var tick = 0
        var lines: [String] = []
        var reports: [PlaybackStall] = []
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("stallrunner-\(UUID().uuidString)", isDirectory: true)
        var marker: OutageMarker<OpenOutage> { OutageMarker<OpenOutage>(directory: directory) }

        init(_ samples: [StallSample?]) { self.samples = samples }

        func sample() -> StallSample? {
            samples[min(tick, samples.count - 1)]
        }

        func run(maxLooks: Int = 7_200) async {
            let runner = StallRunner(
                sample: { [unowned self] in self.sample() },
                sleep: { [unowned self] _ in self.tick += 1 },
                now: { [unowned self] in 1_000 + TimeInterval(self.tick) },
                record: { [unowned self] in self.lines.append($0) },
                report: { [unowned self] in self.reports.append($0) },
                marker: marker, maxLooks: maxLooks)
            await runner.run()
        }
    }

    private static let moving = StallSample(
        isPlaying: true, isWaiting: false, itemFailed: false, listenerPaused: false, startInProgress: false, aheadSeconds: nil, network: .cellular, route: .carPlay)
    private static func waiting(ahead: Double? = 0, network: NetworkKind = .cellular) -> StallSample {
        StallSample(
            isPlaying: false, isWaiting: true, itemFailed: false, listenerPaused: false, startInProgress: false, aheadSeconds: ahead, network: network, route: .carPlay)
    }
    private static let paused = StallSample(
        isPlaying: false, isWaiting: false, itemFailed: false, listenerPaused: true, startInProgress: false, aheadSeconds: nil, network: .cellular, route: .carPlay)

    @Test("A stall of eight seconds that resumes is reported once, with its length and what was buffered, and the journal says it began and ended")
    func resumes() async {
        let script = Script([Self.waiting(ahead: 45)] + Array(repeating: Self.waiting(ahead: 20), count: 7) + [Self.moving])
        await script.run()
        #expect(script.reports == [PlaybackStall(reason: .bufferEmpty, took: .from5to15, ahead: .from30to120, network: .cellular, route: .carPlay, outcome: .resumed, cycles: 0)])
        #expect(script.lines.first == "stall: began, buffer empty, ahead from30to120, network cellular")
        #expect(script.lines.last == "stall: ended, resumed after from5to15")
        script.marker.clear()
        #expect(script.marker.takeUnfinished() == nil)
    }

    @Test("While a stall lasts it is written to the marker once it has been going five seconds and then every ten, and the marker is gone when it ends")
    func marker() async throws {
        var samples: [StallSample?] = Array(repeating: Self.waiting(network: .none), count: 20)
        samples.append(Self.moving)
        let script = Script(samples)
        var seen: [OpenOutage] = []
        let runner = StallRunner(
            sample: { script.sample() },
            sleep: { _ in
                script.tick += 1
                if let open = script.marker.takeUnfinished() { seen.append(open); script.marker.write(open) }
            },
            now: { 1_000 + TimeInterval(script.tick) },
            record: { script.lines.append($0) }, report: { script.reports.append($0) }, marker: script.marker, maxLooks: 7_200)
        await runner.run()
        #expect(seen.first?.reason == .networkLost)
        #expect(seen.map(\.lastSeenAt).filter { $0 > 0 }.count >= 2)
        #expect(script.reports.count == 1)
        #expect(script.marker.takeUnfinished() == nil)
    }

    @Test("A single sample of waiting (about a second) is not a stall: nothing is reported, and no marker is left")
    func tooShort() async {
        let script = Script([Self.waiting(), Self.moving])
        await script.run()
        #expect(script.reports.isEmpty)
        #expect(script.marker.takeUnfinished() == nil)
    }

    @Test("A listener who pauses ends it there, as listenerPaused")
    func listenerPauses() async {
        let script = Script(Array(repeating: Self.waiting(), count: 12) + [Self.paused])
        await script.run()
        #expect(script.reports.map(\.outcome) == [.listenerPaused])
        #expect(script.reports.first?.took == .from5to15)
    }

    @Test("If there is no player to ask any more, the watch ends without a report and without leaving a marker")
    func noPlayer() async {
        let script = Script(Array(repeating: Self.waiting(), count: 8) + [nil])
        await script.run()
        #expect(script.reports.isEmpty)
        #expect(script.marker.takeUnfinished() == nil)
    }

    @Test("A stall that never ends is watched only up to the bound, leaves its marker for the next launch, and reports nothing now")
    func neverEnds() async throws {
        let script = Script([Self.waiting(network: .none)])
        await script.run(maxLooks: 30)
        #expect(script.reports.isEmpty)
        let left = try #require(script.marker.takeUnfinished())
        #expect(left.reason == .networkLost)
        #expect(left.lastSeenAt - left.startedAt >= 20)
    }

    @Test("The journal holds codes and seconds only")
    func journalHoldsCodes() async {
        let script = Script(Array(repeating: Self.waiting(network: .none), count: 6) + [Self.moving])
        await script.run()
        #expect(script.lines.count == 2)
        for line in script.lines { #expect(line.hasPrefix("stall: ")) }
    }
}
