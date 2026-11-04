//
//  MiniPlayerView.swift
//  Spinner Mac
//

import SwiftUI

/// The collapsed window: just what is playing, with play/pause and a way back to the full window.
struct MiniPlayerView: View {
    let model: ResultRetriever

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let summary = NowPlayingSummary(model.play)
        let state = PlaybackMenuState(isPlaying: model.playerController.isPlaying)
        HStack(spacing: 12) {
            ImageView(play: model.play)
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title).font(.headline).lineLimit(2)
                Text(summary.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: model.playerController.playOrPause) {
                Image(systemName: model.playerController.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .resizable()
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.title)
            Button {
                openWindow(id: SceneID.main)
                dismissWindow(id: SceneID.mini)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Show the full window")
            .accessibilityLabel("Show full window")
        }
        .padding(12)
        .frame(minWidth: 320, idealWidth: 380, maxWidth: 560)
        // The window has no title bar, but its top edge is still a safe area (the traffic lights sit in it). The
        // backdrop runs up under it so the whole window is translucent.
        .background {
            if reduceTransparency {
                Rectangle().fill(.background).ignoresSafeArea()
            } else {
                TranslucentWindow().ignoresSafeArea()
            }
        }
        .task { await model.startIfNeeded() }
    }
}
