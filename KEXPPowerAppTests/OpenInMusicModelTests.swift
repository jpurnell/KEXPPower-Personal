import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

/// Hands out the same answer for every lookup and counts how many it was asked.
@MainActor
private final class CountingLookup {
    var answer: URL?
    private(set) var asked: [(artist: String, track: String, album: String)] = []

    init(answer: URL?) { self.answer = answer }

    func lookup(artist: String, track: String, album: String) async -> URL? {
        asked.append((artist, track, album))
        return answer
    }
}

@MainActor
@Suite("OpenInMusicModel")
struct OpenInMusicModelTests {
    private let trackURL = URL(string: "https://music.apple.com/us/album/x/1?i=2")

    private func make(
        answer: URL?, opened: @escaping @MainActor (URL) -> Void = { _ in }
    ) -> (OpenInMusicModel, CountingLookup) {
        let lookup = CountingLookup(answer: answer)
        let model = OpenInMusicModel(
            lookup: { artist, track, album in await lookup.lookup(artist: artist, track: track, album: album) },
            open: opened)
        return (model, lookup)
    }

    @Test("A song with an artist and a title can be opened; an airbreak cannot")
    func availability() {
        #expect(OpenInMusicModel.canOpen(artist: "Cate Le Bon", track: "Magic Boy"))
        #expect(!OpenInMusicModel.canOpen(artist: nil, track: "Magic Boy"))
        #expect(!OpenInMusicModel.canOpen(artist: "Cate Le Bon", track: nil))
        #expect(!OpenInMusicModel.canOpen(artist: "", track: "Magic Boy"))
        #expect(!OpenInMusicModel.canOpen(artist: "Cate Le Bon", track: "  "))
    }

    @Test("A tap looks the song up and opens what it finds")
    func opensTheFoundTrack() async throws {
        var opened: [URL] = []
        let (model, lookup) = make(answer: trackURL) { opened.append($0) }

        await model.open(artist: "Cate Le Bon", track: "Magic Boy", album: "Pompeii")

        #expect(opened == [try #require(trackURL)])
        #expect(lookup.asked.count == 1)
        #expect(lookup.asked.first?.album == "Pompeii")
        #expect(model.state == .idle)
    }

    @Test("When Apple Music has no match nothing opens, and the model says so")
    func notFound() async {
        var opened: [URL] = []
        let (model, _) = make(answer: nil) { opened.append($0) }

        await model.open(artist: "Nobody", track: "Nothing", album: "")

        #expect(opened.isEmpty)
        #expect(model.state == .notFound)
    }

    @Test("A later tap tries again after a miss")
    func retriesAfterAMiss() async throws {
        var opened: [URL] = []
        let (model, lookup) = make(answer: nil) { opened.append($0) }

        await model.open(artist: "A", track: "B", album: "")
        lookup.answer = trackURL
        await model.open(artist: "A", track: "B", album: "")

        #expect(opened == [try #require(trackURL)])
        #expect(model.state == .idle)
    }

    @Test("An airbreak is never looked up")
    func airbreakIsIgnored() async {
        var opened: [URL] = []
        let (model, lookup) = make(answer: trackURL) { opened.append($0) }

        await model.open(artist: nil, track: nil, album: nil)

        #expect(opened.isEmpty)
        #expect(lookup.asked.isEmpty)
    }

    @Test("The accessibility label names the song, and says when it was not found")
    func labels() {
        #expect(OpenInMusicModel.accessibilityLabel(track: "Magic Boy", state: .idle) == "Open Magic Boy in Music")
        #expect(
            OpenInMusicModel.accessibilityLabel(track: "Magic Boy", state: .notFound)
                == "Magic Boy was not found in Apple Music")
        #expect(
            OpenInMusicModel.accessibilityLabel(track: "Magic Boy", state: .looking)
                == "Looking for Magic Boy in Apple Music")
    }
}
