import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

/// Plays nothing; records what it was asked, and the order of those requests across the model's collaborators.
@MainActor
private final class Recorder {
    var events: [String] = []
}

@MainActor
private final class FakeAudio: PreviewAudio {
    let recorder: Recorder
    var onFinish: (@MainActor () -> Void)?
    init(_ recorder: Recorder) { self.recorder = recorder }
    func play(_ url: URL) { recorder.events.append("play \(url.lastPathComponent)") }
    func stop() { recorder.events.append("stop") }
}

@MainActor
private func make(
    urls: [String: URL] = ["a": URL(fileURLWithPath: "/previews/a.m4a"), "b": URL(fileURLWithPath: "/previews/b.m4a")]
) -> (ReviewPreviewModel, FakeAudio, Recorder) {
    let recorder = Recorder()
    let audio = FakeAudio(recorder)
    let model = ReviewPreviewModel(
        audio: audio,
        previewURL: { id in urls[id] },
        pauseStream: { recorder.events.append("pause stream") })
    return (model, audio, recorder)
}

@MainActor
@Suite("ReviewPreviewModel")
struct ReviewPreviewModelTests {
    @Test("Nothing is playing to begin with")
    func idle() {
        let (model, _, _) = make()
        #expect(model.state(for: "a") == .idle)
    }

    @Test("Playing pauses the radio first, then plays the preview, and the row shows playing")
    func playsAfterPausingTheStream() async {
        let (model, _, recorder) = make()
        await model.toggle("a")
        #expect(recorder.events == ["pause stream", "play a.m4a"])
        #expect(model.state(for: "a") == .playing)
    }

    @Test("Pressing the playing row again stops it")
    func togglesOff() async {
        let (model, _, recorder) = make()
        await model.toggle("a")
        await model.toggle("a")
        #expect(recorder.events.last == "stop")
        #expect(model.state(for: "a") == .idle)
    }

    @Test("Playing another row replaces the first; only one plays at a time")
    func oneAtATime() async {
        let (model, _, _) = make()
        await model.toggle("a")
        await model.toggle("b")
        #expect(model.state(for: "a") == .idle)
        #expect(model.state(for: "b") == .playing)
    }

    @Test("A song with no preview says so, plays nothing, and leaves the radio alone")
    func noPreview() async {
        let (model, _, recorder) = make()
        await model.toggle("zzz")
        #expect(model.state(for: "zzz") == .unavailable)
        #expect(recorder.events.isEmpty)
    }

    @Test("When the preview ends the row returns to idle")
    func finishes() async {
        let (model, audio, _) = make()
        await model.toggle("a")
        audio.onFinish?()
        #expect(model.state(for: "a") == .idle)
    }

    @Test("Stopping everything, as when the section is left, silences the preview")
    func stopAll() async {
        let (model, _, recorder) = make()
        await model.toggle("a")
        model.stop()
        #expect(recorder.events.last == "stop")
        #expect(model.state(for: "a") == .idle)
    }
}
