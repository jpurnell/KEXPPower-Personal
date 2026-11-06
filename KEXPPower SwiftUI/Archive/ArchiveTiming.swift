//
//  ArchiveTiming.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import StationKit

/// The arithmetic between a show's start, an archived file's start and a song's airdate.
///
/// An archived file begins before its show does (observed: a show that began at 13:03:05 was in a file that began at
/// 12:50:07), so a song's place in the file is the playback offset for the show's start plus how long after the show
/// began the song aired.
enum ArchiveTiming {
    /// KEXP's archive names files with the time they begin, in Seattle's time zone.
    static let stationTimeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current

    /// When an archived file begins, read from the `yyyyMMddHHmmss` that starts its name.
    /// - Parameters:
    ///   - url: The file's address.
    ///   - zone: The time zone the name's clock reading is in.
    /// - Returns: The start time, or `nil` if the name does not begin with a valid timestamp.
    static func fileStart(of url: URL, zone: TimeZone = stationTimeZone) -> Date? {
        let stamp = String(url.lastPathComponent.prefix(14))
        guard stamp.count == 14, stamp.allSatisfy(\.isNumber) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.isLenient = false
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.date(from: stamp)
    }

    /// Where a song is in a show's file, in seconds.
    /// - Parameters:
    ///   - airdate: When the song aired.
    ///   - show: The show it aired in.
    ///   - playback: The file and the offset at which the show begins.
    /// - Returns: Seconds into the file; never negative.
    static func songPosition(airedAt airdate: Date, in show: ArchiveShow, playback: ArchivePlayback) -> TimeInterval {
        max(0, playback.offset + airdate.timeIntervalSince(show.startTime))
    }

    /// How far the station's offset is from what the file's name implies, as a check that the two clocks agree.
    /// - Parameters:
    ///   - show: The show that was asked for.
    ///   - playback: What the station answered.
    /// - Returns: The gap in seconds, or `nil` if the file's name carries no start time to compare.
    static func offsetDisagreement(show: ArchiveShow, playback: ArchivePlayback) -> TimeInterval? {
        guard let start = fileStart(of: playback.url) else { return nil }
        return abs(playback.offset - show.startTime.timeIntervalSince(start))
    }
}
