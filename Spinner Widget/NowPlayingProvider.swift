//
//  NowPlayingProvider.swift
//  Spinner Widget
//

import Foundation
import OSLog
import StationKit
import StationKitAdapterKEXP
import WidgetKit

/// One moment of the widget: what to show, and when.
struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let content: NowPlayingWidgetContent
}

/// Gives WidgetKit what to show now and when to ask again.
///
/// It starts from the last snapshot the app saved in the App Group, so there is always something to show, then asks
/// KEXP for the latest play. If KEXP cannot be reached the saved snapshot is shown, marked with when it is from.
struct NowPlayingProvider: AppIntentTimelineProvider {
    typealias Intent = NowPlayingConfigurationIntent
    typealias Entry = NowPlayingEntry

    private let store = AppGroupNowPlayingStore(groupID: WidgetConstants.groupID)
    private let policy = WidgetRefreshPolicy.standard
    private let artworkLoader = ArtworkLoader(allowedDomains: WidgetConstants.artworkDomains)

    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), content: .sample)
    }

    func snapshot(for configuration: Intent, in context: Context) async -> NowPlayingEntry {
        // The gallery asks for a quick sample; do not make it wait for the network.
        if context.isPreview { return placeholder(in: context) }
        return await makeEntry().entry
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<NowPlayingEntry> {
        let (entry, succeeded) = await makeEntry()
        return Timeline(entries: [entry], policy: .after(policy.nextRefresh(after: entry.date, lastSucceeded: succeeded)))
    }

    /// The entry for now, and whether the latest play could be fetched.
    private func makeEntry() async -> (entry: NowPlayingEntry, succeeded: Bool) {
        let now = Date()
        var snapshot = await store.lastSnapshot()
        var succeeded = false

        do {
            let station = KEXPStation()
            let nowPlaying = try await station.nowPlaying()
            // The show is a nicety: its failing must not hide the song.
            let program = await currentProgram(of: station)
            let fresh = WidgetSnapshot(
                nowPlaying: nowPlaying, program: program, stationName: "KEXP",
                fallbackArtworkURL: WidgetConstants.logoURL, fetchedAt: now)
            await store.save(fresh)
            snapshot = fresh
            succeeded = true
        } catch {
            let message = "Widget could not fetch what is playing: \(error.localizedDescription)"
            let logger = Logger(subsystem: "com.JPEnterprises.Spinner.widget", category: "NowPlayingProvider")
            logger.error("\(message, privacy: .public)")
        }

        let shown = snapshot ?? NowPlayingWidgetContent.sample.snapshot
        let content = NowPlayingWidgetContent(
            snapshot: shown,
            artwork: await artwork(for: shown.artworkURL),
            isPlaying: await store.isPlaying(),
            isStale: policy.isStale(fetchedAt: shown.fetchedAt, asOf: now))
        return (NowPlayingEntry(date: now, content: content), succeeded)
    }

    private func currentProgram(of station: KEXPStation) async -> ProgramInfo? {
        do {
            return try await station.currentProgram()
        } catch {
            let message = "Widget could not fetch the current show: \(error.localizedDescription)"
            let logger = Logger(subsystem: "com.JPEnterprises.Spinner.widget", category: "NowPlayingProvider")
            logger.error("\(message, privacy: .public)")
            return nil
        }
    }

    /// The artwork scaled for a widget, or `nil` if the host is not allowed or the download fails.
    private func artwork(for url: URL?) async -> Data? {
        guard let url, artworkLoader.isAllowed(url) else { return nil }
        do {
            let data = try await ArtworkLoader.fetchOverNetwork(url)
            return ArtworkThumbnail.make(from: data, maxPixel: 400)
        } catch {
            let message = "Widget could not download artwork: \(error.localizedDescription)"
            let logger = Logger(subsystem: "com.JPEnterprises.Spinner.widget", category: "NowPlayingProvider")
            logger.error("\(message, privacy: .public)")
            return nil
        }
    }
}
