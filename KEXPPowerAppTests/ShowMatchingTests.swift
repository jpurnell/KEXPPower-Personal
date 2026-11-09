import Foundation
import StationKit
import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("ShowMatching")
struct ShowMatchingTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        return calendar
    }

    /// 2026-11-07 is a Saturday, 2026-11-06 a Friday (Seattle).
    private func show(_ id: String, _ program: String, hosts: [String] = [], day: Int, hour: Int = 12) -> StationKit.ArchiveShow {
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour)) ?? .distantPast
        return StationKit.ArchiveShow(
            id: id, programName: program, hostNames: hosts, tagline: nil, imageURL: nil, startTime: start, tags: [])
    }

    private var shows: [StationKit.ArchiveShow] {
        [
            show("a", "Positive Vibrations", hosts: ["Kid Hops"], day: 7, hour: 12),
            show("b", "Variety Mix", hosts: ["Morgan"], day: 7, hour: 15),
            show("c", "Variety Mix", hosts: ["Troy Nelson"], day: 7, hour: 18),
            show("d", "Variety Mix", hosts: ["Greta Rose"], day: 6, hour: 6),
            show("e", "The Midday Show", hosts: ["Cheryl Waters"], day: 6, hour: 12),
        ]
    }

    private func ids(_ phrase: String, limit: Int = 5) -> [String] {
        ShowMatching.matches(phrase, in: shows, limit: limit, calendar: calendar).map(\.id)
    }

    @Test("A program is found by its spoken name, in any case")
    func byName() {
        #expect(ids("positive vibrations") == ["a"])
        #expect(ids("POSITIVE VIBRATIONS") == ["a"])
    }

    @Test("Part of a name is enough, and a leading 'the' is not needed")
    func partialName() {
        #expect(ids("midday") == ["e"])
        #expect(ids("vibrations") == ["a"])
    }

    @Test("A host's name finds their shows")
    func byHost() {
        #expect(ids("kid hops") == ["a"])
        #expect(ids("troy") == ["c"])
    }

    @Test("A program that airs several times returns every airing, newest first")
    func newestFirst() {
        #expect(ids("variety mix") == ["c", "b", "d"])
    }

    @Test("The limit caps the matches, keeping the newest")
    func limited() {
        #expect(ids("variety mix", limit: 2) == ["c", "b"])
    }

    @Test("A day word narrows the airings to that day")
    func byDay() {
        #expect(ids("variety mix saturday") == ["c", "b"])
        #expect(ids("variety mix friday") == ["d"])
    }

    @Test("A day word alone lists that day's shows")
    func dayOnly() {
        #expect(ids("friday") == ["d", "e"] || ids("friday") == ["e", "d"])
    }

    @Test("Accents are ignored")
    func diacritics() {
        let shows = [show("x", "Café Sónico", day: 7)]
        #expect(ShowMatching.matches("cafe sonico", in: shows, limit: 5, calendar: calendar).map(\.id) == ["x"])
    }

    @Test("An exact program name comes before a looser match")
    func exactFirst() {
        let shows = [
            show("loose", "Variety Mix Extra", day: 7, hour: 20),
            show("exact", "Variety Mix", day: 7, hour: 10),
        ]
        #expect(ShowMatching.matches("variety mix", in: shows, limit: 5, calendar: calendar).map(\.id) == ["exact", "loose"])
    }

    @Test("Nothing matches a name that is not there, and a blank phrase matches the newest shows")
    func noneAndBlank() {
        #expect(ids("zzz").isEmpty)
        #expect(ids("   ", limit: 2) == ["c", "b"])
        #expect(ShowMatching.matches("variety", in: [], limit: 5, calendar: calendar).isEmpty)
        #expect(ids("variety", limit: 0).isEmpty)
    }
}
