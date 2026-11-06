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
    /// Plays an archived file from an offset in place of the live stream.
    func playArchive(url: URL, at offset: TimeInterval) async
    /// Tells the system what is playing.
    func updateNowPlaying(_ nowPlaying: NowPlaying) async
    /// Puts the live stream back.
    func returnToLive()
    /// Arms (or, with `nil`, disarms) the hand-off at the end of an archived file.
    ///
    /// The player calls `provide` shortly before the file ends to learn what to roll into, and `advanced` once it has.
    func setContinuation(
        _ provide: (@MainActor () async -> ArchiveContinuation)?,
        advanced: (@MainActor (ArchiveContinuation) async -> Void)?)
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
    /// Something to tell the listener about the last attempt to play, or `nil`.
    private(set) var notice: String?

    private var playing: ArchiveShow?
    @ObservationIgnored private let catalog: any ArchiveCatalog
    @ObservationIgnored private let player: any ArchivePlayer
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - catalog: The station's archive.
    ///   - player: The app's player.
    ///   - calendar: Decides where a day begins; the station's time zone.
    ///   - now: The current moment; injected so tests control the date.
    init(
        catalog: any ArchiveCatalog,
        player: any ArchivePlayer,
        calendar: Calendar,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.catalog = catalog
        self.player = player
        self.calendar = calendar
        self.now = now
    }

    /// The archived show being heard, or `nil` when the player is on the live stream.
    var nowPlayingShow: ArchiveShow? {
        // `playing` is read first, so a screen is told when it is set whatever the player's flag was at the time.
        let show = playing
        return player.isPlayingArchive ? show : nil
    }

    /// Fetches the last fifteen days of shows and builds the tiles. Safe to call again to retry.
    func load() async {
        phase = .loading
        let moment = now()
        let oldest = calendar.date(
            byAdding: .day, value: -(Self.dayCount - 1), to: calendar.startOfDay(for: moment)) ?? moment
        do {
            let shows = try await catalog.shows(from: oldest, to: moment)
            tiles = ArchiveDayTile.tiles(
                index: ArchiveIndex(shows: shows), now: moment, calendar: calendar, count: Self.dayCount)
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
            await player.playArchive(url: playback.url, at: playback.offset)
            await announce(show)
            playing = show
            notice = nil
            armContinuation()
        } catch {
            notice = "That show could not be started. Check your connection and try again."
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

    /// Stops the archived show and goes back to the live stream.
    func returnToLive() {
        player.setContinuation(nil, advanced: nil)
        player.returnToLive()
        playing = nil
    }

    private func announce(_ show: ArchiveShow) async {
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
        case .show(let next, _):
            playing = next
            await announce(next)
        case .live:
            playing = nil
        }
    }
}
