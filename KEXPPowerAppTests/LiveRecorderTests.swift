import Foundation
import os
import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("ReconnectBackoff")
struct ReconnectBackoffTests {
    private func near(_ value: TimeInterval, _ expected: TimeInterval) -> Bool { abs(value - expected) < 1e-9 }

    @Test("The wait doubles with each failed attempt, from one second")
    func doubles() {
        let backoff = ReconnectBackoff()
        #expect(near(backoff.delay(afterFailures: 1), 1))
        #expect(near(backoff.delay(afterFailures: 2), 2))
        #expect(near(backoff.delay(afterFailures: 3), 4))
    }

    @Test("The wait stops growing at the ceiling, however many attempts have failed")
    func ceiling() {
        let backoff = ReconnectBackoff()
        #expect(near(backoff.delay(afterFailures: 6), 10))
        #expect(near(backoff.delay(afterFailures: 500), 10))
        #expect(near(backoff.delay(afterFailures: Int.max), 10))
    }

    @Test("No failures, or a nonsense count, waits the first interval")
    func floor() {
        let backoff = ReconnectBackoff()
        #expect(near(backoff.delay(afterFailures: 0), 1))
        #expect(near(backoff.delay(afterFailures: -3), 1))
    }
}

/// A source that plays a script: each connection yields its chunks and then fails or ends.
private final class ScriptedSource: LiveByteSource {
    struct Attempt {
        var chunks: [Data]
        var error: (any Error)?
    }
    struct Refused: Error {}

    private let script: OSAllocatedUnfairLock<[Attempt]>
    private let counter = OSAllocatedUnfairLock(initialState: 0)

    init(_ attempts: [Attempt]) { script = OSAllocatedUnfairLock(initialState: attempts) }

    var connections: Int { counter.withLock { $0 } }

    func chunks() -> AsyncThrowingStream<Data, any Error> {
        counter.withLock { $0 += 1 }
        let attempt = script.withLock { $0.isEmpty ? nil : $0.removeFirst() }
        return AsyncThrowingStream { continuation in
            guard let attempt else {
                // Out of script: hold the connection open until cancelled, as a quiet stream would.
                return
            }
            for chunk in attempt.chunks { continuation.yield(chunk) }
            continuation.finish(throwing: attempt.error)
        }
    }
}

@Suite("LiveRecorder")
struct LiveRecorderTests {
    private func frames(_ count: Int) -> Data { Data(ADTSFixture.frames(count)) }

    private func waitFor(_ condition: @Sendable () async -> Bool) async -> Bool {
        for _ in 0..<500 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    @Test("What the stream sends reaches the relay")
    func recordsStream() async {
        let relay = LiveRelay(windowDuration: 60, segmentDuration: 1)
        let source = ScriptedSource([.init(chunks: [frames(200)], error: nil)])
        let waits = OSAllocatedUnfairLock<[TimeInterval]>(initialState: [])
        let recorder = LiveRecorder(source: source, relay: relay, sleep: { seconds in waits.withLock { $0.append(seconds) } })
        await recorder.start()
        let recorded = await waitFor { await relay.bufferedDuration > 1 }
        await recorder.stop()
        #expect(recorded)
    }

    @Test("A dropped connection is retried after a wait, and the audio after it follows a marked gap")
    func reconnects() async {
        let relay = LiveRelay(windowDuration: 60, segmentDuration: 1)
        let source = ScriptedSource([
            .init(chunks: [frames(120)], error: ScriptedSource.Refused()),
            .init(chunks: [], error: ScriptedSource.Refused()),
            .init(chunks: [frames(120)], error: nil),
        ])
        let waits = OSAllocatedUnfairLock<[TimeInterval]>(initialState: [])
        let recorder = LiveRecorder(source: source, relay: relay, sleep: { seconds in waits.withLock { $0.append(seconds) } })
        await recorder.start()
        let reconnected = await waitFor { source.connections >= 4 }
        let playlist = String(decoding: await relay.response(forPath: "/live.m3u8").body, as: UTF8.self)
        await recorder.stop()
        #expect(reconnected)
        #expect(playlist.contains("#EXT-X-DISCONTINUITY\n"))
        // The first drop waited one second; a failure straight after, with nothing received, waited longer.
        let recorded = waits.withLock { $0 }
        #expect(recorded.first.map { abs($0 - 1) < 1e-9 } ?? false)
        #expect(recorded.count >= 2)
        #expect(recorded[1] > recorded[0])
    }

    @Test("Receiving audio starts the wait over, so a long listen does not retry slowly after one drop")
    func backoffResets() async {
        let relay = LiveRelay(windowDuration: 60, segmentDuration: 1)
        let source = ScriptedSource([
            .init(chunks: [], error: ScriptedSource.Refused()),
            .init(chunks: [], error: ScriptedSource.Refused()),
            .init(chunks: [frames(120)], error: ScriptedSource.Refused()),
        ])
        let waits = OSAllocatedUnfairLock<[TimeInterval]>(initialState: [])
        let recorder = LiveRecorder(source: source, relay: relay, sleep: { seconds in waits.withLock { $0.append(seconds) } })
        await recorder.start()
        _ = await waitFor { source.connections >= 4 }
        await recorder.stop()
        let recorded = waits.withLock { $0 }
        #expect(recorded.count >= 3)
        #expect(abs(recorded[2] - 1) < 1e-9)
    }

    @Test("Stopping ends the recording and clears what was kept")
    func stopClears() async {
        let relay = LiveRelay(windowDuration: 60, segmentDuration: 1)
        let source = ScriptedSource([.init(chunks: [frames(200)], error: nil)])
        let recorder = LiveRecorder(source: source, relay: relay, sleep: { _ in })
        await recorder.start()
        _ = await waitFor { await relay.bufferedDuration > 1 }
        await recorder.stop()
        #expect(await relay.bufferedDuration < 0.001)
    }
}
