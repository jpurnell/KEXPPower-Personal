import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

/// The suites that touch `AppModelRegistry`'s shared static state. They are nested here so they run one at a time, not
/// side by side: a `.serialized` trait on each suite only orders the tests inside it.
@Suite("AppModelRegistry", .serialized)
enum RegistrySuites {}

/// The registry's entry points for Siri and Shortcuts.
extension RegistrySuites {
@Suite("Entry points")
@MainActor
struct IntentTests {
    /// Runs a body with the registry holding a model and an archive of their own, then puts it back.
    private func withRegistry(_ body: (ResultRetriever) async -> Void) async {
        let (savedModel, savedArchive) = (AppModelRegistry.model, AppModelRegistry.archive)
        let model = ResultRetriever()
        AppModelRegistry.model = model
        AppModelRegistry.archive = nil
        await body(model)
        AppModelRegistry.model = savedModel
        AppModelRegistry.archive = savedArchive
    }

    @Test("Before the app has made its model, every entry point says it is not ready and does nothing")
    func notReady() async {
        let saved = AppModelRegistry.model
        AppModelRegistry.model = nil
        #expect(AppModelRegistry.whatsPlaying() == AppModelRegistry.notReady)
        #expect(await AppModelRegistry.playLive() == AppModelRegistry.notReady)
        #expect(AppModelRegistry.pause() == AppModelRegistry.notReady)
        #expect(await AppModelRegistry.backToLive() == AppModelRegistry.notReady)
        #expect(await AppModelRegistry.rewind(window: .tenMinutes) == AppModelRegistry.notReady)
        AppModelRegistry.model = saved
    }

    @Test("Rewind says why it cannot when live is not playing through the recording, and when the window is Off")
    func rewindRefused() async {
        await withRegistry { _ in
            let notShifted = await AppModelRegistry.rewind(window: .tenMinutes)
            #expect(notShifted == IntentSpeech.rewindRefusal(window: .tenMinutes, isLiveShifted: false, isArchive: false))
            let off = await AppModelRegistry.rewind(window: .off)
            #expect(off.contains("off"))
        }
    }

    @Test("Back to live from live that is not rewound says so")
    func backToLiveWhenLive() async {
        await withRegistry { _ in
            #expect(await AppModelRegistry.backToLive() == "You are already listening live.")
        }
    }

    @Test("Asking what is playing before anything has loaded is answered in a sentence, not left empty")
    func whatsPlayingAnswers() async {
        await withRegistry { _ in
            #expect(!AppModelRegistry.whatsPlaying().isEmpty)
        }
    }

    @Test("Pausing with nothing playing is harmless and says so")
    func pauseIdle() async {
        await withRegistry { _ in
            #expect(AppModelRegistry.pause() == "Paused.")
        }
    }
}
}

#if !os(macOS)
import KEXPPower
import StationKit

/// Adding the song heard to the playlist, which the Mac cannot do.
extension RegistrySuites {
@Suite("Add song")
@MainActor
struct AddSongTests {
    private func savingModel(_ outcome: SaveOutcome) -> SongSavingModel {
        SongSavingModel(save: { _, _ in outcome }, confirm: { _, _ in outcome }, loadPlaylists: { [] })
    }

    private func withRegistry(saving: SongSavingModel?, _ body: () async -> Void) async {
        let (savedModel, savedSaving, savedArchive) = (AppModelRegistry.model, AppModelRegistry.saving, AppModelRegistry.archive)
        AppModelRegistry.model = ResultRetriever()
        AppModelRegistry.saving = saving
        AppModelRegistry.archive = nil
        await body()
        AppModelRegistry.model = savedModel
        AppModelRegistry.saving = savedSaving
        AppModelRegistry.archive = savedArchive
    }

    @Test("Without the app's saving model it says it is not ready")
    func notReady() async {
        await withRegistry(saving: nil) {
            #expect(await AppModelRegistry.addSong() == AppModelRegistry.notReady)
        }
    }

    @Test("The song on the air is added, and the sentence names the song and the playlist")
    func addsLiveSong() async {
        let wanted = CatalogSong(id: "cat-1", title: "Bleeding Blue", artist: "Cults")
        let kexp = PlaylistSummary(id: "p-kexp", name: "KEXP")
        let saving = savingModel(.finished(wanted, added: [kexp], failed: []))
        await withRegistry(saving: saving) {
            let title = NowPlayingSummary(AppModelRegistry.model?.play).title
            #expect(await AppModelRegistry.addSong() == "Added \(title) to KEXP.")
        }
    }

    @Test("A text match is left for the phone, not guessed at, and the sentence says so")
    func leavesGuessesForThePhone() async {
        let guess = CatalogSong(id: "cat-2", title: "Bleeding Blue (Live)", artist: "Cults")
        let saving = savingModel(.needsConfirmation(guess))
        await withRegistry(saving: saving) {
            let said = await AppModelRegistry.addSong()
            #expect(said.hasSuffix("is held for review on your phone."))
        }
    }
}
}
#endif
