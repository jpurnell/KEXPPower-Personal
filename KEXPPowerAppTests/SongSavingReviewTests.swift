import Foundation
import KEXPPower
import StationKit
import Testing
@testable import KEXPPowerExampleSwiftUI

private let kexp = PlaylistSummary(id: "p-kexp", name: "KEXP")
private let road = PlaylistSummary(id: "p-road", name: "Road Trip")
private let guess = CatalogSong(id: "cat-1", title: "Bleeding Blue", artist: "Cults", album: "Static")
private let play = Play(id: 42, song: "Bleeding Blue", artist: "Cults", playType: .trackplay)

private actor FetchLog {
    private(set) var urls: [URL] = []
    func record(_ url: URL) { urls.append(url) }
}

@MainActor
private final class MemoryStore: ReviewStore {
    var entries: [ReviewEntry] = []
    func load() -> [ReviewEntry] { entries }
    func save(_ entries: [ReviewEntry]) { self.entries = entries }
}

@MainActor
private func makeModel(
    save: SaveOutcome, confirm: SaveOutcome = .finished(guess, added: [kexp], failed: [])
) -> (SongSavingModel, ReviewQueue) {
    let model = SongSavingModel(
        save: { _, _ in save }, confirm: { _, _ in confirm }, loadPlaylists: { [] })
    let queue = ReviewQueue(
        store: MemoryStore(), artwork: ReviewArtworkStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            fetch: { _ in nil }),
        isSaved: { [weak model] id in
            if case .saved = model?.state(for: Play(id: id, song: "x", artist: "y", playType: .trackplay)) { return true }
            return false
        })
    model.reviewQueue = queue
    return (model, queue)
}

@MainActor
@Suite("SongSavingModel and the review queue")
struct SongSavingReviewTests {
    @Test("From the car a text match is held for review, not left as a prompt, and the play shows as held")
    func carHoldsGuesses() async {
        let (model, queue) = makeModel(save: .needsConfirmation(guess))
        await model.save(play, holdingGuesses: true)
        #expect(model.state(for: play) == .heldForReview)
        #expect(queue.entries.map(\.id) == [42])
        #expect(queue.entries[0].candidateID == "cat-1")
        #expect(queue.entries[0].playedTitle == "Bleeding Blue")
    }

    @Test("From the phone a text match still asks at once")
    func phoneStillAsks() async {
        let (model, queue) = makeModel(save: .needsConfirmation(guess))
        await model.save(play)
        #expect(model.state(for: play) == .confirming(guess))
        #expect(queue.count == 0)
    }

    @Test("An exact match is added at once even from the car")
    func exactMatchAdds() async {
        let (model, queue) = makeModel(save: .finished(guess, added: [kexp], failed: []))
        await model.save(play, holdingGuesses: true)
        #expect(model.state(for: play) == .saved(playlists: ["KEXP"], failedPlaylists: []))
        #expect(queue.count == 0)
    }

    @Test("Review later on the phone's prompt holds the suggestion")
    func reviewLater() async {
        let (model, queue) = makeModel(save: .needsConfirmation(guess))
        await model.save(play)
        await model.holdForReview(guess, for: play)
        #expect(model.state(for: play) == .heldForReview)
        #expect(queue.entries.map(\.id) == [42])
    }

    @Test("The second playlist chosen with the press is kept for when the entry is confirmed")
    func extraPlaylistKept() async {
        let (model, queue) = makeModel(save: .needsConfirmation(guess))
        await model.save(play, alsoTo: road, holdingGuesses: true)
        #expect(queue.entries[0].extraPlaylist == road)
    }

    @Test("Confirming a held entry saves it and says so; the entry's play shows as saved")
    func confirmHeld() async {
        let (model, queue) = makeModel(save: .needsConfirmation(guess))
        await model.save(play, holdingGuesses: true)
        let saved = await model.confirmHeld(queue.entries[0])
        #expect(saved)
        #expect(model.state(for: play) == .saved(playlists: ["KEXP"], failedPlaylists: []))
    }

    @Test("A held entry that fails to save reports it was not saved, so it stays queued")
    func confirmFails() async {
        let (model, queue) = makeModel(save: .needsConfirmation(guess), confirm: .unavailable)
        await model.save(play, holdingGuesses: true)
        let saved = await model.confirmHeld(queue.entries[0])
        #expect(!saved)
    }

    @Test("Rejecting a held song returns the play to idle")
    func rejectResets() async {
        let (model, queue) = makeModel(save: .needsConfirmation(guess))
        await model.save(play, holdingGuesses: true)
        model.releaseHeld(queue.entries[0])
        #expect(model.state(for: play) == .idle)
    }

    @Test("The Apple Music suggestion's cover link is the one fetched and saved with the held song")
    func candidateCoverIsFetched() async {
        let cover = URL(fileURLWithPath: "/covers/greatest-hits.jpg")
        let withCover = CatalogSong(id: "cat-2", title: "Bleeding Blue", artist: "Cults", album: "Greatest Hits", artworkURL: cover)
        let fetched = FetchLog()
        let model = SongSavingModel(
            save: { _, _ in .needsConfirmation(withCover) }, confirm: { _, _ in .notFound }, loadPlaylists: { [] })
        model.reviewQueue = ReviewQueue(
            store: MemoryStore(),
            artwork: ReviewArtworkStore(
                directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                fetch: { url in await fetched.record(url); return nil }))
        await model.save(play, holdingGuesses: true)
        #expect(await fetched.urls.contains(cover))
    }

    @Test("Holding without a queue falls back to asking, so nothing is lost")
    func noQueueFallsBack() async {
        let model = SongSavingModel(
            save: { _, _ in .needsConfirmation(guess) }, confirm: { _, _ in .notFound }, loadPlaylists: { [] })
        await model.save(play, holdingGuesses: true)
        #expect(model.state(for: play) == .confirming(guess))
    }
}
