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

/// Tells the widget what is on the air: saves a snapshot where the widget can read it, keeps the playing flag fresh,
/// and asks WidgetKit to reload only when something the widget shows has changed.
///
/// WidgetKit limits how often a widget may refresh, so a reload is spent on a new song, a new show, or playback
/// starting or stopping, and not on the app's every five-second poll.
@MainActor
final class WidgetPublisher {
    private static let stationName = "KEXP"
    private static let logoURL = URL(string: "https://kexp.org/static/assets/img/kexp_logo.jpg")

    private let store: any NowPlayingStore
    private let reload: @MainActor () -> Void
    private var lastPublished: WidgetSnapshot?
    private var lastPlaying: Bool?

    /// - Parameters:
    ///   - store: Where the widget reads from; the App Group by default.
    ///   - reload: Asks WidgetKit to reload the widget's timelines.
    init(
        store: any NowPlayingStore = AppGroupNowPlayingStore(groupID: WidgetConstants.groupID),
        reload: @escaping @MainActor () -> Void = WidgetPublisher.reloadWidgets
    ) {
        self.store = store
        self.reload = reload
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

        let contentChanged = !Self.sameContent(snapshot, lastPublished)
        if contentChanged {
            await store.save(snapshot)
            lastPublished = snapshot
        }
        let playStateChanged = await publishPlayState(isPlaying, at: date)
        if contentChanged || playStateChanged { reload() }
    }

    /// Publishes whether playback is running, on its own, as soon as it is known.
    ///
    /// The app calls this when the player's state changes, and the widget's play/pause intent calls it with the state
    /// it expects, so the widget need not wait for the next poll. It reloads the widget only if the state changed.
    /// - Parameters:
    ///   - isPlaying: Whether the stream is playing.
    ///   - date: The time of this update.
    func updatePlayState(isPlaying: Bool, at date: Date = Date()) async {
        if await publishPlayState(isPlaying, at: date) { reload() }
    }

    /// Sets the playing flag, every time so it stays fresh, and reports whether it differs from the last one set.
    private func publishPlayState(_ isPlaying: Bool, at date: Date) async -> Bool {
        await store.setPlaying(isPlaying, at: date)
        let changed = lastPlaying != isPlaying
        lastPlaying = isPlaying
        if changed {
            // Only changes are logged: the heartbeat repeats every poll and would drown them.
            let message = "Published play state \(isPlaying ? "playing" : "paused") for the widget"
            let logger = Logger()
            logger.info("\(message, privacy: .public)")
        }
        return changed
    }

    /// Whether two snapshots show the same thing, ignoring when they were made.
    private static func sameContent(_ new: WidgetSnapshot, _ old: WidgetSnapshot?) -> Bool {
        guard var old else { return false }
        old.fetchedAt = new.fetchedAt
        return old == new
    }

    /// Asks WidgetKit to reload the app's widgets. Widgets on visionOS need visionOS 26.
    static func reloadWidgets() {
        #if canImport(WidgetKit)
        #if os(visionOS)
        if #available(visionOS 26.0, *) { WidgetCenter.shared.reloadAllTimelines() }
        #else
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        #endif
    }
}
