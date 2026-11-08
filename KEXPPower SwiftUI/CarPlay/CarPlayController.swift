//
//  CarPlayController.swift
//  KEXPPowerExampleSwiftUI
//

#if os(iOS)
import AVFoundation
import CarPlay
import KEXPPower
import OSLog
import StationKit
import UIKit

/// Builds KEXP's CarPlay screens from the app's one player and model: a Live tab with the show and host and the song
/// on the air, an Archive tab (every day the archive holds, then the day's shows), and the system's Now Playing screen
/// with an add-to-playlist button on the live stream and a way back to live on an archived show.
///
/// CarPlay draws everything from system templates; this type only fills them in and keeps them current.
@MainActor
final class CarPlayController {
    private let logger = Logger(subsystem: "com.JPEnterprises.Spinner", category: "CarPlay")
    private let interfaceController: CPInterfaceController
    private let diagnostics = DiagnosticLog.app
    private let model: ResultRetriever
    private let saving: SongSavingModel
    private let archive: ArchiveBrowserModel

    private var archiveTemplate: CPListTemplate?
    private var showItem: CPListItem?
    private var songItem: CPListItem?
    private var isRunning = false
    private let watcher = WatchTask()

    /// - Parameters:
    ///   - interfaceController: The CarPlay screen's template stack.
    ///   - model: The app's player and playlist, shared with the phone.
    ///   - saving: Saves songs to the listener's playlists, shared with the phone.
    ///   - archive: The archive of past shows, shared with the phone.
    init(interfaceController: CPInterfaceController, model: ResultRetriever, saving: SongSavingModel, archive: ArchiveBrowserModel) {
        self.interfaceController = interfaceController
        self.model = model
        self.saving = saving
        self.archive = archive
    }

    /// Shows the root screens and starts keeping them current.
    func start() {
        diagnostics.record("CarPlay", "controller: building root screens")
        isRunning = true
        let live = CPListTemplate(title: "Live", sections: [CPListSection(items: makeLiveItems())])
        live.tabTitle = "Live"
        live.tabImage = UIImage(systemName: "dot.radiowaves.left.and.right")

        let archiveList = CPListTemplate(title: "Archive", sections: [CPListSection(items: makeArchiveItems())])
        archiveList.tabTitle = "Archive"
        archiveList.tabImage = UIImage(systemName: "archivebox")
        archiveTemplate = archiveList

        let root = CPTabBarTemplate(templates: [live, archiveList])
        // A completion is required: without one a failed presentation throws.
        interfaceController.setRootTemplate(root, animated: false) { [logger, diagnostics] success, error in
            let detail = error?.localizedDescription ?? "none"
            diagnostics.record("CarPlay", "controller: root screen shown \(success), error \(detail)")
            if !success { logger.error("CarPlay root template not shown: \(detail, privacy: .public)") }
        }
        refresh()
        // The system's Now Playing screen can be opened from the car's own button, so its buttons are set up front.
        CPNowPlayingTemplate.shared.updateNowPlayingButtons(makeNowPlayingButtons())
        watcher.task = Task { [weak self] in await self?.begin() }
        diagnostics.record("CarPlay", "controller: started")
    }

    /// Stops following the app when the car disconnects.
    func stop() {
        diagnostics.record("CarPlay", "controller: stopped")
        isRunning = false
        watcher.task?.cancel()
        watcher.task = nil
    }

