//
//  ArchivePlayerBar.swift
//  KEXPPowerExampleSwiftUI
//

import StationKit
import SwiftUI

/// The player for an archived show, shown over every section of the app while one plays: where you are in it, play and pause, a short rewind and a longer skip forward,
/// and a way to catch up to the live stream.
struct ArchivePlayerBar: View {
    @AppStorage(ShowTimeZone.storageKey) private var storedZone = ShowTimeZone.mine.rawValue
    /// The zone times of day are drawn in, from Settings.
    private var zone: TimeZone { ShowTimeZone.resolve(stored: storedZone).zone }
    let show: ArchiveShow
    let browser: ArchiveBrowserModel
    /// Whether it offers to fold to its title line; not when it is a screen of its own (tvOS's Now Playing).
    var canFold = true
    /// The scrubber's value while a finger is on it, so the clock does not fight the drag.
    @State private var dragFraction: Double?
    @State private var showingPlaylist = false
    /// Whether the scrubber and controls show, or only the title line; the bar stays over every section, so it can fold.
    @State private var isExpanded = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(tvOS)
    @FocusState private var timelineFocused: Bool
    #endif

    /// Space between the title line, the timeline and the controls. tvOS lifts a focused button by about a tenth of
    /// its size, and at 8 the lifted Catch-up button covered the timeline.
    /// And the card's own inset, so a lifted button at its edge stays inside it.
    #if os(tvOS)
    private static let rowSpacing = 32.0
    private static let inset = 32.0
    private static let clockSpacing = 12.0
    #else
    private static let rowSpacing = 8.0
    private static let inset = 16.0
    private static let clockSpacing = 2.0
    #endif

