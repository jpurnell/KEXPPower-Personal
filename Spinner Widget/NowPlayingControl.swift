//
//  NowPlayingControl.swift
//  Spinner Widget
//

#if !os(visionOS)
import AppIntents
import StationKit
import SwiftUI
import WidgetKit

/// Reads the playing state the app publishes, for the control to show.
@available(iOS 18.0, macOS 26.0, *)
struct PlayStateValueProvider: ControlValueProvider {
    private let store = AppGroupNowPlayingStore(groupID: WidgetConstants.groupID)

    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        await store.isPlaying()
    }
}

/// A Control Center control that plays or pauses KEXP and shows which it is doing.
@available(iOS 18.0, macOS 26.0, *)
struct NowPlayingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetConstants.controlKind, provider: PlayStateValueProvider()) { isPlaying in
            ControlWidgetToggle("KEXP", isOn: isPlaying, action: SetPlayingIntent()) { playing in
                Label(ControlPlayState.valueText(isPlaying: playing), systemImage: ControlPlayState.symbolName(isPlaying: playing))
                    .accessibilityLabel(ControlPlayState.accessibilityLabel(station: "KEXP", isPlaying: playing))
            }
        }
        .displayName("KEXP")
        .description("Play or pause KEXP.")
    }
}
#endif
