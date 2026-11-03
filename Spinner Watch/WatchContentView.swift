//
//  WatchContentView.swift
//  Spinner Watch
//

import SwiftUI

struct WatchContentView: View {
    let player: WatchPlayer

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showVolume = false
    @State private var volumeChanges = 0

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
        // Leave a lane on the right edge for the volume bar, so nothing sits under it.
        .padding(.leading)
        .padding(.trailing, 18)
        .task { player.start() }
        // The system volume control is kept but invisible: it is what lets the crown change the volume.
        .background { VolumeControlView().frame(width: 1, height: 1).opacity(0.01).accessibilityHidden(true) }
        .overlay(alignment: .trailing) {
            if showVolume {
                VolumeBar(level: player.volume)
                    .padding(.trailing, 4)
                    .zIndex(1)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: showVolume)
        .onChange(of: player.volume) {
            showVolume = true
            volumeChanges += 1
        }
        .task(id: volumeChanges) {
            try? await Task.sleep(for: .seconds(1.5))
            // A newer volume change cancelled this wait; its own timer will hide the bar.
            guard !Task.isCancelled else { return }
            showVolume = false
        }
    }
}
