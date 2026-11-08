import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

/// A stream that sends a burst of audio at once and then stays open, as a quiet connection would.
private struct SteadySource: LiveByteSource {
    func chunks() -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(Data(ADTSFixture.frames(400)))
        }
    }
}

/// A stream that never sends anything.
private struct SilentSource: LiveByteSource {
    func chunks() -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream { _ in }
    }
}

@MainActor
@Suite("LiveTimeShift")
struct LiveTimeShiftTests {
    private func fetch(_ url: URL) async throws -> (Data, Int) {
        let (data, response) = try await URLSession(configuration: .ephemeral).data(from: url)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    @Test("Once audio has arrived, start gives the address of a playlist that has it")
    func startsWithAudio() async throws {
        let shift = LiveTimeShift(source: SteadySource(), window: 600, firstAudio: 3, timeout: 5)
        let url = try #require(await shift.start())
        let (playlist, status) = try await fetch(url)
        await shift.stop()
        #expect(status == 200)
        #expect(String(decoding: playlist, as: UTF8.self).hasPrefix("#EXTM3U"))
    }

    @Test("If no audio arrives in time, there is no address, so the player uses the direct stream")
    func timesOut() async {
        let shift = LiveTimeShift(source: SilentSource(), window: 600, firstAudio: 3, timeout: 0.3)
        let url = await shift.start()
        await shift.stop()
        #expect(url == nil)
    }

    @Test("Starting twice gives the same address and does not start a second recorder")
    func idempotent() async throws {
        let shift = LiveTimeShift(source: SteadySource(), window: 600, firstAudio: 3, timeout: 5)
        let first = await shift.start()
        let second = await shift.start()
        await shift.stop()
        #expect(first != nil)
        #expect(first == second)
    }

    @Test("After stop the address no longer answers, and start works again")
    func stopsAndRestarts() async throws {
        let shift = LiveTimeShift(source: SteadySource(), window: 600, firstAudio: 3, timeout: 5)
        let url = try #require(await shift.start())
        await shift.stop()
        try await Task.sleep(for: .milliseconds(200))
        await #expect(throws: (any Error).self) { _ = try await fetch(url) }
        let again = await shift.start()
        await shift.stop()
        #expect(again != nil)
    }
}
