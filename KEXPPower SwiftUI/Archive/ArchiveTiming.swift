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

    /// Where to begin the next file so it picks up exactly where the previous one ended.
    ///
    /// Archive files overlap (observed: one ran to 10:00:29 and the next began at 09:50:08), so playing the next file
    /// from its start would repeat the overlap.
    /// - Parameters:
    ///   - previousFile: The file that is ending.
    ///   - previousDuration: How long that file runs, in seconds.
    ///   - nextFile: The file to roll into.
    /// - Returns: Seconds into the next file; `0` if it begins after the previous one ended; `nil` if either name
    ///   carries no start time or the duration is not a finite number.
    static func joinOffset(previousFile: URL, previousDuration: TimeInterval, nextFile: URL) -> TimeInterval? {
        guard
            previousDuration.isFinite, previousDuration >= 0,
            let previousStart = fileStart(of: previousFile),
            let nextStart = fileStart(of: nextFile)
        else { return nil }
        return max(0, previousStart.addingTimeInterval(previousDuration).timeIntervalSince(nextStart))
    }

    /// A moment as a clock reading in the station's time zone, such as "5:01:32 AM PST".
    ///
    /// The zone is fixed because the archive's files and shows are named in it; the phone's own zone would disagree
    /// with them.
    /// - Parameters:
    ///   - date: The moment.
    ///   - zone: The time zone to read it in.
    static func clock(_ date: Date, zone: TimeZone = stationTimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "h:mm:ss a z"
        return formatter.string(from: date)
    }

    /// A position in a file as "11:25", or "1:02:05" once it passes an hour; a negative position reads as the start.
    /// - Parameter seconds: Seconds from the start of the file.
    static func positionText(_ seconds: TimeInterval) -> String {
        // Beyond a week is not a position in a show's file; it reads as the start, as NaN and infinity do.
        guard seconds.isFinite, seconds < 604_800 else { return "0:00" }
        let total = Int(max(0, seconds))
        let (hours, minutes, secs) = (total / 3_600, total % 3_600 / 60, total % 60)
        return hours > 0
            ? "\(hours):\(twoDigits(minutes)):\(twoDigits(secs))"
            : "\(minutes):\(twoDigits(secs))"
    }

    private static func twoDigits(_ number: Int) -> String {
        number < 10 ? "0\(number)" : "\(number)"
    }
}
