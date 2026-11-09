import Foundation
import KEXPPower
import StationKit
import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("CarPlayContent")
struct CarPlayContentTests {
    @Test("The first row is the show and its host, as the website and the phone show them")
    func showRow() {
        let row = CarPlayContent.showRow(programName: "The Midday Show", hostNames: ["Cheryl Waters"])
        #expect(row == CarPlayContent.Row(title: "The Midday Show", detail: "Cheryl Waters"))
    }

    @Test("Several hosts are listed together")
    func severalHosts() {
        let row = CarPlayContent.showRow(programName: "Early", hostNames: ["Eva Walker", "Lisa LeClair"])
        #expect(row.detail == "Eva Walker and Lisa LeClair")
    }

    @Test("Without a show the row names the station and says it is live")
    func noShow() {
        #expect(CarPlayContent.showRow(programName: nil, hostNames: nil) == CarPlayContent.Row(title: "KEXP 90.3 FM", detail: "Live"))
        #expect(CarPlayContent.showRow(programName: "  ", hostNames: []) == CarPlayContent.Row(title: "KEXP 90.3 FM", detail: "Live"))
    }

    @Test("A show with no host listed shows the station as live under the show's name")
    func noHost() {
        let row = CarPlayContent.showRow(programName: "Sonic Reducer", hostNames: [])
        #expect(row == CarPlayContent.Row(title: "Sonic Reducer", detail: "KEXP 90.3 FM"))
    }

    @Test("The song row is the title and artist, with the airbreak wording when between songs")
    func songRow() {
        let song = CarPlayContent.songRow(NowPlayingSummary(Play(id: 1, song: "Sugar", artist: "NoSo", playType: .trackplay)))
        #expect(song == CarPlayContent.Row(title: "Sugar", detail: "NoSo"))
        let airbreak = CarPlayContent.songRow(NowPlayingSummary(Play(id: 2, playType: .airbreak)))
        #expect(airbreak == CarPlayContent.Row(title: "Airbreak", detail: "KEXP"))
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func show(_ id: String, _ iso: String, hosts: [String] = ["John Richards"]) -> StationKit.ArchiveShow {
        StationKit.ArchiveShow(
            id: id, programName: "The Morning Show", hostNames: hosts, tagline: nil, imageURL: nil,
            startTime: ISO8601DateFormatter().date(from: iso) ?? .distantPast, tags: [])
    }

    private func tiles() -> [ArchiveDayTile] {
        let now = ISO8601DateFormatter().date(from: "2026-11-06T14:00:00-08:00") ?? .distantPast
        let shows = [
            show("1", "2026-11-06T07:00:00-08:00"), show("2", "2026-11-06T10:00:00-08:00"),
            show("3", "2026-11-05T07:00:00-08:00"),
        ]
        return ArchiveDayTile.tiles(index: ArchiveIndex(shows: shows), now: now, calendar: calendar, count: 15)
    }

    @Test("A day in the archive reads as Today or its weekday and date, over how many shows it holds")
    func dayRows() {
        let days = tiles()
        #expect(CarPlayContent.dayRow(days[0]) == CarPlayContent.Row(title: "Today", detail: "2 shows"))
        #expect(CarPlayContent.dayRow(days[1]) == CarPlayContent.Row(title: "Thu Nov 5", detail: "1 show"))
        #expect(CarPlayContent.dayRow(days[2]) == CarPlayContent.Row(title: "Wed Nov 4", detail: "No shows"))
    }

    @Test("An archived show is its name over its start time at the station and its hosts")
    func archiveShowRow() {
        let seattle = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        let row = CarPlayContent.archiveShowRow(show("1", "2026-11-06T07:00:00-08:00"), zone: seattle)
        #expect(row == CarPlayContent.Row(title: "The Morning Show", detail: "7:00 AM · John Richards"))
        let hostless = CarPlayContent.archiveShowRow(show("1", "2026-11-06T13:30:00-08:00", hosts: []), zone: seattle)
        #expect(hostless.detail == "1:30 PM")
    }

    @Test("The start time is read in the zone the listener chose")
    func archiveShowRowZone() {
        let utc = TimeZone(identifier: "UTC") ?? .gmt
        let row = CarPlayContent.archiveShowRow(show("1", "2026-11-06T07:00:00-08:00"), zone: utc)
        #expect(row.detail == "3:00 PM · John Richards")
    }

    @Test("The Now Playing screen offers the add button on the live stream, and the way back to live on an archived show")
    func nowPlayingButtons() {
        #expect(CarPlayContent.nowPlayingButtons(isPlayingArchive: false) == [.save])
        #expect(CarPlayContent.nowPlayingButtons(isPlayingArchive: true) == [.live])
        #expect(CarPlayContent.liveButtonSymbol == "bolt.fill")
    }

    @Test("The add button shows the save state: a symbol, selected once saved, off while saving")
    func saveButton() {
        #expect(CarPlayContent.saveButtonSymbol(for: .idle) == "plus.circle")
        #expect(!CarPlayContent.saveButtonSelected(for: .idle))
        #expect(CarPlayContent.saveButtonEnabled(for: .idle))

        let saved = SaveState.saved(playlists: ["KEXP"], failedPlaylists: [])
        #expect(CarPlayContent.saveButtonSymbol(for: saved) == "checkmark.circle.fill")
        #expect(CarPlayContent.saveButtonSelected(for: saved))

        #expect(!CarPlayContent.saveButtonEnabled(for: .saving))
    }

    @Test("A match that needs confirming is held, not guessed at, and the car says to review it on the phone")
    func confirmingIsHeld() {
        let song = CatalogSong(id: "1", title: "Sugar", artist: "NoSo")
        #expect(!CarPlayContent.saveButtonSelected(for: .confirming(song)))
        #expect(CarPlayContent.saveButtonLabel(for: .confirming(song)) == "Review on your phone")
    }

    @Test("A held match shows a phone, not a question mark, which tells a driver nothing")
    func confirmingSymbolIsAPhone() {
        let song = CatalogSong(id: "1", title: "Sugar", artist: "NoSo")
        #expect(CarPlayContent.saveButtonSymbol(for: .confirming(song)) == "iphone")
        #expect(CarPlayContent.saveButtonSymbol(for: .notFound) == "xmark.circle")
    }

    @Test("A song in the review queue shows a phone with a badge, selected, and is spoken as saved for later")
    func heldButton() {
        #expect(CarPlayContent.saveButtonSymbol(for: .heldForReview) == "iphone.gen3.badge.exclamationmark")
        #expect(CarPlayContent.saveButtonSelected(for: .heldForReview))
        #expect(CarPlayContent.saveButtonLabel(for: .heldForReview) == "Saved to review later")
    }

    @Test("Other states keep their own spoken labels")
    func labels() {
        #expect(CarPlayContent.saveButtonLabel(for: .idle) == "Add to playlist")
        #expect(CarPlayContent.saveButtonLabel(for: .notFound) == "No match found in Apple Music")
        #expect(CarPlayContent.saveButtonLabel(for: .needsPermission) == "Allow access to Apple Music")
    }
}
