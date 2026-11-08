//
//  CarPlayContent.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import StationKit

/// The words and button states CarPlay shows, kept apart from the CarPlay framework so they can be tested.
///
/// A driver reads these at a glance, so each row is a short title and a short detail.
enum CarPlayContent {
    /// One line of a CarPlay list.
    struct Row: Equatable {
        let title: String
        let detail: String
    }

    /// The station's name, shown when the show is not known.
    static let stationName = "KEXP 90.3 FM"

    /// A button on the system's Now Playing screen.
    enum NowPlayingButton: Equatable {
        /// Adds the song on the air to the listener's playlist.
        case save
        /// Goes back to the live stream.
        case live
    }

    /// The live button's symbol: the bolt the phone uses for the same thing.
    static let liveButtonSymbol = "bolt.fill"

    /// The buttons for the Now Playing screen. An archived show gets the way back to live instead of the add button,
    /// which would save the song on the air and not the one being heard.
    static func nowPlayingButtons(isPlayingArchive: Bool) -> [NowPlayingButton] {
        isPlayingArchive ? [.live] : [.save]
    }

    /// A day of the archive: "Today" or its weekday and date, over how many shows it holds.
    static func dayRow(_ day: ArchiveDayTile) -> Row {
        let title = day.isToday ? "Today" : "\(day.weekday) \(day.month.capitalized) \(day.dayNumber)"
        let count = day.shows.count
        let detail = switch count {
        case 0: "No shows"
        case 1: "1 show"
        default: "\(count) shows"
        }
        return Row(title: title, detail: detail)
    }

    /// An archived show: its name over the time it began at the station and its hosts.
    static func archiveShowRow(_ show: ArchiveShow) -> Row {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = ArchiveTiming.stationTimeZone
        formatter.dateFormat = "h:mm a"
        let start = formatter.string(from: show.startTime)
        let hosts = show.hostNames.map(trimmed).filter { !$0.isEmpty }
        let detail = hosts.isEmpty ? start : "\(start) · \(hosts.formatted(.list(type: .and)))"
        return Row(title: show.programName, detail: detail)
    }

    /// The show on the air and its host or hosts, such as "The Midday Show" over "Cheryl Waters".
    /// - Parameters:
    ///   - programName: The show's name, if known.
    ///   - hostNames: The hosts, if any.
    static func showRow(programName: String?, hostNames: [String]?) -> Row {
        let hosts = (hostNames ?? []).map(trimmed).filter { !$0.isEmpty }
        guard let program = programName.map(trimmed), !program.isEmpty else {
            return Row(title: stationName, detail: "Live")
        }
        return Row(title: program, detail: hosts.isEmpty ? stationName : hosts.formatted(.list(type: .and)))
    }

    /// The song on the air: its title over its artist, with the airbreak wording between songs.
    static func songRow(_ summary: NowPlayingSummary) -> Row {
        Row(title: summary.title, detail: summary.artist)
    }

    /// The add button's symbol for a save state.
    ///
    /// A match held for review shows a phone: the phone's question mark means nothing to someone driving.
    static func saveButtonSymbol(for state: SaveState) -> String {
        if case .confirming = state { return "iphone" }
        // The car says nothing more than this: an alert to read or dismiss is a distraction, and the phone has the rest.
        if state == .heldForReview { return "iphone.gen3.badge.exclamationmark" }
        return state.symbolName
    }

    /// Whether the add button looks selected: only once the song is in the playlist.
    static func saveButtonSelected(for state: SaveState) -> Bool {
        if case .saved(_, let failed) = state { return failed.isEmpty }
        return state == .heldForReview
    }

    /// Whether the add button accepts a press: not while a save is in progress.
    static func saveButtonEnabled(for state: SaveState) -> Bool {
        state != .saving
    }

    /// What is spoken for the add button. A match that needs confirming is held rather than guessed at while
    /// driving, and the car says it waits on the phone.
    static func saveButtonLabel(for state: SaveState) -> String {
        if case .confirming = state { return "Review on your phone" }
        return state.accessibilityLabel
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
