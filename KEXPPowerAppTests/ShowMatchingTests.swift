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

    // MARK: Dates

    private var afternoons: [StationKit.ArchiveShow] {
        [
            show("n3", "The Afternoon Show", hosts: ["Larry Mizell, Jr."], day: 3, hour: 13),
            show("n4", "The Afternoon Show", hosts: ["Larry Mizell, Jr."], day: 4, hour: 13),
            show("n5", "The Afternoon Show", hosts: ["Larry Mizell, Jr."], day: 5, hour: 13),
            show("n4d", "Drive Time", hosts: ["Evie Stokes"], day: 4, hour: 16),
        ]
    }

    private func found(_ phrase: String, now: Date? = nil) -> [String] {
        let moment = now ?? calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 10)) ?? .now
        return ShowMatching.matches(phrase, in: afternoons, limit: 5, calendar: calendar, now: moment).map(\.id)
    }

    @Test("A month and a day narrow the airings to that date, as a listener says it")
    func monthAndDay() {
        #expect(found("afternoon show from november 4th") == ["n4"])
        #expect(found("the afternoon show november 4") == ["n4"])
        #expect(found("afternoon show nov 4th") == ["n4"])
        #expect(found("afternoon show on the 4th") == ["n4"])
    }

    @Test("A date alone lists that day's shows")
    func dateOnly() {
        #expect(Set(found("november 4th")) == ["n4", "n4d"])
    }

    @Test("A plain number counts as a day only beside a month, so a number in a name is left alone")
    func plainNumber() {
        let ninety = [show("t", "90.TEEN", hosts: ["Youth DJ"], day: 7, hour: 9)]
        #expect(ShowMatching.matches("90 teen", in: ninety, limit: 5, calendar: calendar).map(\.id) == ["t"])
    }

    @Test("Today and yesterday are read against the moment of asking")
    func relativeDays() {
        let nov5 = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 20)) ?? .now
        #expect(found("afternoon show today", now: nov5) == ["n5"])
        #expect(found("afternoon show yesterday", now: nov5) == ["n4"])
    }

    @Test("A date with no show on it matches nothing")
    func dateWithNoShow() {
        #expect(found("afternoon show november 20th").isEmpty)
    }
}
