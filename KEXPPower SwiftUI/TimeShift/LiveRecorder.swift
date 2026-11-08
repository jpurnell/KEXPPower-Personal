//
//  LiveRecorder.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// How long to wait before trying the stream again: one second after the first failure, doubling, up to ten.
struct ReconnectBackoff: Sendable {
    private static let first: TimeInterval = 1
    private static let ceiling: TimeInterval = 10
    private static let doublingsToCeiling = 4

    /// - Parameter failures: How many attempts in a row have failed; zero or less reads as one.
    func delay(afterFailures failures: Int) -> TimeInterval {
        guard failures > 1 else { return Self.first }
        guard failures <= Self.doublingsToCeiling else { return Self.ceiling }
        return min(Self.first * Double(1 << (failures - 1)), Self.ceiling)
    }
}

/// One connection to the live stream: its bytes as they arrive, ending when the connection does.
protocol LiveByteSource: Sendable {
    /// Opens a connection. The sequence finishes, or throws, when the connection ends.
    func chunks() -> AsyncThrowingStream<Data, any Error>
}

/// Reads the live stream from the network.
struct URLSessionByteSource: LiveByteSource {
    let url: URL

    private static let chunkSize = 4_096

    func chunks() -> AsyncThrowingStream<Data, any Error> {
        let url = url
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let configuration = URLSessionConfiguration.ephemeral
                    // A stalled connection is treated as dropped, so the recorder reconnects instead of waiting on it.
                    configuration.timeoutIntervalForRequest = 15
                    let (bytes, response) = try await URLSession(configuration: configuration).bytes(from: url)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    var chunk = Data()
                    for try await byte in bytes {
                        chunk.append(byte)
                        if chunk.count >= Self.chunkSize {
                            continuation.yield(chunk)
                            chunk.removeAll(keepingCapacity: true)
                        }
                    }
                    if !chunk.isEmpty { continuation.yield(chunk) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Keeps the last few minutes of the live stream by reading it continuously and handing it to a `LiveRelay`, and reads it
/// again, after a wait, whenever the connection drops.
actor LiveRecorder {
    private let source: any LiveByteSource
    private let relay: LiveRelay
    private let backoff = ReconnectBackoff()
    private let sleep: @Sendable (TimeInterval) async -> Void
    private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - source: Where the stream comes from.
    ///   - relay: Where it goes.
    ///   - sleep: Waits for a number of seconds; a test passes one that returns at once.
    init(
        source: any LiveByteSource, relay: LiveRelay,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(for: .seconds(seconds))
        }
    ) {
        self.source = source
        self.relay = relay
        self.sleep = sleep
    }

    /// Starts reading. Does nothing if it already is.
    func start() {
        guard task == nil else { return }
        let source = source
        let relay = relay
        let backoff = backoff
        let sleep = sleep
        task = Task {
            var failures = 0
            while !Task.isCancelled {
                var received = false
                do {
                    for try await chunk in source.chunks() {
                        received = true
                        await relay.ingest(chunk)
                    }
                } catch {
                    // The connection failed; handled the same as one that ended.
                }
                guard !Task.isCancelled else { break }
                await relay.streamBroke()
                // Audio since the last attempt means the stream was up, so the wait starts over.
                failures = received ? 1 : failures + 1
                await sleep(backoff.delay(afterFailures: failures))
            }
        }
    }

    /// Stops reading and forgets what was kept.
    func stop() async {
        task?.cancel()
        task = nil
        await relay.reset()
    }
}
