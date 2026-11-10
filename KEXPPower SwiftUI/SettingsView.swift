//
//  SettingsView.swift
//  KEXPPowerExampleSwiftUI
//

import DiagnosticsKit
import SwiftUI

/// App settings: how live is played and which time zone times are shown in. A window on the Mac (Cmd-comma), a sheet
/// on the iPhone and iPad.
///
/// The times change as soon as they are picked. The quality and the rewind window need the live stream started over,
/// so they are applied when this screen goes away, and only if one changed.
struct SettingsView: View {
    let model: ResultRetriever
    @AppStorage(StreamQuality.storageKey) private var storedQuality = StreamQuality.standard.rawValue
    @AppStorage(RewindWindow.storageKey) private var storedWindow = RewindWindow.tenMinutes.rawValue
    @AppStorage(Cushion.storageKey) private var storedCushion = Cushion.off.rawValue
    @AppStorage(ShowTimeZone.storageKey) private var storedZone = ShowTimeZone.mine.rawValue
    /// The listening settings as they were when this screen appeared.
    @State private var opened = ListeningSettings.current()
    #if os(iOS)
    @Environment(\.dismiss) private var dismiss
    #endif

    private var quality: StreamQuality { StreamQuality.resolve(stored: storedQuality) }
    private var window: RewindWindow { RewindWindow.resolve(stored: storedWindow) }

    var body: some View {
        #if os(iOS)
        NavigationStack {
            form
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
        #else
        form
            .padding()
            .frame(width: 420)
        #endif
    }

    private var form: some View {
        Form {
            Section {
                Picker("Rewind window", selection: $storedWindow) {
                    ForEach(RewindWindow.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Text(ListeningSettings.windowNote(window: window, quality: quality))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // A cushion needs a recording to be behind in, and changing it does not restart the stream.
                if window != .off {
                    Picker("Stay behind live", selection: $storedCushion) {
                        ForEach(Cushion.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    Text(ListeningSettings.cushionNote(cushion: Cushion.resolve(stored: storedCushion), window: window))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("Stream quality", selection: $storedQuality) {
                    ForEach(StreamQuality.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Text(ListeningSettings.qualityNote(for: quality))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Listening")
            } footer: {
                Text("Changing these restarts the live stream.")
            }
            Section("Times") {
                Picker("Show times in", selection: $storedZone) {
                    ForEach(ShowTimeZone.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }
            #if !os(tvOS)
            Section {
                DiagnosticShareButton(reportProvider: { try await DiagnosticReportMetadata.report() }) {
                    Label("Send Diagnostics", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Problems")
            } footer: {
                Text("Makes one file of what the app recorded about itself, with the app version and these settings, and lets you choose where it goes. Nothing is sent unless you send it. It can include names of shows and songs the app was handling.")
            }
            #endif
        }
        .onAppear { opened = ListeningSettings.current() }
        .onDisappear { Task { await applyChanges() } }
    }

    /// Starts live over if the quality or the window changed since this screen appeared.
    private func applyChanges() async {
        let now = ListeningSettings.current()
        guard ListeningSettings.restartsLive(from: opened, to: now) else { return }
        await model.apply(now)
        opened = now
    }
}

#Preview {
    SettingsView(model: ResultRetriever())
}
