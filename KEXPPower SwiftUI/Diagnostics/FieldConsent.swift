//
//  FieldConsent.swift
//  KEXPPowerExampleSwiftUI
//

import SwiftDiagnosticsClient
import SwiftDiagnosticsConsentUI
import SwiftDiagnosticsMetricKit
import SwiftUI

/// The person's answer to "send anonymous diagnostics?", and what depends on it.
///
/// **Off until they say yes, in every build, and silent until they do.** Loading the app touches no network of ours; the question is shown
/// the first time; opting in starts the operating system's diagnostics subscriber; opting out stops it and deletes whatever was waiting to be
/// sent. The wording, the buttons and the Settings section are the package's (`SwiftDiagnosticsConsentUI`), the same in every app.
@MainActor
enum FieldConsent {
    /// The one consent model the app's screens share.
    static let model = DiagnosticsConsentModel(consent: DiagnosticsConsent(), onChange: { choice in FieldConsent.apply(choice) })

    #if canImport(MetricKit) && (os(iOS) || os(macOS) || os(visionOS))
    /// The operating system's diagnostics, asked for only after the person agrees, and forwarded through the same consent-gated sender.
    private static let subscriber = MetricKitSubscriber(isEnabled: { DiagnosticsConsent().isOn }, deliver: { events in
        Task(priority: .utility) { await FieldDiagnostics.shared.send(records: events) }
    })
    #endif

    /// Call once at launch: if the person has already agreed, start listening for the operating system's reports. With no answer, or a no,
    /// this does nothing at all.
    static func resume() {
        if model.isOn { startOperatingSystemReports() }
    }

    private static func apply(_ choice: DiagnosticsConsent.Choice) {
        switch choice {
        case .optedIn:
            startOperatingSystemReports()
        case .optedOut:
            stopOperatingSystemReports()
            Task(priority: .utility) { await FieldDiagnostics.shared.clearQueue() }
        case .notAsked:
            break
        }
    }

    private static func startOperatingSystemReports() {
        #if canImport(MetricKit) && (os(iOS) || os(macOS) || os(visionOS))
        subscriber.start()
        #endif
    }

    private static func stopOperatingSystemReports() {
        #if canImport(MetricKit) && (os(iOS) || os(macOS) || os(visionOS))
        subscriber.stop()
        #endif
    }
}
