//
//  RootView.swift
//  KEXPPowerExampleSwiftUI
//

import SwiftUI

/// The app's frame: a sidebar you can show and hide on the Mac, iPad and Vision Pro, and tabs on the iPhone.
struct RootView: View {
    let model: ResultRetriever

    @Environment(SongSavingModel.self) private var saving
    @State private var selection: AppSection? = AppSection.defaultSection
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
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
            SectionDestination(section: selection ?? AppSection.defaultSection, model: model)
        }
    }

    private var tabLayout: some View {
        TabView(selection: Binding(
            get: { selection ?? AppSection.defaultSection },
            set: { selection = $0 }
        )) {
            ForEach(AppSection.visible(canSaveToPlaylists: AppSongSaver.canSaveToPlaylists)) { section in
                SectionDestination(section: section, model: model)
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

    var body: some View {
        switch section {
        case .live:
            ContentView(resultsRetriever: model)
        case .review:
            ReviewView(model: model)
        case .archive:
            ArchiveView(model: model)
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
