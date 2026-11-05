import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("ControlPlayState")
struct ControlPlayStateTests {
    @Test("A control sets playback to what was asked, never just flipping it")
    func togglesOnlyWhenTheStateDiffers() {
        // The control may be showing a stale state; asking for "play" while already playing must do nothing.
        #expect(ControlPlayState.shouldToggle(wanted: true, isPlaying: false))
        #expect(ControlPlayState.shouldToggle(wanted: false, isPlaying: true))
        #expect(!ControlPlayState.shouldToggle(wanted: true, isPlaying: true))
        #expect(!ControlPlayState.shouldToggle(wanted: false, isPlaying: false))
    }

    @Test("The value text and symbol follow the state")
    func valueTextAndSymbol() {
        #expect(ControlPlayState.valueText(isPlaying: true) == "Playing")
        #expect(ControlPlayState.valueText(isPlaying: false) == "Paused")
        #expect(ControlPlayState.symbolName(isPlaying: true) == "pause.fill")
        #expect(ControlPlayState.symbolName(isPlaying: false) == "play.fill")
    }

    @Test("VoiceOver hears the station and the state")
    func accessibilityLabel() {
        #expect(ControlPlayState.accessibilityLabel(station: "KEXP", isPlaying: true) == "KEXP, playing")
        #expect(ControlPlayState.accessibilityLabel(station: "KEXP", isPlaying: false) == "KEXP, paused")
    }
}
