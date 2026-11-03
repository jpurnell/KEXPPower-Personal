//
//  WatchContentView.swift
//  Spinner Watch
//

import SwiftUI

struct WatchContentView: View {
    let player: WatchPlayer

    var body: some View {
        VStack(spacing: 6) {
            if let artwork = player.artwork {
                Image(decorative: artwork, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
            }
            Text(player.title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            if !player.artist.isEmpty {
                Text(player.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Button {
                player.toggle()
            } label: {
                if player.isBuffering {
                    ProgressView()
                } else {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(player.isPlaying ? "Pause" : (player.isBuffering ? "Loading" : "Play"))
            if let notice = player.notice {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .task { player.start() }
    }
}
