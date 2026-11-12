import Foundation
import KEXPPower
import os
import StationKitAdapterKEXP
import SwiftDiagnosticsClient
import Testing
@testable import KEXPPowerExampleSwiftUI

/// What the app reports when a call to KEXP's API fails, and how often.
/// The package's coalescer asks for a key; Spinner's events name theirs, so the tests ask with the event.
private extension EventCoalescer {
    func allows(_ event: FieldEvent) -> Bool { allows(key: event.coalescingKey) }
}

@Suite("API failures")
struct APIFailureTests {
    // MARK: Classifying an error

    @Test("An HTTP error from the archive keeps its status")
    func badStatus() {
        let failure = APIFailure.classify(KEXPArchiveError.badStatus(522))
        #expect(failure == APIFailure(outcome: .badStatus, status: 522))
    }

    @Test("An HTTP error from the live poll keeps its status: the library reports it since 4.2")
    func liveBadStatus() {
        #expect(APIFailure.classify(KEXPNetworkError.badStatus(522)) == APIFailure(outcome: .badStatus, status: 522))
        #expect(APIFailure.classify(KEXPNetworkError.badStatus(404)) == APIFailure(outcome: .badStatus, status: 404))
    }

    @Test("A live status outside the range an HTTP error can have is reported without one")
    func liveStatusOutOfRange() {
        #expect(APIFailure.classify(KEXPNetworkError.badStatus(304)) == APIFailure(outcome: .badStatus, status: nil))
    }

    @Test("A status outside the range an HTTP error can have is reported without one")
    func statusOutOfRange() {
        #expect(APIFailure.classify(KEXPArchiveError.badStatus(99)) == APIFailure(outcome: .badStatus, status: nil))
        #expect(APIFailure.classify(KEXPArchiveError.badStatus(600)) == APIFailure(outcome: .badStatus, status: nil))
    }

