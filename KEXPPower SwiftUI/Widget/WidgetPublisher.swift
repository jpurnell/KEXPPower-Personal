//
//  WidgetPublisher.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import KEXPPower
import OSLog
import StationKit
import StationKitAdapterKEXP
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(TVServices)
import TVServices
#endif

/// Tells the widget what is on the air: saves a snapshot where the widget can read it, keeps the playing flag fresh,
/// and asks WidgetKit to reload only when something the widget shows has changed.
///
/// WidgetKit limits how often a widget may refresh, so a reload is spent on a new song, a new show, or playback
/// starting or stopping, and not on the app's every five-second poll.
@MainActor
final class WidgetPublisher {
    private static let stationName = "KEXP"
    private static let logoURL = URL(string: "https://kexp.org/static/assets/img/kexp_logo.jpg")

    /// The shared logic (save on change, heartbeat, reload only when something changed) lives in StationKit, so the
    /// watch app uses the same implementation; this type only turns KEXP's plays and shows into a snapshot.
    private let feed: WidgetFeed

    /// - Parameters:
    ///   - store: Where the widget reads from; the App Group by default.
    ///   - reload: Asks WidgetKit to reload the widget's timelines.
    init(
        store: any NowPlayingStore = AppGroupNowPlayingStore(groupID: WidgetConstants.groupID),
        reload: @escaping @MainActor () -> Void = WidgetPublisher.reloadWidgets
    ) {
        feed = WidgetFeed(store: store, reload: reload)
    }

    /// Records the latest play and show, and whether playback is running.
    /// - Parameters:
    ///   - play: The newest play; nothing is published before the first one has loaded.
    ///   - show: The show on the air, if known.
    ///   - isPlaying: Whether the stream is playing.
    ///   - date: The time of this update.
    func update(play: Play?, show: Show?, isPlaying: Bool, at date: Date = Date()) async {
        guard play != nil else { return }
        let snapshot = WidgetSnapshot(
            nowPlaying: KEXPMapping.nowPlaying(from: play),
            program: KEXPMapping.program(from: show),
            stationName: Self.stationName,
            fallbackArtworkURL: Self.logoURL,
            fetchedAt: date)
        let playStateChanged = await feed.publish(snapshot, isPlaying: isPlaying)
        logIfChanged(playStateChanged, isPlaying)
    }

    /// Publishes whether playback is running, on its own, as soon as it is known.
    ///
    /// The app calls this when the player's state changes, and the widget's play/pause intent calls it with the state
    /// it expects, so the widget need not wait for the next poll. It reloads the widget only if the state changed.
    /// - Parameters:
    ///   - isPlaying: Whether the stream is playing.
    ///   - date: The time of this update.
    func updatePlayState(isPlaying: Bool, at date: Date = Date()) async {
        let playStateChanged = await feed.publishPlayState(isPlaying, at: date)
        logIfChanged(playStateChanged, isPlaying)
    }

    /// Only changes are logged: the heartbeat repeats every poll and would drown them.
    private func logIfChanged(_ changed: Bool, _ isPlaying: Bool) {
        guard changed else { return }
        let message = "Published play state \(isPlaying ? "playing" : "paused") for the widget"
        let logger = Logger()
        logger.info("\(message, privacy: .public)")
    }

    /// Asks WidgetKit to reload the app's widgets, or on tvOS the Top Shelf. Widgets on visionOS need visionOS 26.
    static func reloadWidgets() {
        #if canImport(WidgetKit)
        #if os(visionOS)
        if #available(visionOS 26.0, *) { WidgetCenter.shared.reloadAllTimelines() }
        #else
        WidgetCenter.shared.reloadAllTimelines()
        // The Control Center control reads the same play state, so it is told at the same moment.
        if #available(iOS 18.0, macOS 26.0, *) { ControlCenter.shared.reloadControls(ofKind: WidgetConstants.controlKind) }
        #endif
        #elseif canImport(TVServices)
        // tvOS has no widgets; the same change refreshes the Top Shelf.
        TVTopShelfContentProvider.topShelfContentDidChange()
        #endif
    }
}
