//
//  CarPlayController.swift
//  KEXPPowerExampleSwiftUI
//

#if os(iOS)
import CarPlay
import KEXPPower
import OSLog
import UIKit

/// Builds KEXP's CarPlay screens from the app's one player and model: a Live tab with the show and host and the song
/// on the air, an Archive tab (not built yet), and the system's Now Playing screen with an add-to-playlist button.
///
/// CarPlay draws everything from system templates; this type only fills them in and keeps them current.
@MainActor
final class CarPlayController {
    private let logger = Logger(subsystem: "com.JPEnterprises.Spinner", category: "CarPlay")
    private let interfaceController: CPInterfaceController
    private let model: ResultRetriever
    private let saving: SongSavingModel

    private var showItem: CPListItem?
    private var songItem: CPListItem?
    private var isRunning = false
    private let watcher = WatchTask()

    /// - Parameters:
    ///   - interfaceController: The CarPlay screen's template stack.
    ///   - model: The app's player and playlist, shared with the phone.
    ///   - saving: Saves songs to the listener's playlists, shared with the phone.
    init(interfaceController: CPInterfaceController, model: ResultRetriever, saving: SongSavingModel) {
        self.interfaceController = interfaceController
        self.model = model
        self.saving = saving
    }

    /// Shows the root screens and starts keeping them current.
    func start() {
        isRunning = true
        let live = CPListTemplate(title: "Live", sections: [CPListSection(items: makeLiveItems())])
        live.tabTitle = "Live"
        live.tabImage = UIImage(systemName: "dot.radiowaves.left.and.right")

        let archiveItem = CPListItem(text: CarPlayContent.archiveRow.title, detailText: CarPlayContent.archiveRow.detail)
        archiveItem.isEnabled = false
        let archive = CPListTemplate(title: "Archive", sections: [CPListSection(items: [archiveItem])])
        archive.tabTitle = "Archive"
        archive.tabImage = UIImage(systemName: "archivebox")

        let root = CPTabBarTemplate(templates: [live, archive])
        // A completion is required: without one a failed presentation throws.
        interfaceController.setRootTemplate(root, animated: false) { [logger] success, error in
            if !success { logger.error("CarPlay root template not shown: \(error?.localizedDescription ?? "unknown", privacy: .public)") }
        }
        refresh()
        watcher.task = Task { [weak self] in await self?.watch() }
    }

    /// Stops following the app when the car disconnects.
    func stop() {
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
        await AppModelRegistry.setPlayback(true)
        let template = CPNowPlayingTemplate.shared
        template.updateNowPlayingButtons([makeSaveButton()])
        guard interfaceController.topTemplate !== template else { return }
        interfaceController.pushTemplate(template, animated: true) { [logger] success, error in
            if !success { logger.error("CarPlay Now Playing not shown: \(error?.localizedDescription ?? "unknown", privacy: .public)") }
        }
    }

    /// The add-to-playlist button, drawn for the current save state.
    private func makeSaveButton() -> CPNowPlayingImageButton {
        let state = saving.state(for: model.play)
        let image = UIImage(systemName: CarPlayContent.saveButtonSymbol(for: state)) ?? UIImage()
        let button = CPNowPlayingImageButton(image: image) { [weak self] _ in
            Task { @MainActor in await self?.save() }
        }
        button.isSelected = CarPlayContent.saveButtonSelected(for: state)
        button.isEnabled = CarPlayContent.saveButtonEnabled(for: state) && SongSavingModel.canSave(model.play)
        return button
    }

    /// Adds the song on the air to the listener's playlist, the same way the phone's button does.
    private func save() async {
        await saving.save(model.play)
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
        if interfaceController.topTemplate === CPNowPlayingTemplate.shared {
            CPNowPlayingTemplate.shared.updateNowPlayingButtons([makeSaveButton()])
        }
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
