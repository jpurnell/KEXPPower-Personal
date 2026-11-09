import Foundation
import StationKit
import Testing
@testable import KEXPPowerExampleSwiftUI

/// A catalog that answers from fixed data and remembers what it was asked.
// Justification: a test double used from one test at a time; nothing touches it from two tasks at once.
final class FakeCatalog: ArchiveCatalog, @unchecked Sendable {
    var shows: [ArchiveShow] = []
    var playback: ArchivePlayback?
    var failure: (any Error)?
    var photos: [String: URL] = [:]
    var photosFailure: (any Error)?
    var trackList: [Track] = []
    var tracksFailure: (any Error)?
    private(set) var trackRequests: [String] = []
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

    func tracks(of show: ArchiveShow) async throws -> [Track] {
        trackRequests.append(show.id)
        if let tracksFailure { throw tracksFailure }
        return trackList
    }

    func hostPhotos() async throws -> [String: URL] {
        if let photosFailure { throw photosFailure }
        return photos
    }
}

@MainActor
final class FakePlayer: ArchivePlayer {
    var isPlayingArchive = false
    var isPlaying = false
    var archiveFileTime: TimeInterval = 0
    var archiveFileDuration: TimeInterval = 0
    private(set) var seeks: [TimeInterval] = []
    private(set) var transportControls: ArchiveTransportControls?
    private(set) var playCalls = 0
    private(set) var pauseCalls = 0
    private(set) var played: [(URL, TimeInterval)] = []
    private(set) var announced: [NowPlaying] = []
    private(set) var returnedToLive = 0
    private(set) var provider: (@MainActor () async -> ArchiveContinuation)?
    private(set) var advanced: (@MainActor (ArchiveContinuation) async -> Void)?

    func setContinuation(
        _ provide: (@MainActor () async -> ArchiveContinuation)?,
        advanced: (@MainActor (ArchiveContinuation) async -> Void)?
    ) {
        provider = provide
        self.advanced = advanced
    }

    func playArchive(url: URL, at offset: TimeInterval) async {
        played.append((url, offset))
        isPlayingArchive = true
    }

    func updateNowPlaying(_ nowPlaying: NowPlaying) async { announced.append(nowPlaying) }

    func seekArchive(to seconds: TimeInterval) async { seeks.append(seconds) }
    func setTransportControls(_ controls: ArchiveTransportControls?) { transportControls = controls }
    func playPlayer() { playCalls += 1 }
    func pausePlayer() { pauseCalls += 1 }

    func returnToLive() {
        returnedToLive += 1
        isPlayingArchive = false
    }
}

