//
//  LivePlayerBar.swift
//  KEXPPowerExampleSwiftUI
//

import SwiftUI

/// A slim bar for the live stream, shown beneath sections other than Live: a live marker, and play and pause.
///
/// Live has no scrubber or skips, so there is nothing else to offer.
struct LivePlayerBar: View {
    let player: PlayerController

    var body: some View {
        HStack {
            Label("KEXP Live", systemImage: "dot.radiowaves.left.and.right")
                .font(.headline)
                .foregroundStyle(.tint)
            Spacer()
            Button { player.playOrPause() } label: {
                Label(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
