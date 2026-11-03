//
//  WatchContentView.swift
//  Spinner Watch
//

import SwiftUI

struct WatchContentView: View {
    let player: WatchPlayer

    var body: some View {
        VStack(spacing: 6) {
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
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
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
