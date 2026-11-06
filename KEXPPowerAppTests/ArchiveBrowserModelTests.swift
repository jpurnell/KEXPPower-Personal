import Foundation
import StationKit
import Testing
@testable import KEXPPowerExampleSwiftUI

/// A catalog that answers from fixed data and remembers what it was asked.
// Justification: a test double used from one test at a time; nothing touches it from two tasks at once.
private final class FakeCatalog: ArchiveCatalog, @unchecked Sendable {
    var shows: [ArchiveShow] = []
    var playback: ArchivePlayback?
    var failure: (any Error)?
    private(set) var spans: [(Date, Date)] = []
    private(set) var playbackRequests: [String] = []

    func shows(from start: Date, to end: Date) async throws -> [ArchiveShow] {
        spans.append((start, end))
        if let failure { throw failure }
        return shows
    }

    func playback(for show: ArchiveShow) async throws -> ArchivePlayback? {
        playbackRequests.append(show.id)
        if let failure { throw failure }
        return playback
    }

    func tracks(of show: ArchiveShow) async throws -> [Track] { [] }
}

@MainActor
private final class FakePlayer: ArchivePlayer {
    var isPlayingArchive = false
    private(set) var played: [(URL, TimeInterval)] = []
    private(set) var announced: [NowPlaying] = []
    private(set) var returnedToLive = 0

    func playArchive(url: URL, at offset: TimeInterval) async {
        played.append((url, offset))
        isPlayingArchive = true
    }

    func updateNowPlaying(_ nowPlaying: NowPlaying) async { announced.append(nowPlaying) }

    func returnToLive() {
        returnedToLive += 1
        isPlayingArchive = false
    }
}

private struct Boom: Error {}