    @Test("A body that is not what was asked for is a bad response: an error page that fails to decode")
    func badResponse() {
        let decoding = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "not JSON"))
        #expect(APIFailure.classify(decoding) == APIFailure(outcome: .badResponse, status: nil))
    }

    @Test("No connection and a lost connection are offline; a timeout is a timeout")
    func network() {
        #expect(APIFailure.classify(URLError(.notConnectedToInternet))?.outcome == .offline)
        #expect(APIFailure.classify(URLError(.networkConnectionLost))?.outcome == .offline)
        #expect(APIFailure.classify(URLError(.timedOut))?.outcome == .timeout)
    }

    @Test("Anything else is other")
    func other() {
        #expect(APIFailure.classify(URLError(.cannotFindHost))?.outcome == .other)
        #expect(APIFailure.classify(URLError(.badURL))?.outcome == .other)
    }

    @Test("A cancelled request is not a failure and is not reported")
    func cancelled() {
        #expect(APIFailure.classify(CancellationError()) == nil)
        #expect(APIFailure.classify(URLError(.cancelled)) == nil)
    }

    // MARK: The event

    @Test("The event carries the endpoint and outcome as codes, and the status as a number when it is known")
    func eventRecord() {
        let with = FieldEvent.apiFailed(.archive, APIFailure(outcome: .badStatus, status: 522)).record
        #expect(with.kind == "apiFailed")
        #expect(with.severity == .warning)
        #expect(with.fields == ["endpoint": .code("archive"), "outcome": .code("badStatus"), "status": .int(522)])
        let without = FieldEvent.apiFailed(.live, APIFailure(outcome: .offline, status: nil)).record
        #expect(without.fields == ["endpoint": .code("live"), "outcome": .code("offline")])
    }

    private func schema() throws -> AppSchema {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try JSONDecoder().decode(
            AppSchema.self, from: Data(contentsOf: root.appendingPathComponent("project/diagnostics/spinner-schema.json")))
    }

    @Test("Every endpoint and outcome the app can report passes the schema file, with and without a status")
    func everyFailurePassesTheSchema() throws {
        let validator = SchemaValidator(schema: try schema())
        var events: [EventRecord] = []
        for endpoint in APIEndpoint.allCases {
            for outcome in APIFailure.Outcome.allCases {
                events.append(FieldEvent.apiFailed(endpoint, APIFailure(outcome: outcome, status: nil)).record)
                events.append(FieldEvent.apiFailed(endpoint, APIFailure(outcome: outcome, status: 503)).record)
            }
        }
        let envelope = Envelope(
            app: "spinner", platform: .ios, appVersion: "3.5.1", build: "14", osVersion: "27.2", deviceClass: "iPhone",
            channel: .appStore, launchID: "L1", sentAt: Date(timeIntervalSince1970: 0), events: events)
        let result = validator.validate(envelope)
        #expect(result.rejected.isEmpty, "\(result.rejected)")
        #expect(result.accepted.count == events.count)
    }

    // MARK: Coalescing

    @Test("The same failure is allowed once, then not again until the window has passed")
    func coalescing() {
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_000))
        let coalescer = EventCoalescer(window: 600, now: { clock.now })
        let event = FieldEvent.apiFailed(.live, APIFailure(outcome: .badStatus, status: 522))
        #expect(coalescer.allows(event))
        #expect(!coalescer.allows(event))
        clock.advance(by: 599)
        #expect(!coalescer.allows(event))
        clock.advance(by: 2)
        #expect(coalescer.allows(event))
    }

    @Test("A different endpoint, outcome or status is a different failure")
    func distinctFailures() {
        let coalescer = EventCoalescer(window: 600, now: { Date(timeIntervalSince1970: 1_000) })
        #expect(coalescer.allows(.apiFailed(.live, APIFailure(outcome: .badStatus, status: 522))))
        #expect(coalescer.allows(.apiFailed(.archive, APIFailure(outcome: .badStatus, status: 522))))
        #expect(coalescer.allows(.apiFailed(.live, APIFailure(outcome: .badStatus, status: 503))))
        #expect(coalescer.allows(.apiFailed(.live, APIFailure(outcome: .offline, status: nil))))
    }

    @Test("Events that are not repeated failures are never held back")
    func otherEventsPass() {
        let coalescer = EventCoalescer(window: 600, now: { Date(timeIntervalSince1970: 1_000) })
        for _ in 0..<3 {
            #expect(coalescer.allows(.launch(previousRun: .quit)))
            #expect(coalescer.allows(.rewindUnavailable(.serverFailed)))
        }
    }

    @Test("A flood of one failure sends one event: sixty-nine polls during an outage")
    func outageSendsOne() async throws {
        let transport = RecordingTransport()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("api-\(UUID().uuidString)", isDirectory: true)
        let endpoint = try #require(URL(string: "https://diagnostics.example/v1/ingest"))
        let uploader = DiagnosticsUploader(
            endpoint: endpoint, appKey: "test-key-0123456789abcdef",
            identity: AppIdentity(app: "spinner", platform: .ios, appVersion: "3.5.1", build: "14", osVersion: "27.2", deviceClass: "iPhone"),
            channel: .appStore, queue: DiskQueue(directory: folder), transport: transport, enabled: { true })
        let diagnostics = FieldDiagnostics(uploader: uploader, coalescer: EventCoalescer(window: 600, now: { Date() }))
        for _ in 0..<69 {
            await diagnostics.send(.apiFailed(.live, APIFailure(outcome: .badResponse, status: nil)))
        }
        #expect(await transport.requests.count == 1)
    }
}

/// A clock a test moves, readable from a synchronous closure.
final class TestClock: Sendable {
    private let lock: OSAllocatedUnfairLock<Date>

    init(start: Date) { lock = OSAllocatedUnfairLock(initialState: start) }

    var now: Date { lock.withLock { $0 } }

    func advance(by seconds: TimeInterval) { lock.withLock { $0 = $0.addingTimeInterval(seconds) } }
}
