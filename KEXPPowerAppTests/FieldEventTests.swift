import Foundation
import SwiftDiagnosticsClient
import SwiftDiagnosticsMetricKit
import Testing
@testable import KEXPPowerExampleSwiftUI

/// What Spinner may report to the diagnostics hub: typed fields only, and exactly what its schema file allows.
@Suite("FieldEvent")
struct FieldEventTests {
    @Test("A launch carries how the last run ended as a code, and only that")
    func launchRecord() {
        for previous in [PreviousRun.firstLaunch, .endedWhileActive, .endedInBackground, .quit] {
            let record = FieldEvent.launch(previousRun: previous).record
            #expect(record.kind == "launch")
            #expect(record.fields == ["previousRun": .code(previous.rawValue)])
        }
    }

    @Test("Only a run that ended while the app was in use is worth a warning; the others are routine")
    func launchSeverity() {
        #expect(FieldEvent.launch(previousRun: .endedWhileActive).record.severity == .warning)
        for previous in [PreviousRun.firstLaunch, .endedInBackground, .quit] {
            #expect(FieldEvent.launch(previousRun: previous).record.severity == .info)
        }
    }

    @Test("A rewind fallback carries its reason as a code and is a warning")
    func rewindRecord() {
        for reason in RewindReason.allCases {
            let record = FieldEvent.rewindUnavailable(reason).record
            #expect(record.kind == "rewindUnavailable")
            #expect(record.severity == .warning)
            #expect(record.fields == ["reason": .code(reason.rawValue)])
        }
    }

