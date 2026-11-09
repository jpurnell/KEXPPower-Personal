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

    /// One column on a phone; as many 320-point columns as fit on an iPad or Mac. On tvOS, whose type is about twice
    /// the size, 520: at 320 a host's name broke a syllable per line.
    #if os(tvOS)
    private static let cardColumns = [GridItem(.adaptive(minimum: 520), spacing: cardSpacing)]
    /// Room between cards for the focused one to lift without covering its neighbours.
    private static let cardSpacing = 48.0
    /// Five columns: the fifteen days fill three even rows, and each tile is wide enough to lift cleanly when focused.
    private static let dayColumns = Array(repeating: GridItem(.flexible(), spacing: 40), count: 5)
    private static let daySpacing = 40.0
    #else
    private static let cardColumns = [GridItem(.adaptive(minimum: 320), spacing: cardSpacing)]
    private static let cardSpacing = 8.0
    private static let dayColumns = [GridItem(.adaptive(minimum: 84), spacing: 12)]
    private static let daySpacing = 12.0
    #endif

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
            #if os(iOS)
            SettingsButton(model: model)
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
        LazyVGrid(columns: Self.dayColumns, spacing: Self.daySpacing) {
            ForEach(browser.tiles) { tile in
                Button {
                    selection = .day(tile.id)
                } label: {
                    DayTileView(tile: tile)
                }
                .archiveTileButtonStyle()
                .disabled(tile.shows.isEmpty)
            }
        }
    }

    private var hostList: some View {
        LazyVGrid(columns: Self.cardColumns, spacing: Self.cardSpacing) {
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
        LazyVGrid(columns: Self.cardColumns, spacing: Self.cardSpacing) {
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
        LazyVGrid(columns: Self.cardColumns, spacing: Self.cardSpacing) {
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

    #if os(tvOS)
    private static let pictureSize = 88.0
    private static let padding = 24.0
    private static let minHeight = 136.0
    #else
    private static let pictureSize = 56.0
    private static let padding = 12.0
    private static let minHeight = 0.0
    #endif

    private var countText: some View {
        Text(count == 1 ? "1 show" : "\(count) shows").font(.caption).foregroundStyle(.secondary)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Self.padding) {
                if imageURL != nil || alwaysShowsPicture { ArchivePicture(url: imageURL, size: Self.pictureSize) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).lineLimit(2)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    #if os(tvOS)
                    // Beneath the name rather than beside it, so the name has the card's width; a focused card lifts,
                    // which says it opens, so there is no chevron.
                    countText
                    #endif
                }
                Spacer(minLength: 0)
                #if !os(tvOS)
                // Never wrapped: the name and its line beneath take what room is short.
                countText.fixedSize()
                Image(systemName: "chevron.forward").foregroundStyle(.tertiary).accessibilityHidden(true)
                #endif
            }
            .padding(Self.padding)
            // As tall as the tallest card in its grid row, so a two-line name does not leave its neighbours short.
            .frame(minHeight: Self.minHeight, maxHeight: .infinity)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .archiveTileButtonStyle()
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// tvOS's card style lifts the tile itself when focused; the plain style drew a second frame around it there.
    @ViewBuilder
    func archiveTileButtonStyle() -> some View {
        #if os(tvOS)
        buttonStyle(.card)
        #else
        buttonStyle(.plain)
        #endif
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

    #if os(tvOS)
    private static let minHeight = 180.0
    private static let verticalPadding = 16.0
    #else
    private static let minHeight = 84.0
    private static let verticalPadding = 0.0
    #endif

    var body: some View {
        VStack(spacing: 2) {
            Text(tile.month).font(.caption.weight(.semibold))
            // One line, shrinking if it must: a wide number ("30" on tvOS) wrapped a digit per line and made its tile taller.
            Text(tile.dayNumber).font(.title.weight(.bold)).lineLimit(1).minimumScaleFactor(0.6)
            Text(tile.weekday).font(.caption)
        }
        .padding(.vertical, Self.verticalPadding)
        .frame(maxWidth: .infinity, minHeight: Self.minHeight)
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
            .contextMenu {
                Button("Play from the start", systemImage: "play.fill") { Task { await browser.play(show) } }
            }
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
    @AppStorage(ShowTimeZone.storageKey) private var storedZone = ShowTimeZone.mine.rawValue
    /// The zone times of day are drawn in, from Settings.
    private var zone: TimeZone { ShowTimeZone.resolve(stored: storedZone).zone }
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
                Text(showsDay ? ArchiveTiming.dayAndClock(show.startTime, zone: zone) : ArchiveTiming.clock(show.startTime, zone: zone))
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
