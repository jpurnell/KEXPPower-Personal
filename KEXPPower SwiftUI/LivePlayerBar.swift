//
//  LivePlayerBar.swift
//  KEXPPowerExampleSwiftUI
//

import SwiftUI

/// A slim bar for the live stream, shown beneath sections other than Live: a live marker, and play and pause.
///
/// When live plays through the recording it also carries the rewind controls; otherwise there is nothing more to offer.
struct LivePlayerBar: View {
    let player: PlayerController
    /// Whether the bar has its own play and pause; the Live screen has a large one already.
    var showsPlayButton = true
    /// Whether the rewind controls show, or only the title line; the bar stays under every section, so it can fold.
    @State private var isExpanded = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label("KEXP Live", systemImage: "dot.radiowaves.left.and.right")
                    .font(.headline)
                    .foregroundStyle(.tint)
                Spacer()
                // With the rewind controls showing, play and pause are among them.
                if showsPlayButton, !player.isTimeShifted || !isExpanded {
                    Button { player.playOrPause() } label: {
                        Label(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                            .labelStyle(.iconOnly)
                            .font(.title2)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                if player.isTimeShifted {
                    Button { withAnimation(reduceMotion ? nil : .default) { isExpanded.toggle() } } label: {
                        Label(isExpanded ? "Show less" : "Show the controls", systemImage: isExpanded ? "chevron.down" : "chevron.up")
                            .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            if player.isTimeShifted, isExpanded {
                LiveRewindControls(player: player, showsPlayButton: showsPlayButton)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, player.isTimeShifted && isExpanded ? 8 : 0)
        .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
