//
//  ArchiveBrowserModel.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import Observation
import StationKit

/// What the archive browser needs from the app's player, so the model can be tested without audio.
@MainActor
protocol ArchivePlayer: AnyObject {
    /// Whether the player holds an archived show instead of the live stream.
    var isPlayingArchive: Bool { get }
    /// Whether the player is playing, as opposed to paused.
    var isPlaying: Bool { get }
    /// Seconds into the archived file being played; zero when nothing is known.
    var archiveFileTime: TimeInterval { get }
    /// The length of the archived file so far; zero when nothing is known.
    var archiveFileDuration: TimeInterval { get }
    /// Moves within the archived file.
    func seekArchive(to seconds: TimeInterval) async
    /// Starts or resumes playing.
    func playPlayer()
    /// Pauses.
    func pausePlayer()
    /// Plays an archived file from an offset in place of the live stream.
    func playArchive(url: URL, at offset: TimeInterval) async
    /// Tells the system what is playing.
    func updateNowPlaying(_ nowPlaying: NowPlaying) async
    /// Puts the live stream back.
    func returnToLive()
    /// Gives the player what the system may ask of the archived show (skip, scrub, and the timeline to report), or with
    /// `nil` takes it away, as for the live stream.
    func setTransportControls(_ controls: ArchiveTransportControls?)
    /// Arms (or, with `nil`, disarms) the hand-off at the end of an archived file.
    ///
    /// The player calls `provide` shortly before the file ends to learn what to roll into, and `advanced` once it has.
    func setContinuation(
        _ provide: (@MainActor () async -> ArchiveContinuation)?,
        advanced: (@MainActor (ArchiveContinuation) async -> Void)?)
}

/// What the system's lock screen and the car's Now Playing screen may ask of an archived show: skip, scrub, and where
/// the player is in the show.
struct ArchiveTransportControls: Sendable {
    /// Moves by a number of seconds; negative to go back.
    let skip: @MainActor (TimeInterval) async -> Void
    /// Moves to a position in the show, in seconds from its start.
    let seek: @MainActor (TimeInterval) async -> Void
    /// How far into the show the player is, and how long the show is; `nil` when that is not known.
    let timeline: @MainActor () -> PlaybackTimeline?
}

/// The four ways into the archive, as the website offers them.
enum ArchiveMode: String, CaseIterable, Identifiable {
    case date, host, show, genre

    var id: String { rawValue }

    /// The label in the picker.
    var title: String {
        switch self {
        case .date: "Date"
        case .host: "Host"
        case .show: "Show"
        case .genre: "Genre"
        }
    }
}

/// One thing picked in the archive, which means a list of shows.
enum ArchiveSelection: Hashable {
    /// A day, by the start of that day (an `ArchiveDayTile`'s id).
    case day(Date)
    case host(String)
    case program(String)
    case genre(String)
}

/// What to play when an archived file runs out.
enum ArchiveContinuation: Equatable {
    /// Roll into the show that follows, whose audio is at this address.
    case show(ArchiveShow, URL)
    /// Nothing follows that can be played: go back to the live stream.
    case live
}

/// One day in the archive's date picker, as the website draws it: month, day number and weekday.
struct ArchiveDayTile: Identifiable, Hashable {
    /// The start of the day, in the station's time zone.
    let id: Date
    /// The month, upper-case and abbreviated ("NOV").
    let month: String
    /// The day of the month ("6").
    let dayNumber: String
    /// The weekday, abbreviated ("Fri").
    let weekday: String
    /// Whether this is the current day.
    let isToday: Bool
    /// The shows that began on this day, in the order they aired.
    let shows: [ArchiveShow]
    /// What VoiceOver reads: "November 6, Friday".
    let accessibilityLabel: String