    private func makeLiveItems() -> [CPListItem] {
        let show = CPListItem(text: "KEXP 90.3 FM", detailText: "Live")
        let song = CPListItem(text: "", detailText: "")
        for item in [show, song] {
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    await self?.listen()
                    completion()
                }
            }
        }
        showItem = show
        songItem = song
        return [show, song]
    }

    /// Starts the stream if it is not playing and opens the system's Now Playing screen.
    private func listen() async {
        diagnostics.record("CarPlay", "listen: row tapped")
        // An archived show is on: this row is the way back to the live stream.
        if archive.nowPlayingShow != nil { archive.returnToLive() }
        await AppModelRegistry.setPlayback(true)
        diagnostics.record("CarPlay", "listen: playback requested")
        showNowPlaying()
    }

    /// Opens the system's Now Playing screen, unless it is already showing.
    private func showNowPlaying() {
        let template = CPNowPlayingTemplate.shared
        template.updateNowPlayingButtons(makeNowPlayingButtons())
        guard interfaceController.topTemplate !== template else { return }
        interfaceController.pushTemplate(template, animated: true) { [logger, diagnostics] success, error in
            let detail = error?.localizedDescription ?? "none"
            diagnostics.record("CarPlay", "listen: Now Playing shown \(success), error \(detail)")
            if !success { logger.error("CarPlay Now Playing not shown: \(detail, privacy: .public)") }
        }
    }

    /// The buttons for what is playing: add-to-playlist on the live stream, the way back to live on an archived show.
    private func makeNowPlayingButtons() -> [CPNowPlayingButton] {
        CarPlayContent.nowPlayingButtons(isPlayingArchive: archive.nowPlayingShow != nil).map { button in
            switch button {
            case .save: makeSaveButton()
            case .live: makeLiveButton()
            }
        }
    }

    private func makeLiveButton() -> CPNowPlayingImageButton {
        let image = UIImage(systemName: CarPlayContent.liveButtonSymbol) ?? UIImage()
        return CPNowPlayingImageButton(image: image) { [weak self] _ in
            Task { @MainActor in await self?.listen() }
        }
    }

    // MARK: Archive

    /// The rows of the Archive tab: the days the archive holds, or a word on how loading stands.
    private func makeArchiveItems() -> [CPListItem] {
        switch archive.phase {
        case .idle, .loading:
            let item = CPListItem(text: "Loading the archive…", detailText: nil)
            item.isEnabled = false
            return [item]
        case .failed:
            let item = CPListItem(text: "The archive could not be reached", detailText: "Tap to try again")
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    await self?.archive.load()
                    completion()
                }
            }
            return [item]
        case .loaded:
            return archive.tiles.prefix(CPListTemplate.maximumItemCount).map { day in
                let row = CarPlayContent.dayRow(day)
                let item = CPListItem(text: row.title, detailText: row.detail)
                item.accessoryType = .disclosureIndicator
                item.isEnabled = !day.shows.isEmpty
                item.handler = { [weak self] _, completion in
                    Task { @MainActor in
                        await self?.showShows(of: day)
                        completion()
                    }
                }
                return item
            }
        }
    }

    /// Pushes the list of a day's shows.
    private func showShows(of day: ArchiveDayTile) async {
        let zone = ShowTimeZone.resolve(stored: UserDefaults.standard.string(forKey: ShowTimeZone.storageKey)).zone
        let items = day.shows.prefix(CPListTemplate.maximumItemCount).map { show in
            let row = CarPlayContent.archiveShowRow(show, zone: zone)
            let item = CPListItem(text: row.title, detailText: row.detail)
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    await self?.play(show)
                    completion()
                }
            }
            return item
        }
        let list = CPListTemplate(title: CarPlayContent.dayRow(day).title, sections: [CPListSection(items: items)])
        interfaceController.pushTemplate(list, animated: true) { [logger] success, error in
            if !success { logger.error("CarPlay show list not shown: \(error?.localizedDescription ?? "none", privacy: .public)") }
        }
    }

    /// Plays an archived show and opens Now Playing, unless the show has no audio.
    private func play(_ show: StationKit.ArchiveShow) async {
        diagnostics.record("CarPlay", "archive: playing \(show.programName)")
        await archive.play(show)
        guard archive.nowPlayingShow != nil else {
            diagnostics.record("CarPlay", "archive: show did not start")
            return
        }
        showNowPlaying()
    }

    /// The add-to-playlist button, drawn for the current save state.
    private func makeSaveButton() -> CPNowPlayingImageButton {
        let state = saving.state(for: model.play)
        // A symbol the system lacks falls back to a plain phone rather than a blank button.
        let image = UIImage(systemName: CarPlayContent.saveButtonSymbol(for: state)) ?? UIImage(systemName: "iphone") ?? UIImage()
        let button = CPNowPlayingImageButton(image: image) { [weak self] _ in
            Task { @MainActor in await self?.save() }
        }
        button.isSelected = CarPlayContent.saveButtonSelected(for: state)
        button.isEnabled = CarPlayContent.saveButtonEnabled(for: state) && SongSavingModel.canSave(model.play)
        return button
    }

    /// Adds the song on the air to the listener's playlist, the same way the phone's button does.
    private func save() async {
        diagnostics.record("CarPlay", "save: button pressed")
        await saving.save(model.play, holdingGuesses: true)
        let state = saving.state(for: model.play)
        diagnostics.record("CarPlay", "save: finished, state \(state)")
        refresh()
    }

    /// Fills the rows and the button from the current show, song and save state.
    private func refresh() {
        let show = CarPlayContent.showRow(programName: model.show.programName, hostNames: model.show.hostNames)
        showItem?.setText(show.title)
        showItem?.setDetailText(show.detail)
        let song = CarPlayContent.songRow(NowPlayingSummary(model.play))
        songItem?.setText(song.title)
        songItem?.setDetailText(song.detail)
        CPNowPlayingTemplate.shared.updateNowPlayingButtons(makeNowPlayingButtons())
        archiveTemplate?.updateSections([CPListSection(items: makeArchiveItems())])
    }

    /// Starts following the station, then keeps the screens current. CarPlay can launch the app with no window open,
    /// and the model otherwise starts fetching only when a window asks, so the car asks for itself.
    private func begin() async {
        diagnostics.record("CarPlay", "controller: asking the model to start fetching")
        async let archiveLoaded: Void = archiveLoad()
        await model.startIfNeeded()
        refresh()
        diagnostics.record("CarPlay", "controller: first fetch returned, show \(model.show.programName ?? "none")")
        await archiveLoaded
        refresh()
        await watch()
    }

    /// Fetches the archive's days when the phone has not, so the car can list them.
    private func archiveLoad() async {
        guard archive.phase == .idle else { return }
        await archive.load()
    }

    /// Redraws whenever the show, the song or the save state changes, until the car disconnects.
    private func watch() async {
        while isRunning, !Task.isCancelled {
            // Observation fires once per registration, so each pass registers again after a change.
            await withCheckedContinuation { continuation in
                withObservationTracking {
                    _ = model.show
                    _ = model.play
                    _ = saving.state(for: model.play)
                    _ = archive.nowPlayingShow
                    _ = archive.phase
                } onChange: {
                    continuation.resume()
                }
            }
            refresh()
        }
    }
}

/// Holds the watching loop and cancels it when the controller goes away.
private final class WatchTask {
    var task: Task<Void, Never>?

    deinit {
        task?.cancel()
    }
}
#endif