@Suite("ArchiveBrowserModel")
@MainActor
struct ArchiveBrowserModelTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    private func show(_ id: String, _ iso: String, program: String = "The Midday Show", hosts: [String] = ["Cheryl Waters"]) throws -> ArchiveShow {
        ArchiveShow(
            id: id, programName: program, hostNames: hosts, tagline: nil,
            imageURL: URL(string: "https://www.kexp.org/media/\(id).jpg"), startTime: try date(iso), tags: [])
    }

    private func model(
        _ catalog: FakeCatalog, _ player: FakePlayer = FakePlayer(), now: String = "2026-11-06T14:00:00-08:00"
    ) throws -> ArchiveBrowserModel {
        let fixed = try date(now)
        return ArchiveBrowserModel(catalog: catalog, player: player, calendar: calendar, now: { fixed })
    }

    // MARK: Tiles

    @Test("Fifteen day tiles, today first, each labelled as the website labels them")
    func tiles() async throws {
        let model = try model(FakeCatalog())
        await model.load()
        #expect(model.tiles.count == 15)
        let today = try #require(model.tiles.first)
        #expect(today.isToday)
        #expect(today.month == "NOV")
        #expect(today.dayNumber == "6")
        #expect(today.weekday == "Fri")
        #expect(today.accessibilityLabel == "November 6, Friday")
        #expect(model.tiles.dropFirst().allSatisfy { !$0.isToday })
        #expect(model.tiles.last?.dayNumber == "23")
        #expect(model.tiles.last?.month == "OCT")
    }

    @Test("The span asked for runs from the start of the oldest tile's day to now")
    func span() async throws {
        let catalog = FakeCatalog()
        let model = try model(catalog)
        await model.load()
        let span = try #require(catalog.spans.first)
        #expect(span.0 == (try date("2026-10-23T00:00:00-07:00")))
        #expect(span.1 == (try date("2026-11-06T14:00:00-08:00")))
    }

    @Test("A day's shows are in the order they aired, and a day with none is empty")
    func dayShows() async throws {
        let catalog = FakeCatalog()
        catalog.shows = [
            try show("3", "2026-11-05T13:00:00-08:00"),
            try show("1", "2026-11-05T07:00:00-08:00", program: "The Morning Show"),
            try show("2", "2026-11-05T10:00:00-08:00"),
        ]
        let model = try model(catalog)
        await model.load()
        let thursday = try #require(model.tiles.first { $0.dayNumber == "5" })
        #expect(thursday.shows.map(\.id) == ["1", "2", "3"])
        #expect(model.tiles.first { $0.dayNumber == "4" }?.shows.isEmpty == true)
    }

    @Test("A show belongs to the day it began on in the station's time zone, not UTC's")
    func dayBoundary() async throws {
        let catalog = FakeCatalog()
        // 23:30 Pacific on the 4th is already the 5th in UTC.
        catalog.shows = [try show("late", "2026-11-04T23:30:00-08:00")]
        let model = try model(catalog)
        await model.load()
        #expect(model.tiles.first { $0.dayNumber == "4" }?.shows.map(\.id) == ["late"])
        #expect(model.tiles.first { $0.dayNumber == "5" }?.shows.isEmpty == true)
    }

    // MARK: Loading

    @Test("A failed load says so, and a later load recovers")
    func loadFailureThenRetry() async throws {
        let catalog = FakeCatalog()
        catalog.failure = Boom()
        let model = try model(catalog)
        await model.load()
        guard case .failed = model.phase else {
            Issue.record("expected a failed phase, got \(model.phase)")
            return
        }
        catalog.failure = nil
        await model.load()
        #expect(model.phase == .loaded)
        #expect(model.tiles.count == 15)
    }

    // MARK: Playing

    @Test("Playing a show asks for its audio, plays the file at the offset, and announces the show")
    func playShow() async throws {
        let catalog = FakeCatalog()
        let file = try #require(URL(string: "https://kexp-archive.streamguys1.com/content/kexp/a.mp3"))
        catalog.playback = ArchivePlayback(url: file, offset: 762, nextURL: nil)
        let player = FakePlayer()
        let model = try model(catalog, player)
        let midday = try show("2", "2026-11-05T10:00:00-08:00", hosts: ["Cheryl Waters", "Kevin Sur"])
        await model.play(midday)
        #expect(catalog.playbackRequests == ["2"])
        #expect(player.played.count == 1)
        #expect(player.played.first?.0 == file)
        #expect(player.played.first?.1 == 762)
        #expect(player.announced == [.program(ProgramInfo(title: "The Midday Show", host: "Cheryl Waters and Kevin Sur", artworkURL: midday.imageURL))])
        #expect(model.nowPlayingShow == midday)
        #expect(model.notice == nil)
    }

    @Test("A show whose audio is no longer kept gives a notice and leaves the player alone")
    func playUnavailable() async throws {
        let catalog = FakeCatalog()
        catalog.playback = nil
        let player = FakePlayer()
        let model = try model(catalog, player)
        await model.play(try show("2", "2026-10-01T10:00:00-07:00"))
        #expect(player.played.isEmpty)
        #expect(player.announced.isEmpty)
        #expect(model.nowPlayingShow == nil)
        #expect(model.notice?.isEmpty == false)
    }

    @Test("A failed request gives a notice, leaves the player alone, and does not drop what was playing")
    func playFails() async throws {
        let catalog = FakeCatalog()
        let file = try #require(URL(string: "https://kexp-archive.streamguys1.com/content/kexp/a.mp3"))
        catalog.playback = ArchivePlayback(url: file, offset: 0, nextURL: nil)
        let player = FakePlayer()
        let model = try model(catalog, player)
        let first = try show("1", "2026-11-05T07:00:00-08:00")
        await model.play(first)
        catalog.failure = Boom()
        await model.play(try show("2", "2026-11-05T10:00:00-08:00"))
        #expect(player.played.count == 1)
        #expect(model.nowPlayingShow == first)
        #expect(model.notice?.isEmpty == false)
    }

    @Test("A later success clears an earlier notice")
    func noticeClears() async throws {
        let catalog = FakeCatalog()
        let model = try model(catalog)
        await model.play(try show("1", "2026-11-05T07:00:00-08:00"))
        #expect(model.notice != nil)
        catalog.playback = ArchivePlayback(url: try #require(URL(string: "https://example.com/a.mp3")), offset: 0, nextURL: nil)
        await model.play(try show("1", "2026-11-05T07:00:00-08:00"))
        #expect(model.notice == nil)
    }

    @Test("Returning to live hands the player back and forgets the show")
    func backToLive() async throws {
        let catalog = FakeCatalog()
        catalog.playback = ArchivePlayback(url: try #require(URL(string: "https://example.com/a.mp3")), offset: 0, nextURL: nil)
        let player = FakePlayer()
        let model = try model(catalog, player)
        await model.play(try show("1", "2026-11-05T07:00:00-08:00"))
        model.returnToLive()
        #expect(player.returnedToLive == 1)
        #expect(model.nowPlayingShow == nil)
    }

    @Test("The show is not reported as playing once the player has gone back to live on its own")
    func playerLeftArchive() async throws {
        let catalog = FakeCatalog()
        catalog.playback = ArchivePlayback(url: try #require(URL(string: "https://example.com/a.mp3")), offset: 0, nextURL: nil)
        let player = FakePlayer()
        let model = try model(catalog, player)
        await model.play(try show("1", "2026-11-05T07:00:00-08:00"))
        player.isPlayingArchive = false
        #expect(model.nowPlayingShow == nil)
    }

    @Test("A screen watching the playing show is told when playback starts, so the Back to live bar appears")
    func playingShowIsObservable() async throws {
        let catalog = FakeCatalog()
        catalog.playback = ArchivePlayback(url: try #require(URL(string: "https://example.com/a.mp3")), offset: 0, nextURL: nil)
        let model = try model(catalog)
        let (changes, signal) = AsyncStream.makeStream(of: Void.self)
        withObservationTracking {
            _ = model.nowPlayingShow
        } onChange: {
            signal.yield()
        }
        await model.play(try show("1", "2026-11-05T07:00:00-08:00"))
        signal.finish()
        var changed = false
        for await _ in changes { changed = true }
        #expect(changed)
    }
}
