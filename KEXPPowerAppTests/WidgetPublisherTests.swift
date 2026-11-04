import Foundation
import KEXPPower
import StationKit
import Testing
@testable import KEXPPowerExampleSwiftUI

/// An in-memory store that records what was saved and every playing flag set.
private actor FakeStore: NowPlayingStore {
    private(set) var saved: [WidgetSnapshot] = []
    private(set) var playing: [Bool] = []
    func lastSnapshot() async -> WidgetSnapshot? { saved.last }
    func save(_ snapshot: WidgetSnapshot) async { saved.append(snapshot) }
    func isPlaying(asOf now: Date, maxAge: TimeInterval) async -> Bool { playing.last ?? false }
    func setPlaying(_ isPlaying: Bool, at date: Date) async { playing.append(isPlaying) }
}

@MainActor
private final class Reloads {
    var count = 0
}

@MainActor
private func makePublisher(_ store: FakeStore, _ reloads: Reloads) -> WidgetPublisher {
    WidgetPublisher(store: store, reload: { reloads.count += 1 })
}

private let now = Date(timeIntervalSince1970: 1_730_000_000)
private let sugar = Play(id: 1, song: "Sugar", album: "When Are You Leaving?", artist: "NoSo", playType: .trackplay)
private let bleeding = Play(id: 2, song: "Bleeding Blue", artist: "Cults", playType: .trackplay)

@MainActor
@Suite("WidgetPublisher")
struct WidgetPublisherTests {
    @Test("The first update saves a snapshot and asks the widget to reload")
    func first() async {
        let store = FakeStore(), reloads = Reloads()
        await makePublisher(store, reloads).update(play: sugar, show: nil, isPlaying: false, at: now)
        let saved = await store.saved
        #expect(saved.count == 1)
        #expect(saved.first?.title == "Sugar")
        #expect(saved.first?.fetchedAt == now)
        #expect(reloads.count == 1)
    }

    @Test("The same song on the next update changes nothing and does not spend a reload")
    func unchanged() async {
        let store = FakeStore(), reloads = Reloads()
        let publisher = makePublisher(store, reloads)
        await publisher.update(play: sugar, show: nil, isPlaying: false, at: now)
        await publisher.update(play: sugar, show: nil, isPlaying: false, at: now.addingTimeInterval(5))
        #expect(await store.saved.count == 1)
        #expect(reloads.count == 1)
    }

    @Test("A new song is saved and reloads the widget")
    func newSong() async {
        let store = FakeStore(), reloads = Reloads()
        let publisher = makePublisher(store, reloads)
        await publisher.update(play: sugar, show: nil, isPlaying: false, at: now)
        await publisher.update(play: bleeding, show: nil, isPlaying: false, at: now.addingTimeInterval(5))
        #expect(await store.saved.map(\.title) == ["Sugar", "Bleeding Blue"])
        #expect(reloads.count == 2)
    }

    @Test("Starting or stopping playback reloads the widget so its button shows the right icon")
    func playStateChange() async {
        let store = FakeStore(), reloads = Reloads()
        let publisher = makePublisher(store, reloads)
        await publisher.update(play: sugar, show: nil, isPlaying: false, at: now)
        await publisher.update(play: sugar, show: nil, isPlaying: true, at: now.addingTimeInterval(5))
        await publisher.update(play: sugar, show: nil, isPlaying: false, at: now.addingTimeInterval(10))
        #expect(reloads.count == 3)
    }

    @Test("While playing, every update refreshes the playing flag, without reloading the widget again")
    func heartbeat() async {
        let store = FakeStore(), reloads = Reloads()
        let publisher = makePublisher(store, reloads)
        await publisher.update(play: sugar, show: nil, isPlaying: true, at: now)
        await publisher.update(play: sugar, show: nil, isPlaying: true, at: now.addingTimeInterval(5))
        await publisher.update(play: sugar, show: nil, isPlaying: true, at: now.addingTimeInterval(10))
        #expect(await store.playing == [true, true, true])
        #expect(reloads.count == 1)
    }

    @Test("A different show alone is a change worth saving")
    func showChange() async {
        let store = FakeStore(), reloads = Reloads()
        let publisher = makePublisher(store, reloads)
        await publisher.update(play: sugar, show: Show.fixture(hosts: [], programName: "Morning", hostNames: ["A"], tagline: "", imageURI: ""), isPlaying: false, at: now)
        await publisher.update(play: sugar, show: Show.fixture(hosts: [], programName: "Midday", hostNames: ["B"], tagline: "", imageURI: ""), isPlaying: false, at: now.addingTimeInterval(5))
        #expect(await store.saved.map(\.showName) == ["Morning", "Midday"])
    }

    @Test("An airbreak is published as a message, not a song")
    func airbreak() async {
        let store = FakeStore(), reloads = Reloads()
        await makePublisher(store, reloads).update(play: Play(id: 3, playType: .airbreak), show: nil, isPlaying: false, at: now)
        let saved = await store.saved
        #expect(saved.first?.isSong == false)
        #expect(saved.first?.title == "Airbreak")
    }

    @Test("Before the first play has loaded nothing is published")
    func nothingYet() async {
        let store = FakeStore(), reloads = Reloads()
        await makePublisher(store, reloads).update(play: nil, show: nil, isPlaying: false, at: now)
        #expect(await store.saved.isEmpty)
        #expect(reloads.count == 0)
    }
}
