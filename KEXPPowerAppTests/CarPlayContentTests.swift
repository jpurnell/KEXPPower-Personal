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

    @Test("The archive is shown but not available yet, and says so")
    func archiveRow() {
        #expect(CarPlayContent.archiveRow == CarPlayContent.Row(title: "Archive", detail: "Coming soon"))
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

    @Test("Other states keep their own spoken labels")
    func labels() {
        #expect(CarPlayContent.saveButtonLabel(for: .idle) == "Add to playlist")
        #expect(CarPlayContent.saveButtonLabel(for: .notFound) == "No match found in Apple Music")
        #expect(CarPlayContent.saveButtonLabel(for: .needsPermission) == "Allow access to Apple Music")
    }
}
