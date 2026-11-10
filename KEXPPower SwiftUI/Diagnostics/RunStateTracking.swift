//
//  RunStateTracking.swift
//  KEXPPowerExampleSwiftUI
//

import SwiftUI

/// Tells the run marker when the app goes to the background, comes back, or quits.
private struct RunStateTracking: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background: RunMarker.app.markBackground()
                case .active:
                    RunMarker.app.markActive()
                    // Whatever an earlier failure left waiting to be sent.
                    FieldDiagnostics.shared.requestFlush()
                default: break
                }
            }
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                RunMarker.app.markQuit()
            }
            #endif
    }
}

extension View {
    /// Keeps `RunMarker.app` current as the app goes to the background, returns, or quits.
    func tracksRunState() -> some View {
        modifier(RunStateTracking())
    }
}
