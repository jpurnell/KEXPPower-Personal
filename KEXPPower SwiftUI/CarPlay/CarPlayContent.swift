//
//  CarPlayContent.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

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

    /// The archive row: present, so the Archive has a place, and honest that it is not built yet.
    static let archiveRow = Row(title: "Archive", detail: "Coming soon")

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
    static func saveButtonSymbol(for state: SaveState) -> String {
        state.symbolName
    }

    /// Whether the add button looks selected: only once the song is in the playlist.
    static func saveButtonSelected(for state: SaveState) -> Bool {
        if case .saved(_, let failed) = state { return failed.isEmpty }
        return false
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
