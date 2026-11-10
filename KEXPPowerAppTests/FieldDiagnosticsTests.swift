import Foundation
import os
import SwiftDiagnosticsClient
import Testing
@testable import KEXPPowerExampleSwiftUI

/// Moves a request nowhere and remembers it, answering with whatever outcome the test sets.
actor RecordingTransport: Transport {
    private(set) var requests: [UploadRequest] = []
    private var outcome: TransportOutcome = .delivered

    func set(_ outcome: TransportOutcome) { self.outcome = outcome }

    func send(_ request: UploadRequest) async -> TransportOutcome {
        requests.append(request)
        return outcome
    }
}

/// A clock the test moves, so backoff is measured without waiting.
actor ManualClock: UploaderClock {
    private var current = Date(timeIntervalSince1970: 1_000_000)

    func now() async -> Date { current }
    func advance(by seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }
}

/// The send path from `FieldDiagnostics` to the wire, over a fake transport and a real disk queue.
@Suite("FieldDiagnostics")
struct FieldDiagnosticsTests {
    private struct Rig {
        let diagnostics: FieldDiagnostics
        let transport: RecordingTransport
        let clock: ManualClock
        let isOn: OSAllocatedUnfairLock<Bool>
    }

    private func makeRig(channel: Channel = .appStore) throws -> Rig {
        let endpoint = try #require(URL(string: "https://diagnostics.example/v1/ingest"))
        let transport = RecordingTransport()
        let clock = ManualClock()
        let isOn = OSAllocatedUnfairLock(initialState: true)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("field-\(UUID().uuidString)", isDirectory: true)
        let identity = AppIdentity(
            app: "spinner", platform: .ios, appVersion: "3.5.1", build: "14", osVersion: "27.2", deviceClass: "iPhone")
        let uploader = DiagnosticsUploader(
            endpoint: endpoint, appKey: "test-key-0123456789abcdef", identity: identity,
            channel: channel, queue: DiskQueue(directory: folder), transport: transport, clock: clock,
            enabled: { isOn.withLock { $0 } })
        return Rig(diagnostics: FieldDiagnostics(uploader: uploader), transport: transport, clock: clock, isOn: isOn)
    }

    private func decode(_ request: UploadRequest) throws -> Envelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Envelope.self, from: request.body)
    }

    @Test("A launch becomes one request: the app, the build, the channel and exactly that event")
    func launchIsSent() async throws {
        let rig = try makeRig()
        let outcome = await rig.diagnostics.send(.launch(previousRun: .endedWhileActive))
        #expect(outcome == .queued)
        let requests = await rig.transport.requests
        #expect(requests.count == 1)
        let envelope = try decode(try #require(requests.first))
        #expect(envelope.app == "spinner")
        #expect(envelope.appVersion == "3.5.1")
        #expect(envelope.channel == .appStore)
        #expect(envelope.events.map(\.kind) == ["launch"])
        #expect(envelope.events.first?.fields == ["previousRun": .code("endedWhileActive")])
        #expect(requests.first?.appKey == "test-key-0123456789abcdef")
    }

    @Test("With the setting off nothing is queued and nothing is sent")
    func offSendsNothing() async throws {
        let rig = try makeRig()
        rig.isOn.withLock { $0 = false }
        let outcome = await rig.diagnostics.send(.rewindUnavailable(.serverFailed))
        #expect(outcome == .notSent(.disabled))
        #expect(await rig.transport.requests.isEmpty)
    }

    @Test("Turning the setting off mid-session stops the next send")
    func offMidSession() async throws {
        let rig = try makeRig()
        #expect(await rig.diagnostics.send(.launch(previousRun: .quit)) == .queued)
        rig.isOn.withLock { $0 = false }
        #expect(await rig.diagnostics.send(.launch(previousRun: .quit)) == .notSent(.disabled))
        #expect(await rig.transport.requests.count == 1)
    }

    @Test("A Debug build sends nothing, whatever the setting")
    func developmentSendsNothing() async throws {
        let rig = try makeRig(channel: .development)
        let outcome = await rig.diagnostics.send(.launch(previousRun: .firstLaunch))
        #expect(outcome == .notSent(.notEnabledForChannel(.development)))
        #expect(await rig.transport.requests.isEmpty)
    }

    @Test("A send that cannot be delivered stays queued, and the next flush after the backoff delivers it")
    func failureIsRetried() async throws {
        let rig = try makeRig()
        await rig.transport.set(.retryLater)
        #expect(await rig.diagnostics.send(.launch(previousRun: .endedInBackground)) == .queued)
        await rig.transport.set(.delivered)
        await rig.clock.advance(by: 4_000)
        let result = await rig.diagnostics.flush()
        #expect(result?.eventsDelivered == 1)
        #expect(await rig.transport.requests.count == 2)
    }

    @Test("The setting is on when it was never set, off once turned off, on again once turned on")
    func settingDefaults() throws {
        let suite = "field-setting-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(FieldDiagnosticsSetting.isOn(defaults))
        defaults.set(false, forKey: FieldDiagnosticsSetting.key)
        #expect(!FieldDiagnosticsSetting.isOn(defaults))
        defaults.set(true, forKey: FieldDiagnosticsSetting.key)
        #expect(FieldDiagnosticsSetting.isOn(defaults))
    }

    @Test("The identity is the bundle's version and build, with tokens for the platform and the device class")
    func identity() {
        let info: [String: Any] = ["CFBundleShortVersionString": "3.5.1", "CFBundleVersion": "14"]
        let identity = FieldIdentity.make(info: info, platform: .macos, osVersion: "27.2", deviceClass: "Mac")
        #expect(identity == AppIdentity(app: "spinner", platform: .macos, appVersion: "3.5.1", build: "14", osVersion: "27.2", deviceClass: "Mac"))
    }

    @Test("A bundle with no version does not crash; it says so with a token")
    func identityWithoutVersion() {
        let identity = FieldIdentity.make(info: [:], platform: .ios, osVersion: "27.2", deviceClass: "iPhone")
        #expect(identity.appVersion == "unknown")
        #expect(identity.build == "unknown")
    }

    @Test("The device class on this machine is one of the coarse classes, never a model identifier")
    func deviceClass() {
        #expect(["iPhone", "iPad", "Mac", "AppleTV"].contains(FieldIdentity.currentDeviceClass()))
    }
}
