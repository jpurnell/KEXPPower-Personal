//
//  SaveButton.swift
//  KEXPPowerExampleSwiftUI
//

import KEXPPower
import StationKit
import SwiftUI

/// The button on a play that adds the song to the KEXP playlist: a tap adds it, and a press and hold offers another
/// playlist to add it to as well, or a new one.
struct SaveButton: View {
    let play: Play

    @Environment(SongSavingModel.self) private var model
    @State private var showingNewPlaylist = false
    @State private var newPlaylistName = ""

    var body: some View {
        let state = model.state(for: play)
        Menu {
            if model.playlistChoices.isEmpty {
                Text("Other playlists appear after your first save")
            } else {
                ForEach(model.playlistChoices) { playlist in
                    Button(playlist.name) { Task { await model.save(play, alsoTo: playlist) } }
                }
            }
            Divider()
            Button("New Playlist…", systemImage: "plus") {
                newPlaylistName = ""
                showingNewPlaylist = true
            }
        } label: {
            Image(systemName: state.symbolName)
                .font(.title2)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        } primaryAction: {
            Task { await model.save(play) }
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .disabled(state == .saving)
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityHint("Touch and hold to add to another playlist")
        .alert("New Playlist", isPresented: $showingNewPlaylist) {
            TextField("Name", text: $newPlaylistName)
            Button("Create") { Task { await model.save(play, toNewPlaylistNamed: newPlaylistName) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The song is added to KEXP and to this playlist.")
        }
        .alert("Is this the song?", isPresented: confirming, presenting: confirmingSong) { song in
            Button("Add") { Task { await model.confirm(song, for: play) } }
            Button("Not this one", role: .cancel) { model.dismissConfirmation(for: play) }
        } message: { song in
            Text(description(of: song))
        }
    }

    /// The song waiting for a yes or no, if the play is in that state.
    private var confirmingSong: CatalogSong? {
        if case .confirming(let song) = model.state(for: play) { return song }
        return nil
    }

    private var confirming: Binding<Bool> {
        Binding(
            get: { confirmingSong != nil },
            set: { if !$0 { model.dismissConfirmation(for: play) } })
    }

    private func description(of song: CatalogSong) -> String {
        [song.title, song.artist, song.album].compactMap { $0 }.joined(separator: " — ")
    }
}
