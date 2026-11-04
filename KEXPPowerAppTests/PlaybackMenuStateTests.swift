import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("PlaybackMenuState")
struct PlaybackMenuStateTests {
    @Test("The control says Pause while playing")
    func pauseWhilePlaying() {
        #expect(PlaybackMenuState(isPlaying: true).title == "Pause")
    }

    @Test("The control says Play while paused or stopped")
    func playWhenNotPlaying() {
        #expect(PlaybackMenuState(isPlaying: false).title == "Play")
    }
}
