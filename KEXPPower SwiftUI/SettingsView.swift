//
//  SettingsView.swift
//  KEXPPowerExampleSwiftUI
//

import SwiftUI

/// App settings, shown in the Settings window on macOS (Cmd-comma).
struct SettingsView: View {
    @AppStorage(StreamQuality.storageKey) private var storedQuality = StreamQuality.standard.rawValue

    var body: some View {
        Form {
            Picker("Stream quality", selection: $storedQuality) {
                ForEach(StreamQuality.allCases) { quality in
                    Text(quality.label).tag(quality.rawValue)
                }
            }
            Text("Changes apply the next time the app starts playback.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 380)
    }
}

#Preview {
    SettingsView()
}
