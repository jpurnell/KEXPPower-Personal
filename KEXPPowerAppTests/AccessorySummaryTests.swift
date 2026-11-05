import Foundation
import StationKit
import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("AccessorySummary")
struct AccessorySummaryTests {
    private let when = Date(timeIntervalSince1970: 1_730_000_000)

    private func snapshot(title: String, artist: String?, airbreak: Bool = false) -> WidgetSnapshot {
        let nowPlaying: NowPlaying = airbreak
            ? .message("Airbreak")
            : .track(Track(id: "1", title: title, credits: artist.map { [Credit(role: .performer, name: $0)] } ?? []))
        return WidgetSnapshot(
            nowPlaying: nowPlaying, stationName: "KEXP", fallbackArtworkURL: nil, fetchedAt: when)
    }

    @Test("The inline complication reads title and artist on one line")
    func inline() {
        let summary = AccessorySummary(snapshot(title: "Sugar", artist: "NoSo"), isPlaying: false)
        #expect(summary.inlineText == "Sugar – NoSo")
    }

    @Test("An airbreak reads as the station's message, with the station as the artist")
    func airbreak() {
        let summary = AccessorySummary(snapshot(title: "", artist: nil, airbreak: true), isPlaying: false)
        #expect(summary.inlineText == "Airbreak – KEXP")
    }

    @Test("A song with no artist shows the station in its place")
    func noArtist() {
        let summary = AccessorySummary(snapshot(title: "Only A Title", artist: nil), isPlaying: false)
        #expect(summary.inlineText == "Only A Title – KEXP")
    }

    @Test("The action label says what a tap does, and VoiceOver hears the song and the state")
    func labels() {
        let paused = AccessorySummary(snapshot(title: "Sugar", artist: "NoSo"), isPlaying: false)
        let playing = AccessorySummary(snapshot(title: "Sugar", artist: "NoSo"), isPlaying: true)
        #expect(paused.actionLabel == "Play KEXP")
        #expect(playing.actionLabel == "Pause KEXP")
        #expect(paused.accessibilityLabel == "Sugar by NoSo, paused")
        #expect(playing.accessibilityLabel == "Sugar by NoSo, playing")
    }

    @Test("The symbol is the action a tap performs")
    func symbol() {
        #expect(AccessorySummary(snapshot(title: "A", artist: "B"), isPlaying: true).symbolName == "pause.fill")
        #expect(AccessorySummary(snapshot(title: "A", artist: "B"), isPlaying: false).symbolName == "play.fill")
    }

    @Test("The time line says when the song aired, and never claims to be live")
    func timeLine() {
        let song = AccessorySummary(snapshot(title: "Sugar", artist: "NoSo"), isPlaying: false)
        let notice = AccessorySummary(snapshot(title: "", artist: nil, airbreak: true), isPlaying: false)
        #expect(song.timeLine.hasPrefix("Last played "))
        #expect(notice.timeLine.hasPrefix("As of "))
        let formatted = when.formatted(date: .omitted, time: .shortened)
        #expect(song.timeLine.hasSuffix(formatted))
    }
}
