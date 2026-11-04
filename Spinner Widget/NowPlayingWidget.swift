//
//  NowPlayingWidget.swift
//  Spinner Widget
//

import AppIntents
import SwiftUI
import WidgetKit

/// The widget has nothing to configure; WidgetKit's async provider API wants a configuration intent.
struct NowPlayingConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Now Playing"
    static let description = IntentDescription("Shows what KEXP is playing.")
}

/// The Now Playing widget in three sizes.
struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetConstants.kind, intent: NowPlayingConfigurationIntent.self, provider: NowPlayingProvider()) { entry in
            NowPlayingEntryView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("What KEXP is playing: art, the song, and the show.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

/// Picks the layout for the widget's size, and gives it a background that respects Reduce Transparency.
struct NowPlayingEntryView: View {
    let entry: NowPlayingEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            switch family {
            case .systemSmall: SmallNowPlayingView(content: entry.content)
            case .systemMedium: MediumNowPlayingView(content: entry.content).padding(14)
            default: LargeNowPlayingView(content: entry.content).padding(16)
            }
        }
        .containerBackground(for: .widget) {
            if family == .systemSmall {
                Color.black
            } else if reduceTransparency {
                Color.systemBackgroundCompat
            } else {
                Rectangle().fill(.background)
            }
        }
    }
}

private extension Color {
    /// A solid background that exists on every platform the widget runs on.
    static var systemBackgroundCompat: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
}
