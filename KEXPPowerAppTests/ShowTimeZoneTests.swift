import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("ShowTimeZone")
struct ShowTimeZoneTests {
    @Test("Stored values map to the matching choice")
    func storedValues() {
        #expect(ShowTimeZone.resolve(stored: "mine") == .mine)
        #expect(ShowTimeZone.resolve(stored: "station") == .station)
        #expect(ShowTimeZone.allCases.count == 2)
    }

    @Test("Nothing stored, or something unrecognised, is the listener's own time zone, as the phone has always drawn it")
    func fallback() {
        #expect(ShowTimeZone.resolve(stored: nil) == .mine)
        #expect(ShowTimeZone.resolve(stored: "") == .mine)
        #expect(ShowTimeZone.resolve(stored: "Pacific") == .mine)
    }

    @Test("The listener's choice follows the device; the station's is Seattle's")
    func zones() {
        #expect(ShowTimeZone.mine.zone == TimeZone.autoupdatingCurrent)
        #expect(ShowTimeZone.station.zone == ArchiveTiming.stationTimeZone)
        #expect(ShowTimeZone.station.zone.identifier == "America/Los_Angeles")
    }

    @Test("Every choice has a label to show in Settings, and they differ")
    func labels() {
        #expect(ShowTimeZone.allCases.allSatisfy { !$0.label.isEmpty })
        #expect(ShowTimeZone.mine.label != ShowTimeZone.station.label)
    }

    @Test("The same moment reads differently in the two zones")
    func sameMomentTwoZones() {
        // 7:00 AM PST on 2026-11-06 is 15:00 UTC.
        let start = Date(timeIntervalSince1970: 1_793_977_200)
        let utc = TimeZone(identifier: "UTC") ?? .gmt
        #expect(ArchiveTiming.clock(start, zone: ShowTimeZone.station.zone).hasPrefix("7:00:00 AM"))
        #expect(ArchiveTiming.clock(start, zone: utc).hasPrefix("3:00:00 PM"))
    }
}
