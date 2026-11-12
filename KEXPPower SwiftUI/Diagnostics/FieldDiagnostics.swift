//
//  FieldDiagnostics.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import SwiftDiagnosticsClient

/// Where the hub is and which app Spinner says it is.
///
/// The ingest key identifies the app to the hub and is meant to be extractable from a shipped build, so it is not a secret
/// the way a password is. It is still **not in the source**, because this repository is public: `Config/Secrets.xcconfig`
/// (untracked) sets `DIAGNOSTICS_INGEST_KEY`, the target's Info.plist carries it as `DiagnosticsIngestKey`, and the app reads
/// it from there. A build without that file has no key, and an app with no key sends nothing.
enum FieldDiagnosticsConfiguration {
    /// The hub's ingest endpoint.
    static let endpoint = URL(string: "https://diagnostics.roseclub.org:9110/v1/ingest")
    /// The Info.plist entry that carries the key.
    static let infoKey = IngestKey.defaultInfoKey

    /// The key this build was given, or `nil` when it has none. The rules for a usable key are the package's (`IngestKey`).
    static var appKey: String? { IngestKey.value(from: Bundle.main.infoDictionary ?? [:], infoKey: infoKey) }
}

/// Sends Spinner's typed health events to the diagnostics hub.
///
/// It wraps the client library's uploader, which holds the privacy line: an event is written to a queue on disk before any
/// send, goes out in small batches, backs off when the hub cannot be reached, and sends nothing while the setting is off or in
/// a Debug build. Nothing here throws or waits for the network, so a hub that is down never touches the app.
struct FieldDiagnostics: Sendable {
    private let uploader: DiagnosticsUploader?
    private let queue: DiskQueue?
    private let coalescer: EventCoalescer

    /// A sender over an uploader; tests give it one over a fake transport.
    /// - Parameters:
    ///   - queue: The uploader's queue, so it can be cleared when the person opts out.
    ///   - coalescer: Holds back a failure that repeats; the default allows each one once in ten minutes.
    init(uploader: DiagnosticsUploader, queue: DiskQueue? = nil, coalescer: EventCoalescer = EventCoalescer()) {
        self.uploader = uploader
        self.queue = queue
        self.coalescer = coalescer
    }

    private init() {
        uploader = nil
        queue = nil
        coalescer = EventCoalescer()
    }

    /// A sender that **asks the person's consent before it does anything**: nothing is queued and nothing is sent until they opt in, and an
    /// event from before they agreed is never sent after.
    static func make(
        endpoint: URL, appKey: String, identity: AppIdentity, channel: Channel, queue: DiskQueue, transport: any Transport,
        clock: any UploaderClock = SystemUploaderClock(), consent: DiagnosticsConsent = DiagnosticsConsent()
    ) -> FieldDiagnostics {
        FieldDiagnostics(
            uploader: DiagnosticsUploader(
                endpoint: endpoint, appKey: appKey, identity: identity, channel: channel, queue: queue, transport: transport, clock: clock,
                enabled: { consent.isOn }),
            queue: queue)
    }

    /// The running app's sender. If the endpoint cannot be formed, or this build has no key, it sends nothing; whatever it has, it sends nothing
    /// until the person opts in.
    static let shared: FieldDiagnostics = {
        guard let endpoint = FieldDiagnosticsConfiguration.endpoint, let appKey = FieldDiagnosticsConfiguration.appKey else {
            return FieldDiagnostics()
        }
        let folder = URL.applicationSupportDirectory
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("field-queue", isDirectory: true)
        return make(
            endpoint: endpoint, appKey: appKey, identity: FieldIdentity.current(), channel: ReceiptChannelResolver.bundle.resolve(),
            queue: DiskQueue(directory: folder), transport: URLSessionTransport())
    }()

    /// Queues an event and sends what is waiting; says what became of it, or `nil` when the event was held back because the
    /// same failure was reported moments ago.
    @discardableResult
    func send(_ event: FieldEvent) async -> SendOutcome? {
        guard let uploader else { return .notSent(.disabled) }
        guard coalescer.allows(key: event.coalescingKey) else { return nil }
        return await uploader.send(event.record)
    }

    /// Sends events that came from somewhere else, such as the operating system's diagnostics, through the same gate.
    func send(records: [EventRecord]) async {
        guard let uploader else { return }
        for record in records { _ = await uploader.send(record) }
    }

    /// Deletes whatever is waiting to be sent: for a person who has turned diagnostics off.
    func clearQueue() async {
        await queue?.removeAll()
    }

    /// Sends what is waiting, as the network and the backoff allow; `nil` when this sender has no uploader to flush.
    @discardableResult
    func flush() async -> FlushResult? {
        guard let uploader else { return nil }
        return await uploader.flush()
    }

    /// Reports an event without waiting for it: the caller carries on at once.
    func report(_ event: FieldEvent) {
        Task(priority: .utility) { await send(event) }
    }

    /// Reports that a call to KEXP's API failed with this error, unless the error is only a cancelled request.
    func reportFailure(of error: any Error, endpoint: APIEndpoint) {
        guard let failure = APIFailure.classify(error) else { return }
        report(.apiFailed(endpoint, failure))
    }

    /// Tries to send what an earlier failure left on disk, without waiting for it.
    func requestFlush() {
        Task(priority: .utility) { await flush() }
    }
}
