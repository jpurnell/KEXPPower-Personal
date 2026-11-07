//
//  RootView.swift
//  KEXPPowerExampleSwiftUI
//

import StationKitAdapterKEXP
import SwiftUI

/// The app's frame: a sidebar you can show and hide on the Mac, iPad and Vision Pro, and tabs on the iPhone.
struct RootView: View {
    let model: ResultRetriever
    /// The archive's browser lives here rather than in its screen, so playback can be controlled from any section.
    @State private var archive: ArchiveBrowserModel

    @Environment(SongSavingModel.self) private var saving
    @State private var selection: AppSection? = AppSection.defaultSection
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    init(model: ResultRetriever) {
        self.model = model
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ArchiveTiming.stationTimeZone
        calendar.locale = .current
        _archive = State(initialValue: ArchiveBrowserModel(
            catalog: KEXPArchiveCatalog(), player: model.playerController, calendar: calendar))
    }

    var body: some View {
        layout
    }

    @ViewBuilder
    private var layout: some View {
        #if os(macOS)
        sidebarLayout
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

    private var tabLayout: some View {
        TabView(selection: Binding(
            get: { selection ?? AppSection.defaultSection },
            set: { selection = $0 }
        )) {
            ForEach(AppSection.visible(canSaveToPlaylists: AppSongSaver.canSaveToPlaylists)) { section in
                SectionDestination(section: section, model: model, archive: archive)
                    .tabItem { Label(section.title, systemImage: section.systemImage) }
                    .badge(section == .review ? (saving.reviewQueue?.count ?? 0) : 0)
                    .tag(section)
            }
        }
    }
}

/// What one section shows.
struct SectionDestination: View {
    let section: AppSection
    let model: ResultRetriever
    let archive: ArchiveBrowserModel

    var body: some View {
        content
            // Inside each section, not around the whole layout: a tab or split view does not pass the inset on, so a bar
            // there would float over the content instead of making room.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                playerBar
            }
    }

    /// The bar for what is playing, on a solid background so it reads as a strip of its own beneath the content, not
    /// as something laid over a list that scrolls beneath it.
    @ViewBuilder
    private var playerBar: some View {
        let kind = PlayerBarKind.kind(
            archiveShow: archive.nowPlayingShow, liveHasPlayed: model.playerController.hasPlayed, in: section)
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

    @ViewBuilder
    private func bar(for kind: PlayerBarKind) -> some View {
        switch kind {
        case .archive(let show):
            ArchivePlayerBar(show: show, browser: archive)
        case .live:
            LivePlayerBar(player: model.playerController)
        case .none:
            EmptyView()
        }
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
        case .playlists:
            ComingSoonView(section: section)
        }
    }
}

/// The stand-in for a section that is not built yet.
struct ComingSoonView: View {
    let section: AppSection

    var body: some View {
        ContentUnavailableView(
            section.title,
            systemImage: section.systemImage,
            description: Text(section.comingSoonMessage ?? "")
        )
    }
}

#Preview {
    RootView(model: ResultRetriever())
        .environment(AppSongSaver.makeModel())
}
