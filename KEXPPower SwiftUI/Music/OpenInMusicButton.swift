//
//  OpenInMusicButton.swift
//  KEXPPowerExampleSwiftUI
//

#if os(macOS)
import AppKit
import KEXPPower
import SwiftUI

/// The Mac's stand-in for the add button: MusicKit cannot add to a playlist on the Mac, so this opens the song in
/// Music, where the listener adds it.
struct OpenInMusicButton: View {
    let play: Play

    @State private var model = OpenInMusicModel(open: { url in _ = NSWorkspace.shared.open(url) })

    var body: some View {
        let track = play.song ?? "this song"
        Button {
            Task { await model.open(artist: play.artist, track: play.song, album: play.album) }
        } label: {
            Image(systemName: symbolName)
                .font(.title2)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.state == .looking)
        .help("Open in Music")
        .accessibilityLabel(OpenInMusicModel.accessibilityLabel(track: track, state: model.state))
        .accessibilityIdentifier("open-in-music")
    }

    private var symbolName: String {
        switch model.state {
        case .idle: "music.note.list"
        case .looking: "ellipsis.circle"
        case .notFound: "exclamationmark.circle"
        }
    }
}
#endif
