//
//  CombinedView.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 5/7/24.
//  Copyright © 2024 KEXP. All rights reserved.
//

import SwiftUI
import KEXPPower

/// One play: artwork, details, and a backdrop made from the artwork itself. Tapping expands it.
struct CombinedView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var play: Play?
    var imageURL: String = "https://kexp.org/static/assets/img/kexp_logo.jpg"
    @State var small: Bool = true
    #if os(tvOS)
    @State private var showingDetails = false
    #endif

    private let corner: CGFloat = 12

    /// How wide and tall the expanded details may grow: a Mac window has room for a comfortable line length, and its
    /// page scrolls, so the details are never cut short.
    #if os(macOS)
    private let detailWidth: CGFloat = 720
    private let detailHeight: CGFloat = .infinity
    #else
    private let detailWidth: CGFloat = 340
    private let detailHeight: CGFloat = 400
    #endif

    var body: some View {
        VStack {
            HStack {
                ImageView(play: play ?? .fixture())
                    .frame(
                        minWidth: small ? 120 : 200,
                        idealWidth: small ? 120 : 400,
                        maxWidth: small ? 120 : 400,
                        minHeight: 120,
                        idealHeight: small ? 120 : 400
                    )
                    .padding(small ? [.vertical] : [.all])
                (small ? CompactView(play: play ?? .fixture())
                    .frame(minWidth: 200, maxWidth: .infinity)
                    .padding(.leading)
                    .padding(.vertical) : nil)
            }
            (small ? nil : ExtendedView(play: play ?? .fixture()))
                .frame(
                    minWidth: 200,
                    idealWidth: 200,
                    maxWidth: detailWidth,
                    minHeight: 100,
                    idealHeight: 200,
                    maxHeight: detailHeight,
                    alignment: .center
                )
                .clipped()
                .padding(.bottom, 5).padding(.vertical)
        }
        // Fill the row, so an expanded one is as wide as a collapsed one.
        .frame(maxWidth: .infinity)
        .padding(8)
        .overlay(alignment: .topTrailing) {
            #if os(tvOS)
            // tvOS rows cannot take focus, so the details are a button of their own beside the save button.
            HStack(spacing: 12) {
                // A sheet rather than the row growing in place: an expanded row was taller than the screen and held nothing
                // focusable, so the remote could neither scroll its notes into view nor move past it.
                Button { showingDetails = true } label: {
                    Label("Show details", systemImage: "info.circle")
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                if AppSongSaver.canSaveToPlaylists, let play, SongSavingModel.canSave(play) {
                    SaveButton(play: play)
                }
            }
            // Far enough in that a focused button's lift is not cut off by the row's rounded clip.
            .padding(16)
            #else
            if AppSongSaver.canSaveToPlaylists, let play, SongSavingModel.canSave(play) {
                SaveButton(play: play).padding(4)
            }
            #endif
            #if os(macOS)
            // MusicKit cannot add to a playlist on the Mac, so the button opens the song in Music instead.
            if let play, OpenInMusicModel.canOpen(artist: play.artist, track: play.song) {
                OpenInMusicButton(play: play).padding(4)
            }
            #endif
        }
        .foregroundStyle(.primary)
        .background { backdrop }
        .clipShape(RoundedRectangle(cornerRadius: corner))
        // The tap goes on the finished row, background and all. Attached to the content before the background, a row
        // inside a Mac scroll view answered clicks only in its top half (measured: taps 31 and 63 pt down fired, 85 pt
        // and deeper did not); here it answers anywhere in the row. Links and buttons inside still take their own clicks.
        .contentShape(Rectangle())
        #if !os(tvOS)
        // Not on tvOS: there the row cannot take focus, and a tap gesture on it caught Select pressed on the save
        // button inside, so the remote expanded the row instead of adding the song.
        .onTapGesture { small.toggle() }
        #endif
        #if os(macOS)
        // A gesture is not a control, so the row asks for keyboard focus itself: Tab reaches it and Return expands it.
        // Space stays the Playback menu's play/pause.
        .focusable(interactions: .activate)
        .onKeyPress(.return) {
            small.toggle()
            return .handled
        }
        #endif
        // One element that contains the row's parts, so the identifier names the row without overwriting its children's.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("song-row")
        .accessibilityAction(named: small ? "Show details" : "Hide details") { small.toggle() }
        #if os(tvOS)
        .sheet(isPresented: $showingDetails) { PlayDetailsSheet(play: play ?? .fixture()) }
        #endif
    }

    /// The artwork, blurred, under a material. Clipped to the row so it can never spill onto neighbouring views.
    private var backdrop: some View {
        ZStack {
            Color.clear
                .overlay {
                    ImageView(play: play ?? .fixture())
                        .scaledToFill()
                        .blur(radius: reduceTransparency ? 0 : 20)
                }
                .clipped()
            Rectangle()
                .fill(reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.ultraThinMaterial))
        }
    }
}

#if os(tvOS)
/// A play's details on a TV: the artwork beside the song, artist, album and the DJ's notes. Menu closes it.
private struct PlayDetailsSheet: View {
    let play: Play

    var body: some View {
        HStack(alignment: .top, spacing: 60) {
            ImageView(play: play)
                .frame(width: 420, height: 420)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(play.song ?? "Airbreak").font(.title2.weight(.semibold))
                    if let artist = play.artist, !artist.isEmpty { Text(artist).font(.title3) }
                    if let album = play.album, !album.isEmpty { Text(album).foregroundStyle(.secondary) }
                    let released = [play.releaseDate, play.labels?.joined(separator: ", ")]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                    if !released.isEmpty { Text(released).font(.callout).foregroundStyle(.secondary) }
                    // One focusable paragraph at a time, so the remote can scroll through notes longer than the sheet;
                    // text that cannot take focus cannot be scrolled to.
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(MusicLinks.linkedComment(paragraph))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .focusable()
                    }
                }
                .padding(.vertical)
            }
        }
        .padding(60)
        .frame(width: 1400, height: 800)
    }

    private var paragraphs: [String] {
        (play.comment ?? "").split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
#endif

#Preview(traits: .sizeThatFitsLayout) {
    CombinedView(play: .fixture())
        .environment(AppSongSaver.makeModel())
}