    /// The tiles for the last days up to and including today, newest first.
    /// - Parameters:
    ///   - index: The shows fetched for the span.
    ///   - now: The current moment.
    ///   - calendar: Decides where a day begins; its locale names the months and weekdays.
    ///   - count: How many days to show.
    static func tiles(index: ArchiveIndex, now: Date, calendar: Calendar, count: Int) -> [ArchiveDayTile] {
        let today = calendar.startOfDay(for: now)
        let byDay = Dictionary(
            uniqueKeysWithValues: index.days(calendar: calendar).compactMap { day in
                calendar.date(from: day.day).map { ($0, day.shows) }
            })
        let long = DateFormatter()
        long.calendar = calendar
        long.locale = calendar.locale
        long.timeZone = calendar.timeZone
        long.dateFormat = "MMMM d, EEEE"
        return (0..<max(0, count)).compactMap { back in
            guard let start = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            let parts = calendar.dateComponents([.month, .day, .weekday], from: start)
            let month = parts.month.flatMap { calendar.shortMonthSymbols[safe: $0 - 1] } ?? ""
            let weekday = parts.weekday.flatMap { calendar.shortWeekdaySymbols[safe: $0 - 1] } ?? ""
            return ArchiveDayTile(
                id: start,
                month: month.uppercased(),
                dayNumber: parts.day.map(String.init) ?? "",
                weekday: weekday,
                isToday: back == 0,
                shows: (byDay[start] ?? []).sorted { $0.startTime < $1.startTime },
                accessibilityLabel: long.string(from: start))
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// The Archive's Date mode: the last fifteen days, the shows on each, and playing one through the app's player.
@MainActor
@Observable
final class ArchiveBrowserModel {
    /// How the list of days stands.
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// The longest a show runs, so a show that began more recently than this may not have ended.
    static let longestShow: TimeInterval = 4 * 3_600

    /// The days to offer: KEXP keeps about two weeks of audio, and the website shows fifteen days.
    static let dayCount = 15

    private(set) var phase: Phase = .idle
    private(set) var tiles: [ArchiveDayTile] = []
    /// How the listener is browsing.
    var mode: ArchiveMode = .date
    /// Hosts, programs and genres in the loaded days, alphabetical, with how many shows each has.
    private(set) var hosts: [ArchiveHostSummary] = []
    private(set) var programs: [ArchiveProgramSummary] = []
    private(set) var genres: [ArchiveGenreSummary] = []
    /// Hosts' pictures by name; empty until loaded, and if the station has none.
    private(set) var hostPhotos: [String: URL] = [:]
    /// Whether the playing show's songs have been fetched.
    enum TracksState: Equatable { case idle, loading, loaded, failed }
    /// The songs of the show being heard, in the order they aired; only those with an air time, since the rest
    /// cannot be placed in the show.
    private(set) var tracks: [Track] = []
    private(set) var tracksState: TracksState = .idle
    /// Something to tell the listener about the last attempt to play, or `nil`.
    private(set) var notice: String?

    private var playing: ArchiveShow?
    /// Where `playing` begins in the file being heard, in seconds, or `nil` if that is not known.
    @ObservationIgnored private var playingOffset: TimeInterval?
    @ObservationIgnored private var index = ArchiveIndex(shows: [])
    @ObservationIgnored private let catalog: any ArchiveCatalog
    @ObservationIgnored private let player: any ArchivePlayer
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: @Sendable () -> Date
    /// How often the song heard is checked while a show plays; `nil` leaves that to the caller.
    @ObservationIgnored private let songCheckInterval: Duration?
    @ObservationIgnored private var songWatch: Task<Void, Never>?
    /// The id of the song last announced to the system, or `nil` while the show itself is announced.
    @ObservationIgnored private var announcedSongID: String?

    /// - Parameters:
    ///   - catalog: The station's archive.
    ///   - player: The app's player.
    ///   - calendar: Decides where a day begins; the station's time zone.
    ///   - now: The current moment; injected so tests control the date.
    ///   - songCheckInterval: How often to look up the song being heard while a show plays, so the lock screen and the
    ///     car name it; `nil` for never.
    init(
        catalog: any ArchiveCatalog,
        player: any ArchivePlayer,
        calendar: Calendar,
        now: @escaping @Sendable () -> Date = Date.init,
        songCheckInterval: Duration? = .seconds(3)
    ) {
        self.catalog = catalog
        self.player = player
        self.calendar = calendar
        self.now = now
        self.songCheckInterval = songCheckInterval
    }

    isolated deinit {
        songWatch?.cancel()
    }

    /// The archived show being heard, or `nil` when the player is on the live stream.
    var nowPlayingShow: ArchiveShow? {
        // `playing` is read first, so a screen is told when it is set whatever the player's flag was at the time.
        let show = playing
        return player.isPlayingArchive ? show : nil
    }

    /// A host's picture, or `nil` if the station has none for them.
    /// - Parameter name: The host's name.
    func hostPhoto(named name: String) -> URL? { hostPhotos[name] }

    /// Fetches the last fifteen days of shows and builds the tiles. Safe to call again to retry.
    func load() async {
        phase = .loading
        let moment = now()
        let oldest = calendar.date(
            byAdding: .day, value: -(Self.dayCount - 1), to: calendar.startOfDay(for: moment)) ?? moment
        do {
            // Pictures only dress the Host list, so failing to fetch them leaves placeholders and does not fail the load.
            async let photos = try? await catalog.hostPhotos()
            let shows = try await catalog.shows(from: oldest, to: moment)
            hostPhotos = await photos ?? [:]
            let loaded = ArchiveIndex(shows: shows)
            index = loaded
            tiles = ArchiveDayTile.tiles(index: loaded, now: moment, calendar: calendar, count: Self.dayCount)
            hosts = loaded.hosts
            programs = loaded.programs
            genres = loaded.genres
            phase = .loaded
        } catch {
            phase = .failed("The archive could not be reached. Check your connection and try again.")
        }
    }

    /// Plays a show from its start, in place of the live stream.
    /// - Parameter show: The show to play.
    func play(_ show: ArchiveShow) async {
        do {
            guard let playback = try await catalog.playback(for: show) else {
                notice = "That show is no longer available."
                return
            }
            await start(show, file: playback.url, at: playback.offset)
        } catch {
            notice = "That show could not be started. Check your connection and try again."
        }
    }

    /// The shows a selection means: a day's in the order they aired, the others newest first.
    /// - Parameter selection: A day, host, program or genre.
    func shows(for selection: ArchiveSelection) -> [ArchiveShow] {
        switch selection {
        case .day(let start): tiles.first { $0.id == start }?.shows ?? []
        case .host(let name): index.shows(byHost: name)
        case .program(let name): index.shows(ofProgram: name)
        case .genre(let name): index.shows(inGenre: name)
        }
    }

    /// The heading for a selection's list.
    /// - Parameter selection: A day, host, program or genre.
    func title(for selection: ArchiveSelection) -> String {
        switch selection {
        case .day(let start): tiles.first { $0.id == start }?.accessibilityLabel ?? ""
        case .host(let name), .program(let name): name
        case .genre(let name): genres.first { $0.id == name.lowercased() }?.name ?? name
        }
    }

    /// The show that began next after this one, among those loaded.
    /// - Parameter show: The show that is ending.
    func nextShow(after show: ArchiveShow) -> ArchiveShow? {
        tiles.flatMap(\.shows)
            .filter { $0.startTime > show.startTime }
            .min { $0.startTime < $1.startTime }
    }

    /// What to play when this show's file ends: the following show if it has ended and has audio, otherwise the live stream.
    ///
    /// A failed lookup also means live, because silence is the worse outcome.
    /// - Parameter show: The show that is ending.
    func continuation(after show: ArchiveShow) async -> ArchiveContinuation {
        guard let next = nextShow(after: show) else { return .live }
        // The newest show may still be on the air, and its file is still being written: go live instead.
        if nextShow(after: next) == nil, next.startTime > now().addingTimeInterval(-Self.longestShow) { return .live }
        do {
            guard let playback = try await catalog.playback(for: next) else { return .live }
            return .show(next, playback.url)
        } catch {
            return .live
        }
    }

    /// The range of the show being heard, for the player's scrubber and skip buttons; `nil` when no archived show is
    /// playing or where it begins in the file is not known.
    var transport: ArchiveTransport? {
        guard let show = nowPlayingShow, let offset = playingOffset else { return nil }
        let length = nextShow(after: show).map { $0.startTime.timeIntervalSince(show.startTime) }
        return ArchiveTransport(offset: offset, showLength: length, fileDuration: player.archiveFileDuration)
    }

    /// Whether the player is playing, as opposed to paused.
    var isPlaying: Bool { player.isPlaying }

    /// Where the player is in the file being heard, in seconds; read by the bar's clock rather than observed.
    var fileTime: TimeInterval { player.archiveFileTime }

    /// The time of day, at the station, that a moment in the file was on the air.
    /// - Parameter fileTime: Seconds into the file.
    /// - Returns: The moment, or `nil` when no archived show is playing.
    func airTime(atFileTime fileTime: TimeInterval) -> Date? {
        guard let show = nowPlayingShow, let transport else { return nil }
        return show.startTime.addingTimeInterval(transport.elapsed(atFileTime: fileTime))
    }

    /// Fetches the songs of the show being heard, unless they are already here or being fetched. Safe to call again
    /// to retry after a failure.
    func loadTracks() async {
        guard let show = nowPlayingShow, tracksState == .idle || tracksState == .failed else { return }
        tracksState = .loading
        do {
            let fetched = try await catalog.tracks(of: show)
            // The player may have moved on while the songs were coming; they are no longer this show's.
            guard playing?.id == show.id else { return }
            tracks = fetched.filter { $0.airDate != nil }
            tracksState = .loaded
        } catch {
            guard playing?.id == show.id else { return }
            tracksState = .failed
        }
    }

    /// Whether a song is in the part of the show that was recorded.
    /// - Parameter track: A song of the show being heard.
    func isPlayable(_ track: Track) -> Bool {
        guard let show = nowPlayingShow, let transport, let aired = track.airDate else { return false }
        return aired.timeIntervalSince(show.startTime) < transport.length
    }

    /// A note for when the recording holds only part of the show, or `nil`.
    var truncationNote: String? {
        guard let transport, transport.isTruncated else { return nil }
        return "Only the first \(ArchiveTiming.positionText(transport.length)) of this show was recorded."
    }

    /// The song being heard: the latest one that had aired by this point in the show.
    /// - Parameter fileTime: Seconds into the file.
    func currentTrack(atFileTime fileTime: TimeInterval) -> Track? {
        guard let show = nowPlayingShow, let transport else { return nil }
        let elapsed = transport.elapsed(atFileTime: fileTime)
        return tracks.last { ($0.airDate?.timeIntervalSince(show.startTime) ?? .infinity) <= elapsed }
    }

    /// Tells the lock screen and the car which song is being heard, when it has changed: the latest one that had aired
    /// by this point in the show, or the show itself before its first song. Does nothing until the songs are here.
    func announceCurrentSong() async {
        guard let show = nowPlayingShow, tracksState == .loaded else { return }
        let track = currentTrack(atFileTime: player.archiveFileTime)
        guard track?.id != announcedSongID else { return }
        guard let track else {
            await announce(show)
            return
        }
        announcedSongID = track.id
        await player.updateNowPlaying(.track(track))
    }

    /// Fetches the songs, then keeps naming the one heard for as long as an archived show plays.
    private func followSongs(every interval: Duration) async {
        await loadTracks()
        while !Task.isCancelled, nowPlayingShow != nil {
            await announceCurrentSong()
            try? await Task.sleep(for: interval)
        }
    }

    private func startFollowingSongs() {
        songWatch?.cancel()
        songWatch = nil
        guard let interval = songCheckInterval else { return }
        songWatch = Task { [weak self] in await self?.followSongs(every: interval) }
    }

    private func stopFollowingSongs() {
        songWatch?.cancel()
        songWatch = nil
    }

    /// Jumps to where a song aired in the show.
    /// - Parameter track: A song of the show being heard.
    func seek(to track: Track) async {
        guard let show = nowPlayingShow, let transport, let aired = track.airDate else { return }
        await move(to: transport.target(showTime: aired.timeIntervalSince(show.startTime)))
    }

    /// How far into the show the player is and how long the show is, as the system's lock screen wants it.
    func timeline() -> PlaybackTimeline? {
        guard let transport, !transport.isEmpty else { return nil }
        return PlaybackTimeline(
            elapsed: transport.elapsed(atFileTime: player.archiveFileTime), duration: transport.length)
    }

    /// Jumps to a position in the show, as a scrub from the lock screen does.
    /// - Parameter showTime: Seconds from the start of the show.
    func seek(toShowTime showTime: TimeInterval) async {
        guard let transport else { return }
        await move(to: transport.target(showTime: showTime))
    }

    /// Hands the player what the system may ask of the show being heard. The controls hold the model weakly, so a
    /// player that outlives it cannot keep it alive.
    private func provideTransportControls() {
        player.setTransportControls(ArchiveTransportControls(
            skip: { [weak self] seconds in await self?.skip(by: seconds) },
            seek: { [weak self] position in await self?.seek(toShowTime: position) },
            timeline: { [weak self] in self?.timeline() }))
    }

    /// Jumps back or forward within the show; past its end, goes on to the next show, or to live.
    /// - Parameter seconds: How far to move; negative to go back.
    func skip(by seconds: TimeInterval) async {
        guard let transport else { return }
        await move(to: transport.target(skipping: seconds, from: player.archiveFileTime))
    }

    /// Jumps to a place in the show; its very end goes on to the next show, or to live.
    /// - Parameter fraction: 0 for the start of the show, 1 for its end.
    func scrub(toFraction fraction: Double) async {
        guard let transport else { return }
        await move(to: transport.target(fraction: fraction))
    }

    /// Pauses what is playing, or plays what is paused.
    func togglePause() {
        if player.isPlaying { player.pausePlayer() } else { player.playPlayer() }
    }

    /// Plays a show's file from an offset and takes it as the show being heard.
    private func start(_ show: ArchiveShow, file: URL, at offset: TimeInterval) async {
        await player.playArchive(url: file, at: offset)
        playingOffset = offset
        playing = show
        clearTracks()
        notice = nil
        provideTransportControls()
        // After the state above, so the timeline announced with the show is this show's.
        await announce(show)
        armContinuation()
        startFollowingSongs()
    }

    private func move(to target: ArchiveTransport.Target) async {
        switch target {
        case .within(let fileTime):
            await player.seekArchive(to: fileTime)
        case .unrecorded:
            notice = "That song is past the end of this recording."
        case .end:
            guard let show = playing else { return }
            switch await continuation(after: show) {
            case .show(let next, let file):
                let offset = ArchiveTiming.fileStart(of: file).map { max(0, next.startTime.timeIntervalSince($0)) } ?? 0
                await start(next, file: file, at: offset)
            case .live: returnToLive()
            }
        }
    }

    /// Stops the archived show and goes back to the live stream.
    func returnToLive() {
        player.setContinuation(nil, advanced: nil)
        player.setTransportControls(nil)
        player.returnToLive()
        playing = nil
        playingOffset = nil
        stopFollowingSongs()
        clearTracks()
    }

    private func clearTracks() {
        tracks = []
        tracksState = .idle
    }

    private func announce(_ show: ArchiveShow) async {
        announcedSongID = nil
        await player.updateNowPlaying(.program(ProgramInfo(
            title: show.programName,
            host: show.hostNames.isEmpty ? nil : ListFormatter.localizedString(byJoining: show.hostNames),
            artworkURL: show.imageURL)))
    }

    /// Lets the player ask what follows the show being heard, and tell us when it has rolled into it.
    private func armContinuation() {
        player.setContinuation(
            { [weak self] in
                guard let self, let current = self.playing else { return .live }
                return await self.continuation(after: current)
            },
            advanced: { [weak self] plan in await self?.advanced(to: plan) })
    }

    /// The player has rolled over: into the next show, or onto the live stream.
    private func advanced(to plan: ArchiveContinuation) async {
        switch plan {
        case .show(let next, let file):
            // The next show begins as far into its own file as the show's start is after the file's.
            playingOffset = ArchiveTiming.fileStart(of: file).map { next.startTime.timeIntervalSince($0) }
            playing = next
            clearTracks()
            provideTransportControls()
            await announce(next)
            startFollowingSongs()
        case .live:
            playing = nil
            playingOffset = nil
            stopFollowingSongs()
            clearTracks()
            player.setTransportControls(nil)
        }
    }
}
