//
//  NowPlayingPublishing.swift
//  KEXPPowerExampleSwiftUI
//

import MediaPlayer
import UIKit

/// The one place that tells the system what is playing and receives its remote commands.
///
/// Nothing else in the app writes to `MPNowPlayingInfoCenter` or `MPRemoteCommandCenter`.
@MainActor
protocol NowPlayingPublishing: AnyObject {
    func publish(_ snapshot: NowPlayingSnapshot, artwork: UIImage?)
    func installCommands(
        play: @escaping @MainActor @Sendable () -> Void,
        pause: @escaping @MainActor @Sendable () -> Void,
        toggle: @escaping @MainActor @Sendable () -> Void)
}

/// Publishes through `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`.
@MainActor
final class LegacyNowPlayingPublisher: NowPlayingPublishing {
    private var registrations: [(command: MPRemoteCommand, token: Any)] = []

    func publish(_ snapshot: NowPlayingSnapshot, artwork: UIImage?) {
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = snapshot.nowPlayingInfo(artwork: artwork)
        center.playbackState = snapshot.state == .playing ? .playing : .paused
    }

    func installCommands(
        play: @escaping @MainActor @Sendable () -> Void,
        pause: @escaping @MainActor @Sendable () -> Void,
        toggle: @escaping @MainActor @Sendable () -> Void
    ) {
        invalidate()
        let center = MPRemoteCommandCenter.shared()
        registrations = [
            register(center.playCommand, play),
            register(center.pauseCommand, pause),
            register(center.togglePlayPauseCommand, toggle),
        ]
    }

    private func invalidate() {
        for registration in registrations {
            registration.command.removeTarget(registration.token)
        }
        registrations = []
    }

    private func register(
        _ command: MPRemoteCommand,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> (command: MPRemoteCommand, token: Any) {
        command.isEnabled = true
        let token = command.addTarget { _ in
            Task { @MainActor in action() }
            return .success
        }
        return (command, token)
    }
}
