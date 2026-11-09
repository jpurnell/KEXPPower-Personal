//
//  ShowMatching.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import StationKit

/// Finds archived shows from what a listener says: part of a program name or a host's name, with an optional day.
///
/// Siri cannot be given every show title ahead of time, so the match is done against the shows the archive holds.
enum ShowMatching {
    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let fillers: Set<String> = ["the", "a", "on", "from", "play"]

    /// The shows a spoken phrase means, an exact program name first and then by how recently they aired.
    /// - Parameters:
    ///   - phrase: What was said, such as "variety mix saturday". A blank phrase means every show.
    ///   - shows: The shows to look through.
    ///   - limit: The most to return; zero or less returns none.
    ///   - calendar: Decides which day a show aired on; the station's.
    static func matches(
        _ phrase: String, in shows: [StationKit.ArchiveShow], limit: Int, calendar: Calendar
    ) -> [StationKit.ArchiveShow] {
        guard limit > 0 else { return [] }
        var words = tokens(phrase).filter { !fillers.contains($0) }
        let day = words.first { weekdays.contains($0) }.flatMap { weekdays.firstIndex(of: $0) }
        words.removeAll { weekdays.contains($0) }

        let ranked: [(rank: Int, show: StationKit.ArchiveShow)] = shows.compactMap { show in
            if let day, calendar.component(.weekday, from: show.startTime) - 1 != day { return nil }
            guard !words.isEmpty else { return (0, show) }
            let program = tokens(show.programName).filter { !fillers.contains($0) }
            if program == words { return (0, show) }
            if words.allSatisfy({ word in program.contains { $0.hasPrefix(word) } }) { return (1, show) }
            let hosts = show.hostNames.flatMap(tokens)
            if words.allSatisfy({ word in (program + hosts).contains { $0.hasPrefix(word) } }) { return (2, show) }
            return nil
        }
        return ranked
            .sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.show.startTime > $1.show.startTime }
            .prefix(limit)
            .map(\.show)
    }

    /// Lower-case words without accents or punctuation.
    private static func tokens(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
