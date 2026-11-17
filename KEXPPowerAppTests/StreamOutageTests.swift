import Foundation
import os
import Testing
@testable import KEXPPowerExampleSwiftUI

/// The stream's connection going down and coming back, seen whether or not anyone heard it: the part of the outage that was audible is a stall,
/// and the rest, the part the buffer covered, is only seen here.
@Suite("StreamOutageObserver")
struct StreamOutageObserverTests {
    @Test("A connection lost for thirty-three seconds with seventeen buffered is one outage of that length, with what was buffered at the loss, and it was covered if no stall began")
    func covered() {
        var observer = StreamOutageObserver()
        observer.lost(at: 100, aheadSeconds: 17, network: .wifi, route: .speaker)
        observer.attempted()
        observer.attempted()
        let outage = observer.restored(at: 133)
        #expect(outage == StreamOutage(took: .from15to40, ahead: .under30, network: .wifi, route: .speaker, outcome: .covered, attempts: 2))
    }

    @Test("If a stall began while it lasted, it is reported as stalled")
    func stalled() {
        var observer = StreamOutageObserver()
        observer.lost(at: 0, aheadSeconds: 5, network: .cellular, route: .carPlay)
        observer.stallBegan()
        #expect(observer.restored(at: 45)?.outcome == .stalled)
    }

    @Test("What was buffered is as it was at the loss, not as it was later")
    func aheadAtTheLoss() {
        var observer = StreamOutageObserver()
        observer.lost(at: 0, aheadSeconds: 200, network: .wifi, route: .speaker)
        #expect(observer.restored(at: 150)?.ahead == .from120to300)
        #expect(observer.restored(at: 151) == nil)
    }

    @Test("A restore with no loss, and a second loss while one is open, are nothing: the first loss's start and buffer stand")
    func noise() {
        var observer = StreamOutageObserver()
        #expect(observer.restored(at: 5) == nil)
        observer.lost(at: 10, aheadSeconds: 40, network: .wifi, route: .speaker)
        observer.lost(at: 20, aheadSeconds: 0, network: .none, route: .other)
        let outage = observer.restored(at: 70)
        #expect(outage?.took == .from40to120)
        #expect(outage?.ahead == .from30to120)
        #expect(outage?.network == .wifi)
    }

    @Test("While an outage is open it is described, with the last time it was seen, so it can be written down in case the app stops first")
    func open() throws {
        var observer = StreamOutageObserver()
        observer.lost(at: 100, aheadSeconds: 20, network: .none, route: .carPlay)
        observer.attempted()
        observer.heard(at: 108)
        let open = try #require(observer.openOutage)
        #expect(open == OpenStreamOutage(startedAt: 100, lastSeenAt: 108, ahead: .under30, network: .none, route: .carPlay, attempts: 1, stalled: false))
    }

    @Test("An outage the app did not see the end of is reported once, as unfinished, for as long as it was seen")
    func unfinished() {
        let open = OpenStreamOutage(startedAt: 100, lastSeenAt: 460, ahead: .none, network: .none, route: .carPlay, attempts: 30, stalled: true)
        #expect(StreamOutage.unfinished(open) == StreamOutage(took: .over300, ahead: .none, network: .none, route: .carPlay, outcome: .unfinished, attempts: 30))
    }

    @Test("The attempts are bounded where the schema bounds them")
    func attemptsBounded() {
        var observer = StreamOutageObserver()
        observer.lost(at: 0, aheadSeconds: 0, network: .wifi, route: .speaker)
        for _ in 0..<80 { observer.attempted() }
        #expect(observer.restored(at: 10)?.attempts == StreamOutage.maximumAttempts)
        #expect(StreamOutage.maximumAttempts == 50)
    }
}

/// The recorder says when the stream's connection is lost, tried again, and back, and only once it has been up.
@Suite("LiveRecorder connection events")
struct RecorderConnectionEventTests {
    private struct Refused: Error {}

    private final class Source: LiveByteSource {
        struct Attempt {
            var chunks: [Data]
            var error: (any Error)?
        }
        private let script: OSAllocatedUnfairLock<[Attempt]>
        init(_ attempts: [Attempt]) { script = OSAllocatedUnfairLock(initialState: attempts) }

        func chunks() -> AsyncThrowingStream<Data, any Error> {
            let attempt = script.withLock { $0.isEmpty ? nil : $0.removeFirst() }
            return AsyncThrowingStream { continuation in
                guard let attempt else { return }
                for chunk in attempt.chunks { continuation.yield(chunk) }
                continuation.finish(throwing: attempt.error)
            }
        }
    }

    private func frames(_ count: Int) -> Data { Data(ADTSFixture.frames(count)) }

    private func collect(_ attempts: [Source.Attempt], until count: Int) async -> [RecorderEvent] {
        let events = OSAllocatedUnfairLock<[RecorderEvent]>(initialState: [])
        let recorder = LiveRecorder(
            source: Source(attempts), relay: LiveRelay(windowDuration: 60, segmentDuration: 1), sleep: { _ in },
            onEvent: { event in events.withLock { $0.append(event) } })
        await recorder.start()
        for _ in 0..<500 {
            if events.withLock({ $0.count }) >= count { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        await recorder.stop()
        return events.withLock { $0 }
    }

    @Test("A stream that was up, fails, and comes back is lost, then an attempt, then restored")
    func lostAttemptRestored() async {
        let events = await collect([
            .init(chunks: [frames(40)], error: Refused()),
            .init(chunks: [], error: Refused()),
            .init(chunks: [frames(40)], error: nil),
        ], until: 3)
        #expect(Array(events.prefix(4)) == [.lost, .attempting, .attempting, .restored])
    }

    @Test("A connection that never delivered anything is not a loss: a start with no coverage has its own report")
    func neverUp() async {
        let events = await collect([.init(chunks: [], error: Refused()), .init(chunks: [], error: Refused())], until: 1)
        #expect(!events.contains(.lost))
        #expect(!events.contains(.restored))
    }

    @Test("A stream that ends by itself while up is a loss too, and a second failure while down is not a second loss")
    func endsAndRepeats() async {
        let events = await collect([
            .init(chunks: [frames(40)], error: nil),
            .init(chunks: [], error: Refused()),
            .init(chunks: [], error: Refused()),
            .init(chunks: [frames(40)], error: nil),
        ], until: 5)
        #expect(events.filter { $0 == .lost }.count == 2)
        #expect(events.filter { $0 == .restored }.count == 1)
    }
}
