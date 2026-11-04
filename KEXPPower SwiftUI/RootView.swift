//
//  RootView.swift
//  KEXPPowerExampleSwiftUI
//

import SwiftUI

/// The app's frame: a sidebar you can show and hide on the Mac, iPad and Vision Pro, and tabs on the iPhone.
struct RootView: View {
    let model: ResultRetriever

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
            List(AppSection.allCases, selection: $selection) { section in
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
            ForEach(AppSection.allCases) { section in
                SectionDestination(section: section, model: model)
                    .tabItem { Label(section.title, systemImage: section.systemImage) }
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
        case .archive, .playlists:
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
