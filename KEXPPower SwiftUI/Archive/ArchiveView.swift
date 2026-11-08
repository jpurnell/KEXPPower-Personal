//
//  ArchiveView.swift
//  KEXPPowerExampleSwiftUI
//

import StationKit
import StationKitAdapterKEXP
import SwiftUI

/// Where archive pictures may come from: KEXP's own media host, as for the live artwork.
private let archiveImageHosts = ArtworkLoader(allowedDomains: ["kexp.org"])

/// The Archive section: browse the last two weeks by date, host, show or genre, then pick a show to hear.
struct ArchiveView: View {
    let model: ResultRetriever
    /// Owned by the app's root, so the player outlives this screen.
    let browser: ArchiveBrowserModel
    @State private var selection: ArchiveSelection?
    #if os(iOS) && DEBUG
    @State private var showingProbe = false
    @State private var showingLiveProbe = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let selection {
                ShowListView(
                    shows: browser.shows(for: selection), showsDay: browser.mode != .date, browser: browser)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let notice = browser.notice {
                            Label(notice, systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Picker("Browse by", selection: Bindable(browser).mode) {
                            ForEach(ArchiveMode.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
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
        .sheet(isPresented: $showingLiveProbe) { LiveRewindProbeView(appPlayer: model.playerController) }
        #endif
    }

    /// One column on a phone; as many 320-point columns as fit on an iPad or Mac.
    private static let cardColumns = [GridItem(.adaptive(minimum: 320), spacing: 8)]

    private var header: some View {
        HStack {
            if selection != nil {
                Button {
                    selection = nil
                } label: {
                    Label("\(browser.mode.title)s", systemImage: "chevron.backward")
                }
            }
            Text(selection.map { browser.title(for: $0) } ?? "Archive").font(.title2.weight(.bold))
            Spacer()
            #if os(iOS) && DEBUG
            Button("Probe") { showingProbe = true }
            Button("Live") { showingLiveProbe = true }
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
            switch browser.mode {
            case .date: dateTiles
            case .host: hostList
            case .show: programList
            case .genre: genreList
            }
        }
    }

    private var dateTiles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 12) {
            ForEach(browser.tiles) { tile in
                Button {
                    selection = .day(tile.id)
                } label: {
                    DayTileView(tile: tile)
                }
                .buttonStyle(.plain)
                .disabled(tile.shows.isEmpty)
            }
        }
    }

    private var hostList: some View {
        LazyVGrid(columns: Self.cardColumns, spacing: 8) {
            ForEach(browser.hosts) { host in
                CardButton(
                    title: host.name,
                    subtitle: ListFormatter.localizedString(byJoining: host.programNames),
                    count: host.showCount,
                    imageURL: browser.hostPhoto(named: host.name),
                    alwaysShowsPicture: true
                ) { selection = .host(host.name) }
            }
        }
    }

    private var programList: some View {
        LazyVGrid(columns: Self.cardColumns, spacing: 8) {
            ForEach(browser.programs) { program in
                CardButton(
                    title: program.name,
                    subtitle: [ListFormatter.localizedString(byJoining: program.hostNames),
                               program.tags.joined(separator: ", ")].filter { !$0.isEmpty }.joined(separator: " · "),
                    count: program.showCount,
                    imageURL: program.imageURL
                ) { selection = .program(program.name) }
            }
        }
    }

    private var genreList: some View {
        LazyVGrid(columns: Self.cardColumns, spacing: 8) {
            ForEach(browser.genres) { genre in
                CardButton(title: genre.name, subtitle: "", count: genre.showCount) { selection = .genre(genre.name) }
            }
        }
    }
}

/// A row in the Host, Show or Genre picker: a name, a line beneath it, and how many shows it has.
private struct CardButton: View {
    let title: String
    let subtitle: String
    let count: Int
    var imageURL: URL?
    /// Keeps a picture's place when there is none, so a list of names lines up.
    var alwaysShowsPicture = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if imageURL != nil || alwaysShowsPicture { ArchivePicture(url: imageURL, size: 56) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer()
                Text(count == 1 ? "1 show" : "\(count) shows").font(.caption).foregroundStyle(.secondary)
                Image(systemName: "chevron.forward").foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// A picture from KEXP's own media host, or a plain placeholder.
private struct ArchivePicture: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        if let url, archiveImageHosts.isAllowed(url) {
            AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.2) }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: 8).fill(.secondary.opacity(0.2)).frame(width: size, height: size)
                .accessibilityHidden(true)
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

/// A list of shows (a day's, a host's, a program's or a genre's); tapping one plays it.
private struct ShowListView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shows: [ArchiveShow]
    /// Whether rows say which day too, because the list spans several.
    let showsDay: Bool
    let browser: ArchiveBrowserModel

    var body: some View {
        List(shows) { show in
            Button {
                Task { await browser.play(show) }
            } label: {
                ShowRow(show: show, showsDay: showsDay, isPlaying: browser.nowPlayingShow?.id == show.id)
            }
            .buttonStyle(.plain)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
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
    let showsDay: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            ArchivePicture(url: show.imageURL, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(show.programName).font(.headline)
                if !show.hostNames.isEmpty {
                    Text(ListFormatter.localizedString(byJoining: show.hostNames)).font(.subheadline)
                }
                Text(showsDay ? ArchiveTiming.dayAndClock(show.startTime, zone: .autoupdatingCurrent) : ArchiveTiming.clock(show.startTime, zone: .autoupdatingCurrent))
                    .font(.caption).foregroundStyle(.secondary)
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
}
