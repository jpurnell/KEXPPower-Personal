//
//  LiveRewindControls.swift
//  KEXPPowerExampleSwiftUI
//

import SwiftUI

/// The controls for a live stream that can be paused and rewound: where you are in the last few minutes, the time of day
/// being heard, a way back to live, and back 5 minutes, back 15 seconds, play and pause, and forward 30 seconds.
///
/// It shows nothing unless live is playing through the recording, so a caller can place it unconditionally.
struct LiveRewindControls: View {
    @AppStorage(ShowTimeZone.storageKey) private var storedZone = ShowTimeZone.mine.rawValue
    /// The zone times of day are drawn in, from Settings.
    private var zone: TimeZone { ShowTimeZone.resolve(stored: storedZone).zone }
    let player: PlayerController
    /// Whether the row includes play and pause; the Live screen already has a large one of its own.
    var showsPlayButton = true
    /// The scrubber's value while a finger is on it, so the clock does not fight the drag.
    @State private var dragFraction: Double?

    var body: some View {
        if player.isTimeShifted {
            // Redrawn twice a second by a timeline rather than by observation, so the screen around it is not.
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                if let window = player.liveWindow {
                    VStack(spacing: 8) {
                        scrubber(window)
                        controls
                    }
                }
            }
        }
    }

    private func scrubber(_ window: LiveWindow) -> some View {
        let shown = dragFraction ?? window.fraction
        return VStack(spacing: 2) {
            #if os(tvOS)
            // tvOS has no slider. Focus the bar and press left or right on the remote: the same moves as the skip
            // buttons, back 15 seconds and forward 30.
            ProgressView(value: shown)
                .focusable()
                .onMoveCommand { direction in
                    switch direction {
                    case .left: Task { await player.skipLive(by: -PlayerController.skipBack) }
                    case .right: Task { await player.skipLive(by: PlayerController.skipForward) }
                    default: break
                    }
                }
                .accessibilityLabel("Position in the last few minutes")
                .accessibilityValue(window.isLive ? "Live" : "\(ArchiveTiming.positionText(window.behindLive)) behind live")
            #else
            Slider(
                value: Binding(get: { shown }, set: { dragFraction = $0 }),
                in: 0...1
            ) { editing in
                guard !editing, let fraction = dragFraction else { return }
                dragFraction = nil
                Task { await player.scrubLive(toFraction: fraction) }
            }
            .accessibilityLabel("Position in the last few minutes")
            .accessibilityValue(window.isLive ? "Live" : "\(ArchiveTiming.positionText(window.behindLive)) behind live")
            #endif
            HStack {
                Text(window.behindText)
                    .foregroundStyle(window.isLive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                Spacer()
                if !window.isLive {
                    // What the clock read when the music being heard was broadcast, for finding "the thing a minute ago".
                    Text(ArchiveTiming.clock(Date().addingTimeInterval(-window.behindLive), zone: zone))
                    Spacer()
                    Button { Task { await player.catchUpToLive() } } label: {
                        Label("Catch up to live", systemImage: "bolt.fill")
                            .labelStyle(.iconOnly)
                            .font(.title3)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .accessibilityHint("Skips ahead to the live broadcast")
                }
            }
            .font(.caption.monospacedDigit())
            .accessibilityHidden(true)
        }
    }

    private var controls: some View {
        HStack(spacing: 28) {
            Button { Task { await player.rewindLive() } } label: {
                VStack(spacing: 0) {
                    Image(systemName: "gobackward").font(.title2)
                    Text(stepText).font(.caption2)
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Back \(stepText)")
            }
            Button { Task { await player.skipLive(by: -PlayerController.skipBack) } } label: {
                Label("Back 15 seconds", systemImage: "gobackward.15").labelStyle(.iconOnly).font(.title2)
                    .frame(minWidth: 44, minHeight: 44)
            }
            if showsPlayButton {
                Button { player.playOrPause() } label: {
                    Label(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                        .labelStyle(.iconOnly).font(.largeTitle).frame(minWidth: 44, minHeight: 44)
                }
            }
            Button { Task { await player.skipLive(by: PlayerController.skipForward) } } label: {
                Label("Forward 30 seconds", systemImage: "goforward.30").labelStyle(.iconOnly).font(.title2)
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    /// "5 min", or "2 min" for a shorter window.
    private var stepText: String {
        let minutes = Int((player.rewindStep / 60).rounded())
        return "\(minutes) min"
    }
}