    var body: some View {
        VStack(spacing: Self.rowSpacing) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Playing from the archive").font(.caption).foregroundStyle(.secondary)
                    Text(show.programName).font(.headline)
                    // The song being heard, from the show's playlist against the playhead.
                    if let song = browser.heardTrack {
                        Text(song.displayArtist.isEmpty ? song.title : "\(song.title) · \(song.displayArtist)")
                            .font(.subheadline)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !isExpanded {
                    Button { browser.togglePause() } label: {
                        Label(browser.isPlaying ? "Pause" : "Play", systemImage: browser.isPlaying ? "pause.fill" : "play.fill")
                            .labelStyle(.iconOnly).font(.title2).frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    browser.returnToLive()
                } label: {
                    Label("Catch up to live", systemImage: "bolt.fill")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityHint("Stops the archive and plays the live stream")
                if canFold {
                    Button { withAnimation(reduceMotion ? nil : .default) { isExpanded.toggle() } } label: {
                        Label(isExpanded ? "Show less" : "Show the player", systemImage: isExpanded ? "chevron.down" : "chevron.up")
                            .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            if isExpanded {
                if let note = browser.truncationNote {
                    Text(note).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
                if let transport = browser.transport {
                    scrubber(transport)
                }
                controls
            }
        }
        .padding(Self.inset)
        .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showingPlaylist) { ArchivePlaylistView(show: show, browser: browser) }
    }

    /// The scrubber and its two clocks, redrawn twice a second by a timeline rather than by observation, so the
    /// rest of the screen is not redrawn with it.
    private func scrubber(_ transport: ArchiveTransport) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let fileTime = browser.fileTime
            let shown = dragFraction ?? transport.fraction(atFileTime: fileTime)
            let shownFileTime = transport.lowerBound + shown * transport.length
            VStack(spacing: Self.clockSpacing) {
                #if os(tvOS)
                // tvOS has no slider. Focus the bar and press left or right on the remote: the same moves as the skip
                // buttons, back 15 seconds and forward 30.
                ProgressView(value: shown)
                    // A progress bar has no focus effect of its own; without this, nothing showed it was focused.
                    .tint(timelineFocused ? Color.primary : Color.secondary)
                    .scaleEffect(x: 1, y: timelineFocused ? 2 : 1)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(Capsule().fill(Color.primary.opacity(timelineFocused ? 0.18 : 0)))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: timelineFocused)
                    .focusable()
                    .focused($timelineFocused)
                    .onMoveCommand { direction in
                        switch direction {
                        case .left: Task { await browser.skip(by: -15) }
                        case .right: Task { await browser.skip(by: 30) }
                        default: break
                        }
                    }
                    .accessibilityLabel("Position in the show")
                    .accessibilityValue("\(transport.elapsedText(atFileTime: shownFileTime)) of \(ArchiveTiming.positionText(transport.length))")
                #else
                Slider(
                    value: Binding(get: { shown }, set: { dragFraction = $0 }),
                    in: 0...1
                ) { editing in
                    guard !editing, let fraction = dragFraction else { return }
                    dragFraction = nil
                    Task { await browser.scrub(toFraction: fraction) }
                }
                .accessibilityLabel("Position in the show")
                .accessibilityValue("\(transport.elapsedText(atFileTime: shownFileTime)) of \(ArchiveTiming.positionText(transport.length))")
                #endif
                HStack {
                    Text(transport.elapsedText(atFileTime: shownFileTime))
                    Spacer()
                    if let aired = browser.airTime(atFileTime: shownFileTime) {
                        // What the clock on the studio wall read, for finding "the thing at 12:15".
                        Text(ArchiveTiming.clock(aired, zone: zone)).foregroundStyle(.primary)
                    }
                    Spacer()
                    Text(transport.remainingText(atFileTime: shownFileTime))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 32) {
            Button { Task { await browser.skip(by: -15) } } label: {
                Label("Back 15 seconds", systemImage: "gobackward.15").labelStyle(.iconOnly).font(.title2)
            }
            .disabled(browser.transport == nil)
            Button { browser.togglePause() } label: {
                Label(browser.isPlaying ? "Pause" : "Play", systemImage: browser.isPlaying ? "pause.fill" : "play.fill")
                    .labelStyle(.iconOnly).font(.largeTitle)
            }
            Button { Task { await browser.skip(by: 30) } } label: {
                Label("Forward 30 seconds", systemImage: "goforward.30").labelStyle(.iconOnly).font(.title2)
            }
            .disabled(browser.transport == nil)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            Button { showingPlaylist = true } label: {
                Label("Playlist", systemImage: "list.bullet").labelStyle(.iconOnly).font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(browser.transport == nil)
            .accessibilityHint("Shows the songs of this show, to jump to one")
        }
    }
}

/// The songs of the show being heard, with the one on now marked; choosing one jumps to it.
private struct ArchivePlaylistView: View {
    @Environment(\.dismiss) private var dismiss
    let show: ArchiveShow
    let browser: ArchiveBrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Playlist").font(.title2.weight(.bold))
                    Text(show.programName).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()
            content
        }
        // The same show may roll into the next while this is open; its songs are fetched when it does.
        .task(id: browser.nowPlayingShow?.id) { await browser.loadTracks() }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #elseif os(tvOS)
        // A tvOS sheet is as large as its content, and a list has no size of its own: without this it was the title
        // line and the top of the spinner.
        .frame(width: 1200, height: 820)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch browser.tracksState {
        case .idle, .loading:
            ProgressView("Loading the playlist…").frame(maxWidth: .infinity, minHeight: 200)
        case .failed:
            ContentUnavailableView {
                Label("Playlist unavailable", systemImage: "wifi.exclamationmark")
            } actions: {
                Button("Try again") { Task { await browser.loadTracks() } }
            }
        case .loaded:
            if browser.tracks.isEmpty {
                ContentUnavailableView {
                    Label("No playlist for this show", systemImage: "music.note.list")
                } description: {
                    Text("KEXP has no songs logged for it.")
                }
            } else {
                trackList
            }
        }
    }

    private var trackList: some View {
        ScrollViewReader { proxy in
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let current = browser.currentTrack(atFileTime: browser.fileTime)?.id
                List(browser.tracks) { track in
                    HStack {
                        let playable = browser.isPlayable(track)
                        Button {
                            Task {
                                await browser.seek(to: track)
                                dismiss()
                            }
                        } label: {
                            TrackRow(track: track, isCurrent: track.id == current, isRecorded: playable)
                        }
                        .buttonStyle(.plain)
                        .disabled(!playable)
                        // Beside the jump button, not inside it, so a tap on either does one thing.
                        if AppSongSaver.canSaveToPlaylists, SongSavingModel.canSave(track) {
                            SaveButton(track: track)
                        }
                    }
                    .id(track.id)
                }
                .onAppear {
                    if let current { proxy.scrollTo(current, anchor: .center) }
                }
            }
        }
    }
}

private struct TrackRow: View {
    @AppStorage(ShowTimeZone.storageKey) private var storedZone = ShowTimeZone.mine.rawValue
    /// The zone times of day are drawn in, from Settings.
    private var zone: TimeZone { ShowTimeZone.resolve(stored: storedZone).zone }
    let track: Track
    let isCurrent: Bool
    /// Whether the song is in the part of the show that was recorded; if not, it cannot be played.
    var isRecorded = true

    /// Room for "12:03:14 AM EST" on one line; tvOS's caption type is about twice the size.
    #if os(tvOS)
    private static let clockWidth = 220.0
    #else
    private static let clockWidth = 96.0
    #endif

    var body: some View {
        HStack(spacing: 12) {
            if let aired = track.airDate {
                Text(ArchiveTiming.clock(aired, zone: zone)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(width: Self.clockWidth, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.headline)
                if !track.displayArtist.isEmpty { Text(track.displayArtist).font(.subheadline) }
            }
            Spacer()
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint).accessibilityHidden(true)
            } else if !isRecorded {
                Text("Not recorded").font(.caption).foregroundStyle(.secondary)
            }
        }
        .opacity(isRecorded ? 1 : 0.5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isCurrent ? "Playing" : (isRecorded ? "" : "Not recorded"))
        .accessibilityHint(isRecorded ? "Jumps to this song" : "This part of the show was not recorded")
    }
}
