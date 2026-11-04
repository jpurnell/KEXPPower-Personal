//
//  PlayStateExpectation.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// The play state the app has just asked for, so it can be published before the player has caught up.
///
/// Starting a stream takes a second or two. If the widget's button is tapped, the widget reloads straight away and
/// must already be told "playing"; and the app's next poll must not announce "paused" in the gap and undo it. The
/// expectation lasts only a few seconds, after which the player's real state is believed again, so a stream that
/// fails to start is corrected rather than shown as playing.
struct PlayStateExpectation {
    private var playing: Bool?
    private var until = Date.distantPast

    /// Records what the app has just asked the player to do.
    /// - Parameters:
    ///   - playing: Whether it was asked to play (`true`) or pause (`false`).
    ///   - until: When to stop expecting it.
    mutating func expect(playing: Bool, until: Date) {
        self.playing = playing
        self.until = until
    }

    /// The state to publish: the expected one while the expectation is current, otherwise the real one.
    /// - Parameters:
    ///   - actual: Whether the player says it is playing.
    ///   - now: The current time.
    func effective(actual: Bool, at now: Date) -> Bool {
        guard let playing, now < until else { return actual }
        return playing
    }
}
