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
    private static let months = [
        "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november",
        "december",
    ]
    private static let fillers: Set<String> = ["the", "a", "on", "from", "of", "play"]

    /// The shows a spoken phrase means, an exact program name first and then by how recently they aired.
    /// - Parameters:
    ///   - phrase: What was said, such as "afternoon show from november 4th" or "variety mix saturday". A blank phrase
    ///     means every show.
    ///   - shows: The shows to look through.
    ///   - limit: The most to return; zero or less returns none.
    ///   - calendar: Decides which day a show aired on.
    ///   - now: The moment of asking, for "today" and "yesterday".
    static func matches(
        _ phrase: String, in shows: [StationKit.ArchiveShow], limit: Int, calendar: Calendar, now: Date = .now
    ) -> [StationKit.ArchiveShow] {
        guard limit > 0 else { return [] }
        var words = tokens(phrase).filter { !fillers.contains($0) }
        let when = When(extracting: &words, calendar: calendar, now: now)

        let ranked: [(rank: Int, show: StationKit.ArchiveShow)] = shows.compactMap { show in
            guard when.allows(show.startTime, calendar: calendar) else { return nil }
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

    /// The day words of a phrase: a weekday, a month and day of the month, or today and yesterday.
    private struct When {
        var weekday: Int?
        var month: Int?
        var day: Int?
        var date: DateComponents?

        /// Takes the day words out of `words`, leaving the name.
        init(extracting words: inout [String], calendar: Calendar, now: Date) {
            let hasMonth = words.contains { Self.monthIndex($0) != nil }
            var name: [String] = []
            for word in words {
                if let index = weekdays.firstIndex(of: word) {
                    weekday = index + 1
                } else if let index = Self.monthIndex(word) {
                    month = index + 1
                } else if word == "today" {
                    date = calendar.dateComponents([.year, .month, .day], from: now)
                } else if word == "yesterday" {
                    date = calendar.date(byAdding: .day, value: -1, to: now)
                        .map { calendar.dateComponents([.year, .month, .day], from: $0) }
                } else if let number = Self.dayNumber(word, plainCounts: hasMonth) {
                    day = number
                } else {
                    name.append(word)
                }
            }
            words = name
        }

        func allows(_ start: Date, calendar: Calendar) -> Bool {
            let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: start)
            if let weekday, parts.weekday != weekday { return false }
            if let month, parts.month != month { return false }
            if let day, parts.day != day { return false }
            if let date, parts.year != date.year || parts.month != date.month || parts.day != date.day { return false }
            return true
        }

        private static func monthIndex(_ word: String) -> Int? {
            guard word.count >= 3 else { return nil }
            return months.firstIndex { $0 == word || ($0.hasPrefix(word) && word.count == 3) }
        }

        /// A day of the month: "4th", "22nd", or a plain number when a month was also said.
        private static func dayNumber(_ word: String, plainCounts: Bool) -> Int? {
            let suffixes = ["st", "nd", "rd", "th"]
            let digits = word.prefix { $0.isNumber }
            guard !digits.isEmpty, let number = Int(digits), (1...31).contains(number) else { return nil }
            let rest = word.dropFirst(digits.count)
            if rest.isEmpty { return plainCounts ? number : nil }
            return suffixes.contains(String(rest)) ? number : nil
        }
    }

    /// Lower-case words without accents or punctuation.
    private static func tokens(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
