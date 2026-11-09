import AppIntents
import Foundation
import StationKit
import Testing
@testable import KEXPPowerExampleSwiftUI

/// Playing an archived show by name, through the registry and the entity Siri asks about.
extension RegistrySuites {
@Suite("Play an archived show")
@MainActor
struct PlayArchivedShowTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        return calendar
    }

    private func show(_ id: String, _ program: String, hosts: [String], day: Int, hour: Int) -> StationKit.ArchiveShow {
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour)) ?? .distantPast
        return StationKit.ArchiveShow(
            id: id, programName: program, hostNames: hosts, tagline: nil, imageURL: nil, startTime: start, tags: [])
    }

    /// Runs a body with the registry holding an archive of these shows, then puts it back.
    private func withArchive(
        _ shows: [StationKit.ArchiveShow], loaded: Bool = false, _ body: (ArchiveBrowserModel, FakePlayer, FakeCatalog) async -> Void
    ) async {
        let saved = (AppModelRegistry.model, AppModelRegistry.archive)
        let catalog = FakeCatalog()
        catalog.shows = shows
        catalog.playback = ArchivePlayback(url: URL(string: "https://example.com/a.aac") ?? URL(fileURLWithPath: "/"), offset: 0, nextURL: nil)
        let player = FakePlayer()
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 12)) ?? .now
        let archive = ArchiveBrowserModel(catalog: catalog, player: player, calendar: calendar, now: { now }, songCheckInterval: nil)
        AppModelRegistry.model = ResultRetriever()
        AppModelRegistry.archive = archive
        if loaded { await archive.load() }
        await body(archive, player, catalog)
        AppModelRegistry.model = saved.0
        AppModelRegistry.archive = saved.1
    }

    private var shows: [StationKit.ArchiveShow] {
        [
            show("a", "Positive Vibrations", hosts: ["Kid Hops"], day: 7, hour: 12),
            show("b", "Variety Mix", hosts: ["Morgan"], day: 7, hour: 15),
            show("c", "Variety Mix", hosts: ["Troy Nelson"], day: 6, hour: 18),
        ]
    }

    @Test("Without an archive the entry points say the app is not ready")
    func notReady() async {
        let saved = AppModelRegistry.archive
        AppModelRegistry.archive = nil
        #expect(await AppModelRegistry.playShow(id: "a") == AppModelRegistry.notReady)
        #expect(await AppModelRegistry.showsMatching("variety").isEmpty)
        AppModelRegistry.archive = saved
    }

    @Test("A spoken name loads the archive when it has not been loaded, then finds the shows, newest first")
    func matchingLoadsFirst() async {
        await withArchive(shows) { archive, _, catalog in
            #expect(archive.phase == .idle)
            let found = await AppModelRegistry.showsMatching("variety mix")
            #expect(found.map(\.id) == ["b", "c"])
            #expect(archive.phase == .loaded)
            #expect(catalog.spans.count == 1)
        }
    }

    @Test("Suggestions are the newest shows, without the one on the air, which is not an archive yet")
    func suggestions() async {
        await withArchive(shows, loaded: true) { _, _, _ in
            let found = await AppModelRegistry.suggestedShows()
            #expect(found.map(\.id) == ["a", "c"])
        }
    }

    @Test("Suggestions are not cut short: Shortcuts shows every show the archive holds, so a listener can scroll to one")
    func suggestionsHoldTheWholeArchive() async {
        let many = (0..<40).map { show("s\($0)", "Show \($0)", hosts: ["Host"], day: 2 + $0 / 8, hour: ($0 % 8) * 3) }
        await withArchive(many, loaded: true) { _, _, _ in
            let found = await AppModelRegistry.suggestedShows()
            #expect(found.count == 39)
        }
    }

    @Test("A list that failed to load, or is still loading, is loaded again before matching")
    func reloadsWhenNotLoaded() async {
        await withArchive(shows) { archive, _, catalog in
            catalog.failure = Boom()
            await archive.load()
            #expect(archive.phase != .loaded)
            catalog.failure = nil
            let found = await AppModelRegistry.showsMatching("variety mix")
            #expect(found.map(\.id) == ["b", "c"])
            #expect(await AppModelRegistry.playShow(id: "a").hasPrefix("Playing"))
        }
    }

    @Test("Playing a show by id starts it and says which show and when")
    func playsById() async {
        await withArchive(shows, loaded: true) { archive, player, _ in
            let said = await AppModelRegistry.playShow(id: "a")
            #expect(said.hasPrefix("Playing Positive Vibrations"))
            #expect(archive.nowPlayingShow?.id == "a")
            #expect(player.played.count == 1)
        }
    }

    @Test("A show that is not in the archive any more says so and plays nothing")
    func unknownShow() async {
        await withArchive(shows, loaded: true) { archive, player, _ in
            #expect(await AppModelRegistry.playShow(id: "gone") == "That show is no longer available.")
            #expect(archive.nowPlayingShow == nil)
            #expect(player.played.isEmpty)
        }
    }

    @Test("A show with no audio says it could not be started")
    func noAudio() async {
        await withArchive(shows, loaded: true) { archive, player, catalog in
            catalog.playback = nil
            let said = await AppModelRegistry.playShow(id: "a")
            #expect(said == "That show is no longer available.")
            #expect(player.played.isEmpty)
            #expect(archive.nowPlayingShow == nil)
        }
    }

    @Test("The entity carries what Siri shows: the program, and the hosts and day under it")
    func entity() {
        let entity = ShowEntity(shows[1])
        #expect(entity.id == "b")
        #expect(entity.programName == "Variety Mix")
        #expect(entity.subtitle.contains("Morgan"))
    }

    @Test("The query answers by id and by spoken name")
    func query() async throws {
        try await withArchiveThrowing(shows) {
            let byID = try await ShowEntityQuery().entities(for: ["c", "zzz"])
            #expect(byID.map(\.id) == ["c"])
            let byName = try await ShowEntityQuery().entities(matching: "positive")
            #expect(byName.map(\.id) == ["a"])
            let suggested = try await ShowEntityQuery().suggestedEntities()
            #expect(suggested.map(\.id) == ["a", "c"])
        }
    }

    private func withArchiveThrowing(_ shows: [StationKit.ArchiveShow], _ body: () async throws -> Void) async throws {
        var failure: (any Error)?
        await withArchive(shows, loaded: true) { _, _, _ in
            do { try await body() } catch { failure = error }
        }
        if let failure { throw failure }
    }
}
}
