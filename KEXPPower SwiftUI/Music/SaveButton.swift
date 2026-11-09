//
//  SaveButton.swift
//  KEXPPowerExampleSwiftUI
//

import KEXPPower
import StationKit
import StationKitAdapterKEXP
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The button on a play that adds the song to the KEXP playlist: a tap adds it, and a press and hold offers another
/// playlist to add it to as well, or a new one.
struct SaveButton: View {
    /// The song, as the saver knows it; `nil` for something that is not a song, which leaves the button doing nothing.
    private let track: Track?

    /// A button for a KEXP play, as on Live.
    init(play: Play?) {
        track = play.flatMap { KEXPMapping.track(from: $0) }
    }

    /// A button for an archived song.
    init(track: Track?) {
        self.track = track
    }

    @Environment(SongSavingModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var showingNewPlaylist = false
    @State private var newPlaylistName = ""

    var body: some View {
        let state = track.map { model.state(for: $0) } ?? .idle
        Menu {
            if model.playlistChoices.isEmpty {
                Text("Other playlists appear after your first save")
            } else {
                ForEach(model.playlistChoices) { playlist in
                    Button(playlist.name) { save(alsoTo: playlist) }
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
            if state.opensSettings { openSettings() } else { save(alsoTo: nil) }
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .disabled(track == nil || state == .saving)
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityHint(state.opensSettings ? "Opens Settings to allow access" : "Touch and hold to add to another playlist")
        .alert("New Playlist", isPresented: $showingNewPlaylist) {
            TextField("Name", text: $newPlaylistName)
            Button("Create") {
                guard let track else { return }
                let name = newPlaylistName
                Task { await model.save(track, toNewPlaylistNamed: name) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The song is added to KEXP and to this playlist.")
        }
        .alert("Is this the song?", isPresented: confirming, presenting: confirmingSong) { song in
            Button("Add") { if let track { Task { await model.confirm(song, for: track) } } }
            Button("Review later") { if let track { Task { await model.holdForReview(song, for: track) } } }
            Button("Not this one", role: .cancel) { if let track { model.dismissConfirmation(for: track) } }
        } message: { song in
            Text(description(of: song))
        }
    }

    /// The song waiting for a yes or no, if the play is in that state.
    private var confirmingSong: CatalogSong? {
        guard let track else { return nil }
        if case .confirming(let song) = model.state(for: track) { return song }
        return nil
    }

    private var confirming: Binding<Bool> {
        Binding(
            get: { confirmingSong != nil },
            set: { if !$0, let track { model.dismissConfirmation(for: track) } })
    }

    /// Opens Spinner's page in Settings, where Apple Music access can be turned back on.
    private func openSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        #endif
    }

    private func save(alsoTo playlist: PlaylistSummary?) {
        guard let track else { return }
        Task { await model.save(track, alsoTo: playlist) }
    }

    private func description(of song: CatalogSong) -> String {
        [song.title, song.artist, song.album].compactMap { $0 }.joined(separator: " — ")
    }
}
