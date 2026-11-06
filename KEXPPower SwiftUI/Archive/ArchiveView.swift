//
//  ArchiveView.swift
//  KEXPPowerExampleSwiftUI
//

import StationKit
import StationKitAdapterKEXP
import SwiftUI

/// Where archive pictures may come from: KEXP's own media host, as for the live artwork.
private let archiveImageHosts = ArtworkLoader(allowedDomains: ["kexp.org"])

/// The Archive section's Date mode: pick one of the last fifteen days, then a show to hear.
struct ArchiveView: View {
    let model: ResultRetriever
    @State private var browser: ArchiveBrowserModel
    @State private var selectedDay: ArchiveDayTile.ID?
    #if os(iOS) && DEBUG
    @State private var showingProbe = false
    #endif

    init(model: ResultRetriever) {
        self.model = model
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ArchiveTiming.stationTimeZone
        calendar.locale = .current
        _browser = State(initialValue: ArchiveBrowserModel(
            catalog: KEXPArchiveCatalog(), player: model.playerController, calendar: calendar))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let tile = selectedTile {
                DayShowsView(tile: tile, browser: browser)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let show = browser.nowPlayingShow {
                            NowPlayingArchiveBar(show: show) { browser.returnToLive() }
                        }
                        if let notice = browser.notice {
                            Label(notice, systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        content
                    }
                    .padding()
                }
            }
        }
        .task {
            if browser.phase == .idle { await browser.load() }
        }
        #if os(iOS) && DEBUG
        .sheet(isPresented: $showingProbe) { ArchiveProbeView(model: model) }
        #endif
    }

    /// The day being looked at, kept current as the list reloads.
    private var selectedTile: ArchiveDayTile? {
        browser.tiles.first { $0.id == selectedDay }
    }

    private var header: some View {
        HStack {
            if selectedTile != nil {
                Button {
                    selectedDay = nil
                } label: {
                    Label("Dates", systemImage: "chevron.backward")
                }
            }
            Text(selectedTile?.accessibilityLabel ?? "Archive").font(.title2.weight(.bold))
            Spacer()
            #if os(iOS) && DEBUG
            Button("Probe") { showingProbe = true }
            #endif
        }
        .padding(.horizontal)
        .padding(.top)
    }

    @ViewBuilder
    private var content: some View {
        switch browser.phase {
        case .idle, .loading:
            ProgressView("Loading the archive…").frame(maxWidth: .infinity, minHeight: 200)
        case .failed(let message):
            ContentUnavailableView {
                Label("Archive unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await browser.load() } }
            }
        case .loaded:
            Text("Select a date").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 12) {
                ForEach(browser.tiles) { tile in
                    Button {
                        selectedDay = tile.id
                    } label: {
                        DayTileView(tile: tile)
                    }
                    .buttonStyle(.plain)
                    .disabled(tile.shows.isEmpty)
                }
            }
        }
    }
}

/// One day's tile: month, day number and weekday, with today marked.
private struct DayTileView: View {
    let tile: ArchiveDayTile

    var body: some View {
        VStack(spacing: 2) {
            Text(tile.month).font(.caption.weight(.semibold))
            Text(tile.dayNumber).font(.title.weight(.bold))
            Text(tile.weekday).font(.caption)
        }
        .frame(maxWidth: .infinity, minHeight: 84)
        .foregroundStyle(tile.isToday ? Color.black : Color.primary)
        .background(tile.isToday ? Color.yellow : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        .opacity(tile.shows.isEmpty ? 0.4 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.accessibilityLabel)
        .accessibilityHint(tile.shows.isEmpty ? "No shows" : "\(tile.shows.count) shows")
    }
}

/// The shows on one day, in the order they aired; tapping one plays it.
private struct DayShowsView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let tile: ArchiveDayTile
    let browser: ArchiveBrowserModel

    var body: some View {
        List(tile.shows) { show in
            Button {
                Task { await browser.play(show) }
            } label: {
                ShowRow(show: show, isPlaying: browser.nowPlayingShow?.id == show.id)
            }
            .buttonStyle(.plain)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let show = browser.nowPlayingShow {
                    NowPlayingArchiveBar(show: show) { browser.returnToLive() }
                }
                if let notice = browser.notice {
                    Text(notice).font(.callout)
                }
            }
            .padding(.horizontal)
            .frame(maxWidth: .infinity)
            .background(reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.regularMaterial))
        }
    }
}

private struct ShowRow: View {
    let show: ArchiveShow
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            picture
            VStack(alignment: .leading, spacing: 2) {
                Text(show.programName).font(.headline)
                if !show.hostNames.isEmpty {
                    Text(ListFormatter.localizedString(byJoining: show.hostNames)).font(.subheadline)
                }
                Text(ArchiveTiming.clock(show.startTime)).font(.caption).foregroundStyle(.secondary)
                if let tagline = show.tagline {
                    Text(tagline).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            if isPlaying {
                Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint).accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isPlaying ? "Playing" : "")
        .accessibilityHint("Plays this show")
    }

    @ViewBuilder
    private var picture: some View {
        if let url = show.imageURL, archiveImageHosts.isAllowed(url) {
            AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.2) }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8).fill(.secondary.opacity(0.2)).frame(width: 56, height: 56)
        }
    }
}

/// Shows which archived show is playing, with a way back to the live stream.
private struct NowPlayingArchiveBar: View {
    let show: ArchiveShow
    let backToLive: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Playing from the archive").font(.caption).foregroundStyle(.secondary)
                Text(show.programName).font(.headline)
            }
            Spacer()
            Button("Back to live", action: backToLive).buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