    @Test("A live start carries how it went, how long, over what network and to what output, all as codes")
    func liveStartRecord() {
        let start = LiveStart(outcome: .rebuilt, took: .from5to15, network: .cellular, route: .carPlay)
        let record = FieldEvent.liveStart(start).record
        #expect(record.kind == "liveStart")
        #expect(record.fields == [
            "outcome": .code("rebuilt"), "took": .code("from5to15"), "network": .code("cellular"), "route": .code("carPlay"),
        ])
    }

    @Test("A start that went as it should is routine; one that needed help is a warning; one that never began is an error")
    func liveStartSeverity() {
        func severity(_ outcome: LiveStartOutcome) -> Severity {
            FieldEvent.liveStart(LiveStart(outcome: outcome, took: .under2, network: .wifi, route: .speaker)).record.severity
        }
        #expect(severity(.started) == .info)
        #expect(severity(.rebuilt) == .warning)
        #expect(severity(.fellBackDirect) == .warning)
        #expect(severity(.recoveredOnNetwork) == .warning)
        #expect(severity(.gaveUp) == .error)
    }

    @Test("Live starts are never held back as repeats: each is one start")
    func liveStartIsNotCoalesced() {
        let start = LiveStart(outcome: .gaveUp, took: .over40, network: .none, route: .speaker)
        #expect(FieldEvent.liveStart(start).coalescingKey == nil)
    }

    @Test("Every value a live start can carry passes the schema file, so the hub accepts all of them")
    func everyLiveStartPasses() throws {
        let validator = SchemaValidator(schema: try loadSchema())
        var events: [EventRecord] = []
        for outcome in LiveStartOutcome.allCases {
            for took in StartDuration.allCases {
                for network in NetworkKind.allCases {
                    for route in OutputRoute.allCases {
                        events.append(FieldEvent.liveStart(LiveStart(outcome: outcome, took: took, network: network, route: route)).record)
                    }
                }
            }
        }
        for channel in Channel.allCases {
            // The envelope holds at most a hundred events, so the combinations go in as many as it needs.
            for chunk in stride(from: 0, to: events.count, by: 100) {
                let result = validator.validate(envelope(Array(events[chunk..<min(chunk + 100, events.count)]), channel: channel))
                #expect(result.rejected.isEmpty, "\(channel): \(result.rejected.prefix(1))")
            }
        }
    }

    @Test("A stall carries why, how long, what was buffered, the network, the output, how it ended and how many recoveries were tried: codes and one bounded number")
    func playbackStallRecord() {
        let stall = PlaybackStall(reason: .networkLost, took: .from120to300, ahead: .from30to120, network: .none, route: .carPlay, outcome: .resumed, cycles: 0)
        let record = FieldEvent.playbackStall(stall).record
        #expect(record.kind == "playbackStall")
        #expect(record.fields == [
            "reason": .code("networkLost"), "took": .code("from120to300"), "ahead": .code("from30to120"), "network": .code("none"),
            "route": .code("carPlay"), "outcome": .code("resumed"), "cycles": .int(0),
        ])
        #expect(FieldEvent.playbackStall(stall).coalescingKey == nil)
    }

    @Test("A stall that ended by itself or by the listener is routine, one that needed help or whose end was not seen is a warning, one given up on is an error")
    func playbackStallSeverity() {
        func severity(_ outcome: StallOutcome) -> Severity {
            FieldEvent.playbackStall(PlaybackStall(reason: .bufferEmpty, took: .under2, ahead: .none, network: .wifi, route: .speaker, outcome: outcome, cycles: 0)).record.severity
        }
        #expect(severity(.resumed) == .info)
        #expect(severity(.listenerPaused) == .info)
        #expect(severity(.rebuilt) == .warning)
        #expect(severity(.restarted) == .warning)
        #expect(severity(.unfinished) == .warning)
        #expect(severity(.gaveUp) == .error)
    }

    @Test("Every value a stall can carry passes the schema file, on every channel, and a cycle count past the cap does not")
    func everyPlaybackStallPasses() throws {
        let validator = SchemaValidator(schema: try loadSchema())
        var events: [EventRecord] = []
        for reason in StallReason.allCases {
            for took in OutageDuration.allCases {
                for ahead in AheadBucket.allCases {
                    for network in NetworkKind.allCases {
                        for route in OutputRoute.allCases {
                            for outcome in StallOutcome.allCases {
                                events.append(FieldEvent.playbackStall(PlaybackStall(
                                    reason: reason, took: took, ahead: ahead, network: network, route: route, outcome: outcome, cycles: 0)).record)
                            }
                        }
                    }
                }
            }
        }
        for channel in Channel.allCases {
            for chunk in stride(from: 0, to: events.count, by: 100) {
                let result = validator.validate(envelope(Array(events[chunk..<min(chunk + 100, events.count)]), channel: channel))
                #expect(result.rejected.isEmpty, "\(channel): \(result.rejected.prefix(1))")
            }
        }
        for cycles in [0, 10, 50] {
            let record = FieldEvent.playbackStall(PlaybackStall(reason: .unknown, took: .under2, ahead: .none, network: .none, route: .other, outcome: .gaveUp, cycles: cycles)).record
            #expect(validator.validate(envelope([record])).rejected.isEmpty, "cycles \(cycles)")
        }
        let tooMany = FieldEvent.playbackStall(PlaybackStall(reason: .unknown, took: .under2, ahead: .none, network: .none, route: .other, outcome: .gaveUp, cycles: 51)).record
        #expect(validator.validate(envelope([tooMany])).rejected.count == 1)
    }

    @Test("No event holds free text, a number or a boolean: every field is a code")
    func onlyCodes() {
        var events: [FieldEvent] = RewindReason.allCases.map { .rewindUnavailable($0) }
        events.append(.liveStart(LiveStart(outcome: .started, took: .under2, network: .wifi, route: .speaker)))
        events += [PreviousRun.firstLaunch, .endedWhileActive, .endedInBackground, .quit].map { .launch(previousRun: $0) }
        for event in events {
            for value in event.record.fields.values {
                guard case .code = value else {
                    Issue.record("\(event) has a field that is not a code")
                    continue
                }
            }
        }
    }

    // MARK: The schema file

    /// The schema as the repository keeps it: the source of truth the hub's apps file is made from.
    private func loadSchema() throws -> AppSchema {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("project/diagnostics/spinner-schema.json"))
        return try JSONDecoder().decode(AppSchema.self, from: data)
    }

    private func envelope(_ events: [EventRecord], channel: Channel = .appStore) -> Envelope {
        Envelope(
            app: "spinner", platform: .ios, appVersion: "3.5.1", build: "14", osVersion: "27.2", deviceClass: "iPhone", channel: channel,
            launchID: "L1", sentAt: Date(timeIntervalSince1970: 0), events: events)
    }

    @Test("Every event the app can produce passes the schema file, on every channel")
    func everyEventPassesTheSchema() throws {
        let validator = SchemaValidator(schema: try loadSchema())
        var events: [FieldEvent] = RewindReason.allCases.map { .rewindUnavailable($0) }
        events += [PreviousRun.firstLaunch, .endedWhileActive, .endedInBackground, .quit].map { .launch(previousRun: $0) }
        for channel in Channel.allCases {
            let result = validator.validate(envelope(events.map(\.record), channel: channel))
            #expect(result.envelopeRejection == nil)
            #expect(result.rejected.isEmpty, "\(channel): \(result.rejected)")
            #expect(result.accepted.count == events.count)
        }
    }

    @Test("The schema file names the app, and refuses a code it does not list and a field it does not have")
    func schemaRefuses() throws {
        let schema = try loadSchema()
        #expect(schema.app == "spinner")
        let validator = SchemaValidator(schema: schema)
        let at = Date(timeIntervalSince1970: 0)
        let unlisted = EventRecord(kind: "launch", severity: .info, at: at, fields: ["previousRun": .code("crashed")])
        let extra = EventRecord(
            kind: "launch", severity: .info, at: at, fields: ["previousRun": .code("quit"), "show": .code("morning")])
        let unknownKind = EventRecord(kind: "nowPlaying", severity: .info, at: at, fields: [:])
        let result = validator.validate(envelope([unlisted, extra, unknownKind]))
        #expect(result.accepted.isEmpty)
        #expect(result.rejected.count == 3)
    }

    @Test("The schema file allows no free text from any channel")
    func schemaAllowsNoText() throws {
        // `AppSchema` cannot be built with text from the App Store channel; this also holds for the others, as the file's
        // fields are all codes or an integer range.
        for kind in try loadSchema().kinds {
            for field in kind.fields {
                if case .text = field.type { Issue.record("\(kind.name).\(field.name) is free text") }
            }
        }
    }

    @Test("The schema file carries every kind the MetricKit mapping can emit, exactly, so the hub accepts what the operating system reports")
    func schemaHasMetricKitKinds() throws {
        let schema = try loadSchema()
        #expect(schema.version == 6)
        for kind in MetricKitMapping.kinds { #expect(schema.kinds.contains(kind), "\(kind.name)") }
    }

    @Test("What the mapping produces passes the schema file on every channel")
    func metricKitEventsPass() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var events = MetricKitMapping.events(crashes: [CrashReport(exceptionType: 1, signal: 11, terminationReason: "Namespace SIGNAL", callStackTreeJSON: nil)], now: now)
        events += MetricKitMapping.events(hangs: [HangReport(durationSeconds: 9, callStackTreeJSON: nil)], now: now)
        events += MetricKitMapping.events(cpuExceptions: [CPUExceptionReport(totalCPUSeconds: 20, callStackTreeJSON: nil)], now: now)
        events += MetricKitMapping.events(diskWrites: [DiskWriteReport(bytesWritten: 3_000_000_000, callStackTreeJSON: nil)], now: now)
        events += MetricKitMapping.events(daily: DailyMetricsReport(launchSeconds: 1.2, hangSeconds: 3, peakMemoryBytes: 200_000_000, abnormalExits: 1), now: now)
        let validator = SchemaValidator(schema: try loadSchema())
        for channel in Channel.allCases {
            let envelope = Envelope(
                app: "spinner", platform: .ios, appVersion: "3.6.0", build: "1", osVersion: "27.2", deviceClass: "iPhone", channel: channel,
                launchID: "launch-1", sentAt: now, events: events)
            let result = validator.validate(envelope)
            #expect(result.rejected.isEmpty && result.accepted.count == events.count, "\(channel)")
        }
    }
}
