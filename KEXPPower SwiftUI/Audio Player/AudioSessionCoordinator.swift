//
//  AudioSessionCoordinator.swift
//  KEXPPowerExampleSwiftUI
//

import AVFoundation
import Combine
import OSLog

#if os(iOS) || os(visionOS)

    /// Owns the app's audio session: category, activation, and what to do when the system interrupts it.
    @MainActor
    final class AudioSessionCoordinator {
        /// What the player should do in response to a system audio event.
        enum Action: Equatable {
            case none
            case pause
            case resume
        }

        private var observations = Set<AnyCancellable>()
        private let logger = Logger(#function)

        /// The player's response to an interruption such as a phone call.
        /// The system pauses playback itself when one begins; we only resume when it says we may.
        nonisolated static func action(
            forInterruption type: AVAudioSession.InterruptionType,
            options: AVAudioSession.InterruptionOptions
        ) -> Action {
            type == .ended && options.contains(.shouldResume) ? .resume : .none
        }

        /// The player's response to an audio route change. Unplugging headphones pauses, by convention.
        nonisolated static func action(forRouteChange reason: AVAudioSession.RouteChangeReason) -> Action {
            reason == .oldDeviceUnavailable ? .pause : .none
        }

        /// Sets the playback category so audio continues in the background and over AirPlay.
        func configure() {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowAirPlay])
            } catch {
                logger.error("Could not set the playback category: \(error.localizedDescription, privacy: .public)")
            }
        }

        /// Activates the session; call before starting playback.
        func activate() {
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                logger.error("Could not activate the audio session: \(error.localizedDescription, privacy: .public)")
            }
        }

        /// Reports interruptions and route changes to a handler, replacing any earlier handler.
        /// - Parameter handler: Called on the main actor with what the player should do.
        func observe(_ handler: @escaping @MainActor (Action) -> Void) {
            observations.removeAll()
            let center = NotificationCenter.default

            center.publisher(for: AVAudioSession.interruptionNotification)
                .compactMap { note -> Action? in
                    guard
                        let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                        let type = AVAudioSession.InterruptionType(rawValue: raw)
                    else { return nil }
                    let optionBits = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    return Self.action(forInterruption: type, options: .init(rawValue: optionBits))
                }
                .receive(on: DispatchQueue.main)
                .sink { action in MainActor.assumeIsolated { handler(action) } }
                .store(in: &observations)

            center.publisher(for: AVAudioSession.routeChangeNotification)
                .compactMap { note -> Action? in
                    guard
                        let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                        let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
                    else { return nil }
                    return Self.action(forRouteChange: reason)
                }
                .receive(on: DispatchQueue.main)
                .sink { action in MainActor.assumeIsolated { handler(action) } }
                .store(in: &observations)
        }
    }
#endif