struct Boom: Error {}

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
        return ArchiveBrowserModel(catalog: catalog, player: player, calendar: calendar, now: { fixed }, songCheckInterval: nil)
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

    // MARK: Continuing

    @Test("The next show is the earliest one that began after this one, across days")
    func nextShow() async throws {
        let catalog = FakeCatalog()
        let a = try show("1", "2026-11-04T22:00:00-08:00")
        let b = try show("2", "2026-11-05T01:00:00-08:00")
        let c = try show("3", "2026-11-05T07:00:00-08:00")
        catalog.shows = [c, a, b]
        let model = try model(catalog)
        await model.load()
        #expect(model.nextShow(after: a)?.id == "2")
        #expect(model.nextShow(after: b)?.id == "3")
        #expect(model.nextShow(after: c) == nil)
    }

    @Test("After a show with a following show that has audio, the plan is to roll into it")
    func continuationShow() async throws {
        let catalog = FakeCatalog()
        let a = try show("1", "2026-11-05T07:00:00-08:00")
        let b = try show("2", "2026-11-05T10:00:00-08:00")
        catalog.shows = [a, b]
        let file = try #require(URL(string: "https://kexp-archive.streamguys1.com/content/kexp/20261105100000-b.mp3"))
        catalog.playback = ArchivePlayback(url: file, offset: 700, nextURL: nil)
        let model = try model(catalog)
        await model.load()
        #expect(await model.continuation(after: a) == .show(b, file))
    }

    @Test("With no following show, the plan is to go live")
    func continuationLive() async throws {
        let catalog = FakeCatalog()
        let a = try show("1", "2026-11-05T07:00:00-08:00")
        catalog.shows = [a]
        let model = try model(catalog)
        await model.load()
        #expect(await model.continuation(after: a) == .live)
    }

    @Test("A following show whose audio is gone, or a failed lookup, means going live rather than silence")
    func continuationFallsBackToLive() async throws {
        let catalog = FakeCatalog()
        let a = try show("1", "2026-11-05T07:00:00-08:00")
        let b = try show("2", "2026-11-05T10:00:00-08:00")
        catalog.shows = [a, b]
        let model = try model(catalog)
        await model.load()
        catalog.playback = nil
        #expect(await model.continuation(after: a) == .live)
        catalog.failure = Boom()
        #expect(await model.continuation(after: a) == .live)
    }

    @Test("Playing a show arms the player to ask what comes next when the file nears its end")
    func playArmsContinuation() async throws {
        let catalog = FakeCatalog()
        let a = try show("1", "2026-11-05T07:00:00-08:00")
        let b = try show("2", "2026-11-05T10:00:00-08:00")
        catalog.shows = [a, b]
        let file = try #require(URL(string: "https://kexp-archive.streamguys1.com/content/kexp/20261105100000-b.mp3"))
        catalog.playback = ArchivePlayback(url: file, offset: 700, nextURL: nil)
        let player = FakePlayer()
        let model = try model(catalog, player)
        await model.load()
        await model.play(a)
        let plan = await player.provider?()
        #expect(plan == .show(b, file))
    }

    @Test("When the player rolls into the next show, it becomes the show playing and is announced")
    func advanceToNextShow() async throws {
        let catalog = FakeCatalog()
        let a = try show("1", "2026-11-05T07:00:00-08:00")
        let b = try show("2", "2026-11-05T10:00:00-08:00", program: "The Midday Show", hosts: ["Kevin Sur"])
        catalog.shows = [a, b]
        let file = try #require(URL(string: "https://kexp-archive.streamguys1.com/content/kexp/20261105100000-b.mp3"))
        catalog.playback = ArchivePlayback(url: file, offset: 700, nextURL: nil)
        let player = FakePlayer()
        let model = try model(catalog, player)
        await model.load()
        await model.play(a)
        await player.advanced?(.show(b, file))
        #expect(model.nowPlayingShow == b)
        #expect(player.announced.last == .program(ProgramInfo(title: "The Midday Show", host: "Kevin Sur", artworkURL: b.imageURL)))
    }

    @Test("When the player rolls into the live stream, no archived show is playing any more")
    func advanceToLive() async throws {
        let catalog = FakeCatalog()
        catalog.playback = ArchivePlayback(url: try #require(URL(string: "https://example.com/a.mp3")), offset: 0, nextURL: nil)
        let player = FakePlayer()
        let model = try model(catalog, player)
        await model.play(try show("1", "2026-11-05T07:00:00-08:00"))
        player.isPlayingArchive = false
        await player.advanced?(.live)
        #expect(model.nowPlayingShow == nil)
    }

    @Test("Going back to live disarms the hand-off")
    func backToLiveDisarms() async throws {
        let catalog = FakeCatalog()
        catalog.playback = ArchivePlayback(url: try #require(URL(string: "https://example.com/a.mp3")), offset: 0, nextURL: nil)
        let player = FakePlayer()
        let model = try model(catalog, player)
        await model.play(try show("1", "2026-11-05T07:00:00-08:00"))
        #expect(player.provider != nil)
        model.returnToLive()
        #expect(player.provider == nil)
        #expect(player.advanced == nil)
    }

    @Test("A following show that is the newest and began within four hours may still be on the air, so the plan is live")
    func continuationStillAiring() async throws {
        let catalog = FakeCatalog()
        let a = try show("1", "2026-11-06T07:00:00-08:00")
        let airing = try show("2", "2026-11-06T10:03:00-08:00")
        catalog.shows = [a, airing]
        catalog.playback = ArchivePlayback(url: try #require(URL(string: "https://example.com/b.mp3")), offset: 0, nextURL: nil)
        // now is 11:00, an hour after the airing show began.
        let model = try model(catalog, now: "2026-11-06T11:00:00-08:00")
        await model.load()
        #expect(await model.continuation(after: a) == .live)
    }

    @Test("A newest following show that began more than four hours ago has ended, so it is rolled into")
    func continuationNewestButEnded() async throws {
        let catalog = FakeCatalog()
        let a = try show("1", "2026-11-06T01:00:00-08:00")
        let late = try show("2", "2026-11-06T04:00:00-08:00")
        catalog.shows = [a, late]
        let file = try #require(URL(string: "https://example.com/b.mp3"))
        catalog.playback = ArchivePlayback(url: file, offset: 0, nextURL: nil)
        let model = try model(catalog, now: "2026-11-06T14:00:00-08:00")
        await model.load()
        #expect(await model.continuation(after: a) == .show(late, file))
    }

    // MARK: Browsing by host, show and genre

    private func browsable() throws -> FakeCatalog {
        let catalog = FakeCatalog()
        catalog.shows = [
            ArchiveShow(id: "1", programName: "The Morning Show", hostNames: ["John Richards"], tagline: nil, imageURL: nil,
                        startTime: try date("2026-11-05T07:00:00-08:00"), tags: ["Rock", "Eclectic"]),
            ArchiveShow(id: "2", programName: "The Midday Show", hostNames: ["Cheryl Waters"], tagline: nil, imageURL: nil,
                        startTime: try date("2026-11-05T10:00:00-08:00"), tags: ["Rock", "Variety Mix"]),
            ArchiveShow(id: "3", programName: "The Midday Show", hostNames: ["Cheryl Waters"], tagline: nil, imageURL: nil,
                        startTime: try date("2026-11-04T10:00:00-08:00"), tags: ["Rock", "Variety Mix"]),
        ]
        return catalog
    }

    @Test("The four ways in, in the order the website offers them")
    func modes() {
        #expect(ArchiveMode.allCases == [.date, .host, .show, .genre])
        #expect(ArchiveMode.allCases.map(\.title) == ["Date", "Host", "Show", "Genre"])
    }

    @Test("The browser opens in Date mode")
    func opensInDate() throws {
        #expect(try model(FakeCatalog()).mode == .date)
    }

    @Test("After loading, hosts, programs and genres are listed with their counts")
    func pickers() async throws {
        let model = try model(try browsable())
        await model.load()
        #expect(model.hosts.map(\.name) == ["Cheryl Waters", "John Richards"])
        #expect(model.hosts.first?.showCount == 2)
        #expect(model.programs.map(\.name) == ["The Midday Show", "The Morning Show"])
        #expect(model.genres.map(\.name) == ["Eclectic", "Rock", "Variety Mix"])
        #expect(model.genres.first { $0.name == "Rock" }?.showCount == 3)
    }

    @Test("A host's picture is found by name once loaded; a host with none has no picture")
    func hostPhotos() async throws {
        let catalog = try browsable()
        let picture = try #require(URL(string: "https://www.kexp.org/media/cheryl.jpg"))
        catalog.photos = ["Cheryl Waters": picture]
        let model = try model(catalog)
        await model.load()
        #expect(model.hostPhoto(named: "Cheryl Waters") == picture)
        #expect(model.hostPhoto(named: "John Richards") == nil)
    }

    @Test("If the pictures cannot be fetched the archive still loads, with placeholders")
    func hostPhotosFailure() async throws {
        let catalog = try browsable()
        catalog.photosFailure = URLError(.notConnectedToInternet)
        let model = try model(catalog)
        await model.load()
        #expect(model.phase == .loaded)
        #expect(model.hosts.count == 2)
        #expect(model.hostPhoto(named: "Cheryl Waters") == nil)
    }

    // MARK: Transport

    private let transportFile = "https://kexp-archive.streamguys1.com/content/kexp/20261105065008-1-1-the-morning-show.mp3"

    /// The Morning Show (7:00, the first of three loaded) playing from a file that holds it from 778 s in; the next
    /// loaded show, the Midday Show, begins three hours later.
    private func playingMorning(duration: TimeInterval = 14_000, fileTime: TimeInterval = 0) async throws
        -> (ArchiveBrowserModel, FakePlayer, FakeCatalog)
    {
        let catalog = try browsable()
        catalog.playback = ArchivePlayback(url: try #require(URL(string: transportFile)), offset: 778, nextURL: nil)
        let player = FakePlayer()
        player.archiveFileDuration = duration
        player.archiveFileTime = fileTime
        let model = try model(catalog, player)
        await model.load()
        let morning = try #require(model.shows(for: .host("John Richards")).first)
        await model.play(morning)
        return (model, player, catalog)
    }

    @Test("The playing show's range runs from its offset in the file to where the next show begins")
    func transportRange() async throws {
        let (model, _, _) = try await playingMorning()
        #expect(model.transport == ArchiveTransport(offset: 778, showLength: 10_800, fileDuration: 14_000))
    }

    @Test("The newest loaded show has no next show, so its range runs to the end of the file")
    func transportNewestShow() async throws {
        let catalog = try browsable()
        catalog.playback = ArchivePlayback(url: try #require(URL(string: transportFile)), offset: 778, nextURL: nil)
        let player = FakePlayer()
        player.archiveFileDuration = 9_000
        let model = try model(catalog, player)
        await model.load()
        let midday = try #require(model.shows(for: .day(try date("2026-11-05T00:00:00-08:00"))).last)
        await model.play(midday)
        #expect(model.transport == ArchiveTransport(offset: 778, showLength: nil, fileDuration: 9_000))
    }

    @Test("With nothing from the archive playing there is no transport")
    func transportNothingPlaying() async throws {
        let model = try model(try browsable())
        await model.load()
        #expect(model.transport == nil)
    }

    @Test("After rolling into the next show its range begins where that show begins in its own file")
    func transportAfterRollOver() async throws {
        let (model, player, _) = try await playingMorning()
        let midday = try #require(model.shows(for: .host("Cheryl Waters")).first)
        let file = try #require(URL(string: "https://kexp-archive.streamguys1.com/content/kexp/20261105095008-2-2-the-midday-show.mp3"))
        await player.advanced?(.show(midday, file))
        // The file began at 9:50:08 and the show at 10:00:00: 592 s in.
        #expect(model.transport?.lowerBound == 592)
    }

    @Test("Skipping back 15 seconds seeks 15 seconds earlier in the file")
    func skipBack() async throws {
        let (model, player, _) = try await playingMorning(fileTime: 2_000)
        await model.skip(by: -15)
        #expect(player.seeks == [1_985])
    }

    @Test("Skipping forward 30 seconds seeks 30 seconds later")
    func skipForward() async throws {
        let (model, player, _) = try await playingMorning(fileTime: 2_000)
        await model.skip(by: 30)
        #expect(player.seeks == [2_030])
    }

    @Test("Skipping forward past the end of the show plays the next show from its start")
    func skipPastEnd() async throws {
        let (model, player, catalog) = try await playingMorning(fileTime: 778 + 10_790)
        await model.skip(by: 30)
        #expect(player.seeks.isEmpty)
        #expect(catalog.playbackRequests == ["1", "2"])
        #expect(model.nowPlayingShow?.id == "2")
    }

    @Test("Skipping forward past the end of the newest show goes back to live")
    func skipPastEndOfNewest() async throws {
        let catalog = try browsable()
        catalog.playback = ArchivePlayback(url: try #require(URL(string: transportFile)), offset: 778, nextURL: nil)
        let player = FakePlayer()
        player.archiveFileDuration = 9_000
        player.archiveFileTime = 8_990
        let model = try model(catalog, player)
        await model.load()
        let midday = try #require(model.shows(for: .day(try date("2026-11-05T00:00:00-08:00"))).last)
        await model.play(midday)
        await model.skip(by: 30)
        #expect(player.returnedToLive == 1)
    }

    @Test("Scrubbing to half way through seeks half the show's length past its start")
    func scrub() async throws {
        let (model, player, _) = try await playingMorning()
        await model.scrub(toFraction: 0.5)
        #expect(player.seeks == [778 + 5_400])
    }

    @Test("Scrubbing to the very end plays the next show")
    func scrubToEnd() async throws {
        let (model, player, catalog) = try await playingMorning()
        await model.scrub(toFraction: 1)
        #expect(player.seeks.isEmpty)
        #expect(catalog.playbackRequests == ["1", "2"])
    }

    @Test("Skipping or scrubbing with nothing from the archive playing does nothing")
    func movesWithNothingPlaying() async throws {
        let player = FakePlayer()
        let model = try model(try browsable(), player)
        await model.load()
        await model.skip(by: 30)
        await model.scrub(toFraction: 0.5)
        #expect(player.seeks.isEmpty)
        #expect(player.returnedToLive == 0)
    }

    @Test("The model reports the player's position in the file and whether it is playing, for the bar to show")
    func reportsPlayerState() async throws {
        let (model, player, _) = try await playingMorning(fileTime: 2_000)
        player.isPlaying = true
        #expect(model.isPlaying)
        #expect(model.fileTime == 2_000)
        player.archiveFileTime = 2_500
        player.isPlaying = false
        #expect(!model.isPlaying)
        #expect(model.fileTime == 2_500)
    }

    // MARK: Time of day and the playlist

    private func track(_ id: String, _ iso: String?, title: String = "A Song") throws -> Track {
        Track(id: id, title: title, credits: [Credit(role: .performer, name: "An Artist")],
              airDate: try iso.map { try date($0) })
    }

    @Test("The time of day being heard is the show's start plus how far into the show the player is")
    func airTime() async throws {
        let (model, _, _) = try await playingMorning()
        // The show began at 7:00:00; 3,725 s into it is 8:02:05.
        #expect(model.airTime(atFileTime: 778 + 3_725) == (try date("2026-11-05T08:02:05-08:00")))
    }

    @Test("With nothing from the archive playing there is no time of day")
    func airTimeNothingPlaying() async throws {
        let model = try model(try browsable())
        await model.load()
        #expect(model.airTime(atFileTime: 100) == nil)
    }

    @Test("The playing show's songs are fetched once it is playing, and those with no air time are left out")
    func loadTracks() async throws {
        let (model, _, catalog) = try await playingMorning()
        catalog.trackList = [
            try track("a", "2026-11-05T07:00:30-08:00"), try track("b", nil), try track("c", "2026-11-05T07:04:00-08:00"),
        ]
        await model.loadTracks()
        #expect(catalog.trackRequests == ["1"])
        #expect(model.tracks.map(\.id) == ["a", "c"])
        #expect(model.tracksState == .loaded)
    }

    @Test("Asking again for the same show's songs does not fetch them again")
    func loadTracksOnce() async throws {
        let (model, _, catalog) = try await playingMorning()
        await model.loadTracks()
        await model.loadTracks()
        #expect(catalog.trackRequests == ["1"])
    }

    @Test("A failed fetch of the songs says so, and asking again tries again")
    func loadTracksFailure() async throws {
        let (model, _, catalog) = try await playingMorning()
        catalog.tracksFailure = Boom()
        await model.loadTracks()
        #expect(model.tracksState == .failed)
        #expect(model.tracks.isEmpty)
        catalog.tracksFailure = nil
        catalog.trackList = [try track("a", "2026-11-05T07:00:30-08:00")]
        await model.loadTracks()
        #expect(model.tracksState == .loaded)
        #expect(model.tracks.count == 1)
    }

    @Test("With nothing from the archive playing no songs are fetched")
    func loadTracksNothingPlaying() async throws {
        let catalog = try browsable()
        let model = try model(catalog)
        await model.load()
        await model.loadTracks()
        #expect(catalog.trackRequests.isEmpty)
        #expect(model.tracksState == .idle)
    }

    @Test("Rolling into the next show clears the songs, so the new show's are fetched")
    func tracksResetOnRollOver() async throws {
        let (model, player, catalog) = try await playingMorning()
        catalog.trackList = [try track("a", "2026-11-05T07:00:30-08:00")]
        await model.loadTracks()
        let midday = try #require(model.shows(for: .host("Cheryl Waters")).first)
        let file = try #require(URL(string: "https://kexp-archive.streamguys1.com/content/kexp/20261105095008-2-2-the-midday-show.mp3"))
        await player.advanced?(.show(midday, file))
        #expect(model.tracks.isEmpty)
        #expect(model.tracksState == .idle)
        await model.loadTracks()
        #expect(catalog.trackRequests == ["1", "2"])
    }

    @Test("Choosing a song seeks to where it aired in the show")
    func seekToTrack() async throws {
        let (model, player, _) = try await playingMorning()
        // Aired at 7:30:00, 1,800 s into a show that begins 778 s into its file.
        await model.seek(to: try track("a", "2026-11-05T07:30:00-08:00"))
        #expect(player.seeks == [778 + 1_800])
    }

    @Test("A song that aired before the show's start seeks to the start of the show")
    func seekToEarlyTrack() async throws {
        let (model, player, _) = try await playingMorning()
        await model.seek(to: try track("a", "2026-11-05T06:58:00-08:00"))
        #expect(player.seeks == [778])
    }

    @Test("A song with no air time cannot be sought to")
    func seekToUndatedTrack() async throws {
        let (model, player, _) = try await playingMorning()
        await model.seek(to: try track("a", nil))
        #expect(player.seeks.isEmpty)
    }

    @Test("The song being heard is the latest one that has aired by this point in the show")
    func currentTrack() async throws {
        let (model, _, catalog) = try await playingMorning()
        catalog.trackList = [
            try track("a", "2026-11-05T07:00:30-08:00"), try track("b", "2026-11-05T07:04:00-08:00"),
            try track("c", "2026-11-05T07:09:00-08:00"),
        ]
        await model.loadTracks()
        #expect(model.currentTrack(atFileTime: 778 + 10) == nil)
        #expect(model.currentTrack(atFileTime: 778 + 250)?.id == "b")
        #expect(model.currentTrack(atFileTime: 778 + 3_000)?.id == "c")
    }

    // MARK: The song follows the timecode

    private func playingWithSongs(fileTime: TimeInterval = 0) async throws -> (ArchiveBrowserModel, FakePlayer) {
        let (model, player, catalog) = try await playingMorning(fileTime: fileTime)
        catalog.trackList = [
            try track("a", "2026-11-05T07:00:30-08:00", title: "First"), try track("b", "2026-11-05T07:04:00-08:00", title: "Second"),
            try track("c", "2026-11-05T07:09:00-08:00", title: "Third"),
        ]
        await model.loadTracks()
        return (model, player)
    }

    @Test("The song heard is announced to the lock screen and the car once the player is past where it aired")
    func announcesSongHeard() async throws {
        let (model, player) = try await playingWithSongs()
        player.archiveFileTime = 778 + 250
        await model.announceCurrentSong()
        #expect(player.announced.last?.track?.id == "b")
    }

    @Test("A song already announced is not announced again")
    func announcesOnce() async throws {
        let (model, player) = try await playingWithSongs()
        player.archiveFileTime = 778 + 250
        await model.announceCurrentSong()
        let count = player.announced.count
        player.archiveFileTime = 778 + 260
        await model.announceCurrentSong()
        #expect(player.announced.count == count)
    }

    @Test("Moving on to the next song, and back to an earlier one, announces each")
    func announcesEachChange() async throws {
        let (model, player) = try await playingWithSongs()
        for (fileTime, expected) in [(778.0 + 250, "b"), (778 + 3_000, "c"), (778 + 100, "a")] {
            player.archiveFileTime = fileTime
            await model.announceCurrentSong()
            #expect(player.announced.last?.track?.id == expected)
        }
    }

    @Test("The song heard is kept for the player bar to show, and follows the playhead")
    func keepsSongHeard() async throws {
        let (model, player) = try await playingWithSongs()
        #expect(model.heardTrack == nil)
        player.archiveFileTime = 778 + 250
        await model.announceCurrentSong()
        #expect(model.heardTrack?.id == "b")
        player.archiveFileTime = 778 + 3_000
        await model.announceCurrentSong()
        #expect(model.heardTrack?.id == "c")
    }

    @Test("Before the first song, and after going back to live, there is no song heard")
    func noSongHeardOutsideSongs() async throws {
        let (model, player) = try await playingWithSongs()
        player.archiveFileTime = 778 + 250
        await model.announceCurrentSong()
        player.archiveFileTime = 778 + 10
        await model.announceCurrentSong()
        #expect(model.heardTrack == nil)
        player.archiveFileTime = 778 + 250
        await model.announceCurrentSong()
        model.returnToLive()
        #expect(model.heardTrack == nil)
    }

    @Test("Before the show's first song the show is announced, not a song")
    func announcesShowBeforeFirstSong() async throws {
        let (model, player) = try await playingWithSongs()
        player.archiveFileTime = 778 + 250
        await model.announceCurrentSong()
        player.archiveFileTime = 778 + 10
        await model.announceCurrentSong()
        guard case .program(let info) = player.announced.last else {
            Issue.record("expected the show")
            return
        }
        #expect(info.title == "The Morning Show")
    }

    @Test("Nothing is announced before the songs have loaded, or when no archived show is playing")
    func announcesNothingWithoutSongs() async throws {
        let (playing, player, _) = try await playingMorning(fileTime: 778 + 250)
        let count = player.announced.count
        await playing.announceCurrentSong()
        #expect(player.announced.count == count)

        let idle = try model(try browsable())
        await idle.announceCurrentSong()
    }

    @Test("While a show plays the model fetches its songs and keeps announcing the one heard, with no screen asking")
    func followsOnItsOwn() async throws {
        let catalog = try browsable()
        catalog.playback = ArchivePlayback(url: try #require(URL(string: transportFile)), offset: 778, nextURL: nil)
        catalog.trackList = [try track("a", "2026-11-05T07:00:30-08:00", title: "First")]
        let player = FakePlayer()
        player.archiveFileDuration = 14_000
        player.archiveFileTime = 778 + 100
        let fixed = try date("2026-11-06T14:00:00-08:00")
        let model = ArchiveBrowserModel(
            catalog: catalog, player: player, calendar: calendar, now: { fixed }, songCheckInterval: .milliseconds(10))
        await model.load()
        let morning = try #require(model.shows(for: .host("John Richards")).first)
        await model.play(morning)
        for _ in 0..<200 where player.announced.last?.track == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(player.announced.last?.track?.id == "a")
        model.returnToLive()
    }

    // MARK: System transport controls

    @Test("While an archived show plays the player is given controls for the lock screen and the car")
    func providesTransportControls() async throws {
        let (_, player, _) = try await playingMorning()
        #expect(player.transportControls != nil)
    }

    @Test("Going back to live takes the controls away")
    func removesTransportControlsOnLive() async throws {
        let (model, player, _) = try await playingMorning()
        model.returnToLive()
        #expect(player.transportControls == nil)
    }

    @Test("Rolling onto the live stream takes the controls away; rolling into the next show keeps them")
    func transportControlsOnRollOver() async throws {
        let (model, player, _) = try await playingMorning()
        let midday = try #require(model.shows(for: .host("Cheryl Waters")).first)
        let file = try #require(URL(string: "https://kexp-archive.streamguys1.com/content/kexp/20261105095008-2-2-the-midday-show.mp3"))
        await player.advanced?(.show(midday, file))
        #expect(player.transportControls != nil)
        await player.advanced?(.live)
        #expect(player.transportControls == nil)
    }

    @Test("The timeline is how far into the show the player is and how long the show is, not file times")
    func timeline() async throws {
        let (model, _, _) = try await playingMorning(fileTime: 778 + 125)
        #expect(model.timeline() == PlaybackTimeline(elapsed: 125, duration: 10_800))
    }

    @Test("With nothing from the archive playing there is no timeline")
    func timelineNothingPlaying() async throws {
        let model = try model(try browsable())
        await model.load()
        #expect(model.timeline() == nil)
    }

    @Test("A skip from the system moves the player the same way as the on-screen button")
    func systemSkip() async throws {
        let (model, player, _) = try await playingMorning(fileTime: 2_000)
        await player.transportControls?.skip(-15)
        #expect(player.seeks == [1_985])
        withExtendedLifetime(model) {}
    }


    @Test("A scrub from the system seeks to that position in the show")
    func systemSeek() async throws {
        let (model, player, _) = try await playingMorning()
        await player.transportControls?.seek(3_600)
        #expect(player.seeks == [778 + 3_600])
        withExtendedLifetime(model) {}
    }


    @Test("The timeline the controls report follows the player's place in the show")
    func controlsTimeline() async throws {
        let (model, player, _) = try await playingMorning(fileTime: 778 + 60)
        #expect(player.transportControls?.timeline() == PlaybackTimeline(elapsed: 60, duration: 10_800))
        player.archiveFileTime = 778 + 90
        #expect(player.transportControls?.timeline() == PlaybackTimeline(elapsed: 90, duration: 10_800))
        withExtendedLifetime(model) {}
    }


    // MARK: A recording shorter than its show

    /// A song that aired 74 minutes into the Morning Show, which begins at 7:00.
    private func lateTrack() throws -> Track { try track("late", "2026-11-05T08:14:00-08:00") }

    @Test("Choosing a song past the end of a truncated recording says so, and stays where it is, rather than rolling on")
    func seekPastRecording() async throws {
        // The file holds 20 minutes of the show: 778 + 1,222 s.
        let (model, player, catalog) = try await playingMorning(duration: 778 + 1_222)
        await model.seek(to: try lateTrack())
        #expect(player.seeks.isEmpty)
        #expect(catalog.playbackRequests == ["1"])
        #expect(model.nowPlayingShow?.id == "1")
        #expect(model.notice == "That song is past the end of this recording.")
    }

    @Test("A song in the recorded part is playable; one past its end, or with no air time, is not")
    func isPlayable() async throws {
        let (model, _, _) = try await playingMorning(duration: 778 + 1_222)
        #expect(model.isPlayable(try track("early", "2026-11-05T07:10:00-08:00")))
        #expect(!model.isPlayable(try lateTrack()))
        #expect(!model.isPlayable(try track("undated", nil)))
    }

    @Test("A recording shorter than its show carries a note saying how much was recorded")
    func truncationNote() async throws {
        let (truncated, _, _) = try await playingMorning(duration: 778 + 1_222)
        #expect(truncated.truncationNote == "Only the first 20:22 of this show was recorded.")
        let (full, _, _) = try await playingMorning()
        #expect(full.truncationNote == nil)
    }

    @Test("The play button pauses what is playing, and plays what is paused")
    func togglePause() async throws {
        let (model, player, _) = try await playingMorning()
        player.isPlaying = true
        model.togglePause()
        #expect(player.pauseCalls == 1)
        player.isPlaying = false
        model.togglePause()
        #expect(player.playCalls == 1)
    }

    @Test("A selection means the shows of that host, program, genre or day")
    func selections() async throws {
        let model = try model(try browsable())
        await model.load()
        #expect(model.shows(for: .host("Cheryl Waters")).map(\.id) == ["2", "3"])
        #expect(model.shows(for: .program("The Morning Show")).map(\.id) == ["1"])
        #expect(model.shows(for: .genre("variety mix")).map(\.id) == ["2", "3"])
        let thursday = try #require(model.tiles.first { $0.dayNumber == "5" })
        #expect(model.shows(for: .day(thursday.id)).map(\.id) == ["1", "2"])
        #expect(model.shows(for: .host("Nobody")).isEmpty)
        #expect(model.shows(for: .day(Date(timeIntervalSince1970: 0))).isEmpty)
    }

    @Test("A selection has a title to put at the top of its list")
    func selectionTitles() async throws {
        let model = try model(try browsable())
        await model.load()
        let thursday = try #require(model.tiles.first { $0.dayNumber == "5" })
        #expect(model.title(for: .day(thursday.id)) == "November 5, Thursday")
        #expect(model.title(for: .host("Cheryl Waters")) == "Cheryl Waters")
        #expect(model.title(for: .program("The Midday Show")) == "The Midday Show")
        #expect(model.title(for: .genre("variety mix")) == "Variety Mix")
    }

    @Test("Reloading replaces the pickers rather than adding to them")
    func reloadReplaces() async throws {
        let model = try model(try browsable())
        await model.load()
        await model.load()
        #expect(model.hosts.count == 2)
    }
}
