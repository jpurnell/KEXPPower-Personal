import Foundation
import StationKit
import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("ArchiveTiming")
struct ArchiveTimingTests {
    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    private func url(_ name: String) throws -> URL {
        try #require(URL(string: "https://kexp-archive.streamguys1.com/content/kexp/\(name)"))
    }

    /// Wednesday's Afternoon Show as the API reported it: the show began at 13:03:05, its file at 12:50:07.
    private func afternoonShow() throws -> ArchiveShow {
        ArchiveShow(
            id: "68231", programName: "The Afternoon Show", hostNames: [], tagline: nil, imageURL: nil,
            startTime: try date("2026-11-04T13:03:05-08:00"), tags: [])
    }

    private func playback(offset: TimeInterval) throws -> ArchivePlayback {
        ArchivePlayback(url: try url("20261104125007-2-1930-the-afternoon-show.mp3"), offset: offset, nextURL: nil)
    }

    @Test("A file's start time is read from the timestamp that begins its name, in the station's time zone")
    func fileStart() throws {
        let start = ArchiveTiming.fileStart(of: try url("20261104125007-2-1930-the-afternoon-show.mp3"))
        #expect(start == (try date("2026-11-04T12:50:07-08:00")))
    }

    @Test("Daylight time is honoured: the same wall-clock reading is an hour earlier in UTC in summer")
    func fileStartDaylightTime() throws {
        let start = ArchiveTiming.fileStart(of: try url("20260715090000-1-1-the-morning-show.mp3"))
        #expect(start == (try date("2026-07-15T09:00:00-07:00")))
    }

    @Test("A name that does not begin with a timestamp has no start time")
    func fileStartAbsent() throws {
        #expect(ArchiveTiming.fileStart(of: try url("the-afternoon-show.mp3")) == nil)
        #expect(ArchiveTiming.fileStart(of: try url("20269999999999-x.mp3")) == nil)
    }

    @Test("A song's place in the file is the show's offset plus how long after the show began it aired")
    func songPosition() throws {
        let position = ArchiveTiming.songPosition(
            airedAt: try date("2026-11-04T13:06:48-08:00"), in: try afternoonShow(), playback: try playback(offset: 778))
        #expect(position == 1001)
    }

    @Test("A song that aired before the show's start time is placed that much earlier in the file")
    func songBeforeShowStart() throws {
        let position = ArchiveTiming.songPosition(
            airedAt: try date("2026-11-04T13:03:00-08:00"), in: try afternoonShow(), playback: try playback(offset: 778))
        #expect(position == 773)
    }

    @Test("A position is never negative, whatever the arithmetic says")
    func positionClamped() throws {
        let position = ArchiveTiming.songPosition(
            airedAt: try date("2026-11-04T12:00:00-08:00"), in: try afternoonShow(), playback: try playback(offset: 778))
        #expect(position == 0)
    }

    @Test("The offset agrees with the file's name when the show's start minus the file's start equals it")
    func offsetAgrees() throws {
        let gap = ArchiveTiming.offsetDisagreement(show: try afternoonShow(), playback: try playback(offset: 778))
        #expect(gap == 0)
    }

    @Test("A disagreement is reported in seconds, in either direction")
    func offsetDisagrees() throws {
        let show = try afternoonShow()
        #expect(ArchiveTiming.offsetDisagreement(show: show, playback: try playback(offset: 800)) == 22)
        #expect(ArchiveTiming.offsetDisagreement(show: show, playback: try playback(offset: 700)) == 78)
    }

    @Test("With no timestamp in the file's name there is nothing to compare")
    func offsetNothingToCompare() throws {
        let plain = ArchivePlayback(url: try url("show.mp3"), offset: 778, nextURL: nil)
        #expect(ArchiveTiming.offsetDisagreement(show: try afternoonShow(), playback: plain) == nil)
    }

    @Test("The clock reading pads minutes and seconds, so five past reads 5:01:32 and not 5:1:32")
    func clockPads() throws {
        let aired = try date("2026-11-06T05:01:32-08:00")
        #expect(ArchiveTiming.clock(aired) == "5:01:32 AM PST")
    }

    @Test("The clock is read in the station's time zone, whatever the phone's is")
    func clockInStationZone() throws {
        // The same instant, written in Eastern, is still 5:01:32 in Seattle.
        let aired = try date("2026-11-06T08:01:32-05:00")
        #expect(ArchiveTiming.clock(aired) == "5:01:32 AM PST")
        #expect(ArchiveTiming.clock(try date("2026-07-15T14:09:05-07:00")) == "2:09:05 PM PDT")
    }

    @Test("A position reads minutes and seconds, with hours once it passes an hour")
    func positionText() {
        #expect(ArchiveTiming.positionText(685) == "11:25")
        #expect(ArchiveTiming.positionText(5) == "0:05")
        #expect(ArchiveTiming.positionText(3_725) == "1:02:05")
        #expect(ArchiveTiming.positionText(-3) == "0:00")
    }

    @Test("A position that is not a finite number reads as the start instead of crashing")
    func positionTextNotFinite() {
        #expect(ArchiveTiming.positionText(.nan) == "0:00")
        #expect(ArchiveTiming.positionText(.infinity) == "0:00")
        #expect(ArchiveTiming.positionText(1e300) == "0:00")
    }

    @Test("The next file is joined where the previous one ended, because archive files overlap")
    func joinOffset() throws {
        // Observed 2026-11-06: the Morning Show's file began 06:50:08 and ran 11,421 s, to 10:00:29; the next file began 09:50:08.
        let join = ArchiveTiming.joinOffset(
            previousFile: try url("20261106065008-4-1952-the-morning-show.mp3"),
            previousDuration: 11_421,
            nextFile: try url("20261106095008-5-1937-the-midday-show.mp3"))
        #expect(join == 621)
    }

    @Test("A next file that begins after the previous one ended is played from its start, with nothing to skip")
    func joinOffsetWithGap() throws {
        let join = ArchiveTiming.joinOffset(
            previousFile: try url("20261106065008-a.mp3"), previousDuration: 100, nextFile: try url("20261106075008-b.mp3"))
        #expect(join == 0)
    }

    @Test("Without timestamps in both names there is no join point to compute")
    func joinOffsetUnknown() throws {
        #expect(ArchiveTiming.joinOffset(previousFile: try url("a.mp3"), previousDuration: 100, nextFile: try url("20261106075008-b.mp3")) == nil)
        #expect(ArchiveTiming.joinOffset(previousFile: try url("20261106075008-a.mp3"), previousDuration: .nan, nextFile: try url("20261106075008-b.mp3")) == nil)
    }

    @Test("A list that spans days shows the day with the time: Thu Nov 5, 7:02 AM PST, in the station's zone")
    func dayAndClock() throws {
        #expect(ArchiveTiming.dayAndClock(try date("2026-11-05T07:02:50-08:00")) == "Thu Nov 5, 7:02 AM PST")
        #expect(ArchiveTiming.dayAndClock(try date("2026-11-05T10:15:00-05:00")) == "Thu Nov 5, 7:15 AM PST")
    }
}
