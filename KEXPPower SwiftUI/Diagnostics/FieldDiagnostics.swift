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
    static let infoKey = "DiagnosticsIngestKey"

    /// The key this build was given, or `nil` when it has none.
    static var appKey: String? { key(from: Bundle.main.infoDictionary ?? [:]) }

    /// The key in an info dictionary, if it is a usable one.
    ///
    /// Not usable: no entry, a value that is not a string, an empty or blank one (a build without the untracked settings
    /// file), a build setting that was never expanded (`$(...)`), anything shorter than the hub issues (16 characters) or
    /// with a space or control character in it.
    static func key(from info: [String: Any]) -> String? {
        guard let raw = info[infoKey] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 16, !trimmed.hasPrefix("$(") else { return nil }
        guard trimmed.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value < 0x7F }) else { return nil }
        return trimmed
    }
}

/// The listener's choice to send anonymous health reports: on until it is turned off.
enum FieldDiagnosticsSetting {
    /// The `UserDefaults` key.
    static let key = "fieldDiagnosticsEnabled"

    /// Whether health reports may be sent. True when the listener never chose.
    static func isOn(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }
}

/// Sends Spinner's typed health events to the diagnostics hub.
///
/// It wraps the client library's uploader, which holds the privacy line: an event is written to a queue on disk before any
/// send, goes out in small batches, backs off when the hub cannot be reached, and sends nothing while the setting is off or in
/// a Debug build. Nothing here throws or waits for the network, so a hub that is down never touches the app.
struct FieldDiagnostics: Sendable {
    private let uploader: DiagnosticsUploader?
    private let coalescer: FieldEventCoalescer

    /// A sender over an uploader; tests give it one over a fake transport.
    /// - Parameter coalescer: Holds back a failure that repeats; the default allows each one once in ten minutes.
    init(uploader: DiagnosticsUploader, coalescer: FieldEventCoalescer = FieldEventCoalescer()) {
        self.uploader = uploader
        self.coalescer = coalescer
    }

    private init() {
        uploader = nil
        coalescer = FieldEventCoalescer()
    }

    /// The running app's sender. If the endpoint cannot be formed, or this build has no key, it sends nothing.
    static let shared: FieldDiagnostics = {
        guard let endpoint = FieldDiagnosticsConfiguration.endpoint, let appKey = FieldDiagnosticsConfiguration.appKey else {
            return FieldDiagnostics()
        }
        let folder = URL.applicationSupportDirectory
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("field-queue", isDirectory: true)
        return FieldDiagnostics(uploader: DiagnosticsUploader(
            endpoint: endpoint, appKey: appKey, identity: FieldIdentity.current(),
            channel: ReceiptChannelResolver.bundle.resolve(), queue: DiskQueue(directory: folder),
            transport: URLSessionTransport(), enabled: { FieldDiagnosticsSetting.isOn() }))
    }()

    /// Queues an event and sends what is waiting; says what became of it, or `nil` when the event was held back because the
    /// same failure was reported moments ago.
    @discardableResult
    func send(_ event: FieldEvent) async -> SendOutcome? {
        guard let uploader else { return .notSent(.disabled) }
        guard coalescer.allows(event) else { return nil }
        return await uploader.send(event.record)
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
