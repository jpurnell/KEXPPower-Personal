//
//  WatchNowPlayingWidget.swift
//  Spinner Watch Widget
//

import AppIntents
import OSLog
import StationKit
import StationKitAdapterKEXP
import SwiftUI
import WidgetKit

/// One moment of the watch widget: what to say, and when.
struct WatchNowPlayingEntry: TimelineEntry {
    let date: Date
    let summary: AccessorySummary
}

/// Gives WidgetKit what to show now and when to ask again, as the phone's widget does but without artwork:
/// the saved snapshot first, then KEXP's latest play. If KEXP cannot be reached the saved snapshot is shown.
struct WatchNowPlayingProvider: AppIntentTimelineProvider {
    typealias Intent = WatchNowPlayingConfigurationIntent
    typealias Entry = WatchNowPlayingEntry

    private let store = AppGroupNowPlayingStore(groupID: WatchWidgetConstants.groupID)
    private let policy = WidgetRefreshPolicy.standard

    func placeholder(in context: Context) -> WatchNowPlayingEntry {
        WatchNowPlayingEntry(date: Date(), summary: AccessorySummary(NowPlayingWidgetSample.snapshot, isPlaying: false))
    }

    /// A watch offers its widgets from a list the provider supplies, as there is no gallery to configure one in.
    func recommendations() -> [AppIntentRecommendation<WatchNowPlayingConfigurationIntent>] {
        [AppIntentRecommendation(intent: WatchNowPlayingConfigurationIntent(), description: "Now Playing")]
    }

    func snapshot(for configuration: Intent, in context: Context) async -> WatchNowPlayingEntry {
        if context.isPreview { return placeholder(in: context) }
        return await makeEntry().entry
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<WatchNowPlayingEntry> {
        let (entry, succeeded) = await makeEntry()
        return Timeline(entries: [entry], policy: .after(policy.nextRefresh(after: entry.date, lastSucceeded: succeeded)))
    }

    private func makeEntry() async -> (entry: WatchNowPlayingEntry, succeeded: Bool) {
        let now = Date()
        let logger = Logger(subsystem: "com.JPEnterprises.Spinner.watchkitapp.widget", category: "WatchNowPlayingProvider")
        var snapshot = await store.lastSnapshot()
        var succeeded = false
        do {
            let station = KEXPStation()
            let nowPlaying = try await station.nowPlaying()
            // The show is a nicety: its failing must not hide the song.
            let program = try? await station.currentProgram()
            let fresh = WidgetSnapshot(
                nowPlaying: nowPlaying, program: program, stationName: "KEXP",
                fallbackArtworkURL: nil, fetchedAt: now)
            await store.save(fresh)
            snapshot = fresh
            succeeded = true
        } catch {
            let message = "Watch widget could not fetch what is playing: \(error.localizedDescription)"
            logger.error("\(message, privacy: .public)")
        }
        let shown = snapshot ?? NowPlayingWidgetSample.snapshot
        let playing = await store.isPlaying()
        let built = "Watch widget entry made: \(playing ? "playing" : "paused"), \(succeeded ? "fresh from KEXP" : "from the saved snapshot")"
        logger.info("\(built, privacy: .public)")
        return (WatchNowPlayingEntry(date: now, summary: AccessorySummary(shown, isPlaying: playing)), succeeded)
    }
}

/// The watch widget has nothing to configure; WidgetKit's async provider API wants a configuration intent.
struct WatchNowPlayingConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Now Playing"
    static let description = IntentDescription("Shows what KEXP is playing.")
}

/// A sample snapshot for placeholders.
enum NowPlayingWidgetSample {
    static let snapshot = WidgetSnapshot(
        nowPlaying: .track(Track(
            id: "sample", title: "Sugar", credits: [Credit(role: .performer, name: "NoSo")],
            airDate: Date(timeIntervalSince1970: 1_730_000_000))),
        stationName: "KEXP", fallbackArtworkURL: nil, fetchedAt: Date(timeIntervalSince1970: 1_730_000_000))
}

/// The watch widget in the four accessory families.
struct WatchNowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WatchWidgetConstants.kind, intent: WatchNowPlayingConfigurationIntent.self,
            provider: WatchNowPlayingProvider()
        ) { entry in
            WatchNowPlayingEntryView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("What KEXP is playing, with play and pause.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner])
    }
}

/// Picks the layout for the accessory family.
struct WatchNowPlayingEntryView: View {
    let entry: WatchNowPlayingEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let summary = entry.summary
        switch family {
        case .accessoryCircular:
            Button(intent: WatchPlayPauseIntent()) {
                Image(systemName: summary.symbolName).font(.title2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(summary.actionLabel)
            .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryInline:
            Text(summary.inlineText)
                .accessibilityLabel(summary.accessibilityLabel)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryCorner:
            Button(intent: WatchPlayPauseIntent()) {
                Image(systemName: summary.symbolName).font(.title3)
            }
            .buttonStyle(.plain)
            .widgetLabel { Text(summary.inlineText) }
            .accessibilityLabel(summary.actionLabel)
            .containerBackground(for: .widget) { Color.clear }
        default:
            HStack(alignment: .center, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(summary.title).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                    Text(summary.artist).font(.caption).lineLimit(1)
                    Text(summary.timeLine).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(summary.accessibilityLabel)
                Spacer(minLength: 0)
                Button(intent: WatchPlayPauseIntent()) {
                    Image(systemName: summary.symbolName).font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(summary.actionLabel)
            }
            .containerBackground(for: .widget) { Color.clear }
        }
    }
}
