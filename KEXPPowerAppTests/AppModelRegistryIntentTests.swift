import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

/// The registry's entry points for Siri and Shortcuts. They share static state, so they run one at a time.
@Suite("AppModelRegistry intents", .serialized)
@MainActor
struct AppModelRegistryIntentTests {
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
