//
//  RootView.swift
//  KEXPPowerExampleSwiftUI
//

import StationKitAdapterKEXP
import SwiftUI

/// The app's frame: a sidebar you can show and hide on the Mac, iPad and Vision Pro, and tabs on the iPhone.
struct RootView: View {
    let model: ResultRetriever
    /// The archive's browser is made once at launch, so playback can be controlled from any section and from the car.
    let archive: ArchiveBrowserModel

    @Environment(SongSavingModel.self) private var saving
    @State private var selection: AppSection? = AppSection.defaultSection
    #if !os(macOS) && !os(tvOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    init(model: ResultRetriever, archive: ArchiveBrowserModel) {
        self.model = model
        self.archive = archive
    }

    var body: some View {
        layout
    }

    @ViewBuilder
    private var layout: some View {
        #if os(macOS)
        sidebarLayout
        #elseif os(tvOS)
        // A tab bar across the top is how tvOS apps are navigated with the remote.
        tabLayout
        #else
        if horizontalSizeClass == .compact {
            tabLayout
        } else {
            sidebarLayout
        }
        #endif
    }

    private var sidebarLayout: some View {
        NavigationSplitView {
            List(AppSection.visible(canSaveToPlaylists: AppSongSaver.canSaveToPlaylists), selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 240)
        } detail: {
            SectionDestination(section: selection ?? AppSection.defaultSection, model: model, archive: archive)
        }
    }

    /// Whether the player has a tab of its own: on tvOS, once something has played.
    private var showsNowPlaying: Bool {
        #if os(tvOS)
        archive.nowPlayingShow != nil || model.playerController.hasPlayed
        #else
        false
        #endif
    }

    private var tabLayout: some View {
        TabView(selection: Binding(
            get: { selection ?? AppSection.defaultSection },
            set: { selection = $0 }
        )) {
            ForEach(AppSection.visible(canSaveToPlaylists: AppSongSaver.canSaveToPlaylists,
                                       showsNowPlaying: showsNowPlaying)) { section in
                SectionDestination(section: section, model: model, archive: archive)
                    .tabItem { Label(section.title, systemImage: section.systemImage) }
                    #if !os(tvOS)
                    // tvOS tabs take no badge; the Review section shows its own count.
                    .badge(section == .review ? (saving.reviewQueue?.count ?? 0) : 0)
                    #endif
                    .tag(section)
            }
        }
        #if os(tvOS)
        // The remote's Play/Pause button pauses and resumes from anywhere. Here rather than in a section, so it works
        // while focus is in the tab bar, where it is when the app opens.
        .onPlayPauseCommand { model.playerController.playOrPause() }
        // The Top Shelf's Play: the live stream, leaving an archived show if one is playing.
        .onOpenURL { url in
            guard SpinnerLink(url: url) == .playLive else { return }
            selection = .live
            if archive.nowPlayingShow != nil {
                archive.returnToLive()
            } else if !model.playerController.isPlaying {
                model.playerController.playPlayer()
            }
        }
        #endif
    }
}

extension ArchiveBrowserModel {
    /// The archive of KEXP's own recordings, played through the app's player, with days kept in the station's time zone.
    /// - Parameter player: The app's player.
    static func standard(player: any ArchivePlayer) -> ArchiveBrowserModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ArchiveTiming.stationTimeZone
        calendar.locale = .current
        return ArchiveBrowserModel(catalog: KEXPArchiveCatalog(), player: player, calendar: calendar)
    }
}

/// What one section shows.
struct SectionDestination: View {
    let section: AppSection
    let model: ResultRetriever
    let archive: ArchiveBrowserModel

    var body: some View {
        #if os(tvOS)
        // No bar on tvOS. The remote reached a bar beneath a list only past its last row, and a column beside it took
        // the width of every section to show one line, so the player is a section of its own: Now Playing, which Menu
        // and a move along the tab bar reach from anywhere.
        content
        #else
        content
            // Inside each section, not around the whole layout: a tab or split view does not pass the inset on, so a bar
            // there would float over the content instead of making room.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                playerBar
            }
        #endif
    }

    private var playerKind: PlayerBarKind {
        PlayerBarKind.kind(
            archiveShow: archive.nowPlayingShow, liveHasPlayed: model.playerController.hasPlayed,
            isTimeShifted: model.playerController.isTimeShifted, in: section)
    }

    #if !os(tvOS)
    /// The bar for what is playing, on a solid background so it reads as a strip of its own beneath the content, not
    /// as something laid over a list that scrolls beneath it.
    @ViewBuilder
    private var playerBar: some View {
        let kind = playerKind
        if kind != .none {
            VStack(spacing: 0) {
                Divider()
                bar(for: kind)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
            }
            .background(.bar, ignoresSafeAreaEdges: .bottom)
        }
    }
    #endif

    /// - Parameters:
    ///   - kind: Which player.
    ///   - canFold: Whether it offers to fold to its title line; not on a screen of its own.
    @ViewBuilder
    private func bar(for kind: PlayerBarKind, canFold: Bool = true) -> some View {
        switch kind {
        case .archive(let show):
            ArchivePlayerBar(show: show, browser: archive, canFold: canFold)
        case .live:
            LivePlayerBar(player: model.playerController, showsPlayButton: section != .live, canFold: canFold)
        case .none:
            EmptyView()
        }
    }

    /// The Now Playing section: the player, large and unfolded, and for live the song on the air.
    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 40) {
            bar(for: playerKind, canFold: false)
            if playerKind == .live {
                CombinedView(play: model.play)
            }
        }
        .frame(maxWidth: 1200)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 40)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .live:
            ContentView(resultsRetriever: model)
        case .review:
            ReviewView(model: model)
        case .archive:
            ArchiveView(model: model, browser: archive)
        case .nowPlaying:
            nowPlaying
        }
    }
}

#Preview {
    let model = ResultRetriever()
    return RootView(model: model, archive: .standard(player: model.playerController))
        .environment(AppSongSaver.makeModel())
}
