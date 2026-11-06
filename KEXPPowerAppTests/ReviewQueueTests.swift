import CoreGraphics
import Foundation
import StationKit
import Testing
@testable import KEXPPowerExampleSwiftUI

/// A store that keeps entries in memory and counts writes.
@MainActor
private final class MemoryReviewStore: ReviewStore {
    var entries: [ReviewEntry] = []
    var writes = 0
    func load() -> [ReviewEntry] { entries }
    func save(_ entries: [ReviewEntry]) {
        self.entries = entries
        writes += 1
    }
}

private func jpeg() throws -> Data {
    let context = try #require(CGContext(
        data: nil, width: 600, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
    let image = try #require(context.makeImage())
    return try #require(ArtworkThumbnail.jpegData(from: image))
}

private func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("review-\(UUID().uuidString)", isDirectory: true)
}

private func held(
    _ id: Int, playedArt: URL? = URL(string: "https://example.com/kexp.jpg"),
    candidateArt: URL? = URL(string: "https://example.com/apple.jpg")
) -> ReviewQueue.Held {
    ReviewQueue.Held(
        playID: id, playedTitle: "Fly Like an Eagle", playedArtist: "Steve Miller Band", playedAlbum: "Fly Like an Eagle",
        playedArtworkURL: playedArt,
        candidate: CatalogSong(id: "c\(id)", title: "Fly Like an Eagle", artist: "Steve Miller Band", album: "Greatest Hits 1974-78"),
        candidateArtworkURL: candidateArt, extraPlaylist: nil)
}

@MainActor
@Suite("ReviewQueue")
struct ReviewQueueTests {
    private func make(
        capacity: Int = 200, store: MemoryReviewStore = MemoryReviewStore(), isSaved: @escaping @MainActor (Int) -> Bool = { _ in false },
        fetch: @escaping @Sendable (URL) async -> Data? = { _ in nil }
    ) -> (ReviewQueue, MemoryReviewStore, ReviewArtworkStore) {
        let artwork = ReviewArtworkStore(directory: tempDirectory(), fetch: fetch)
        return (ReviewQueue(store: store, artwork: artwork, capacity: capacity, isSaved: isSaved), store, artwork)
    }

    @Test("A held match is queued with what KEXP played and what Apple Music suggested")
    func enqueues() async {
        let (queue, _, _) = make()
        let queued = await queue.enqueue(held(1))
        #expect(queued)
        #expect(queue.count == 1)
        let entry = queue.entries[0]
        #expect(entry.id == 1)
        #expect(entry.playedAlbum == "Fly Like an Eagle")
        #expect(entry.candidate.album == "Greatest Hits 1974-78")
    }

    @Test("The same play is not queued twice")
    func noDuplicates() async {
        let (queue, _, _) = make()
        _ = await queue.enqueue(held(1))
        let again = await queue.enqueue(held(1))
        #expect(!again)
        #expect(queue.count == 1)
    }

    @Test("A song already saved is not queued")
    func refusesSaved() async {
        let (queue, _, _) = make(isSaved: { $0 == 7 })
        let queued = await queue.enqueue(held(7))
        #expect(!queued)
        #expect(queue.count == 0)
    }

    @Test("Newest first; past the cap the oldest is dropped")
    func capDropsOldest() async {
        let (queue, _, _) = make(capacity: 2)
        for id in 1...3 { _ = await queue.enqueue(held(id)) }
        #expect(queue.entries.map(\.id) == [3, 2])
    }

    @Test("The queue survives being rebuilt from its store")
    func persists() async {
        let store = MemoryReviewStore()
        let (first, _, _) = make(store: store)
        _ = await first.enqueue(held(1))
        let (second, _, _) = make(store: store)
        #expect(second.entries.map(\.id) == [1])
    }

    @Test("Rejecting removes the entry and its pictures")
    func rejects() async throws {
        let data = try jpeg()
        let (queue, store, artwork) = make(fetch: { _ in data })
        _ = await queue.enqueue(held(1))
        let entry = queue.entries[0]
        let file = try #require(entry.candidateArtworkFile)
        #expect(FileManager.default.fileExists(atPath: artwork.fileURL(for: file).path))
        queue.reject(entry)
        #expect(queue.count == 0)
        #expect(store.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: artwork.fileURL(for: file).path))
    }

    @Test("Adding saves through the given closure and removes the entry only if it was saved")
    func adds() async {
        let (queue, _, _) = make()
        _ = await queue.enqueue(held(1))
        _ = await queue.enqueue(held(2))
        await queue.add(queue.entries[0]) { _ in false }
        #expect(queue.count == 2)
        let target = queue.entries[0]
        await queue.add(target) { _ in true }
        #expect(!queue.contains(target.id))
        #expect(queue.count == 1)
    }

    @Test("Both pictures are saved as small files and the entry points at them")
    func savesArtwork() async throws {
        let data = try jpeg()
        let (queue, _, artwork) = make(fetch: { _ in data })
        _ = await queue.enqueue(held(1))
        let entry = queue.entries[0]
        let played = try #require(entry.playedArtworkFile)
        let candidate = try #require(entry.candidateArtworkFile)
        #expect(played != candidate)
        let saved = try Data(contentsOf: artwork.fileURL(for: candidate))
        #expect(saved.count < data.count)
    }

    @Test("A picture that cannot be fetched still queues the entry, without that picture")
    func missingArtworkStillQueues() async {
        let (queue, _, _) = make(fetch: { _ in nil })
        let queued = await queue.enqueue(held(1))
        #expect(queued)
        #expect(queue.entries[0].playedArtworkFile == nil)
        #expect(queue.entries[0].candidateArtworkFile == nil)
    }

    @Test("No artwork link means nothing is fetched")
    func noLinksNoFetch() async {
        let (queue, _, _) = make(fetch: { _ in Data([1, 2, 3]) })
        _ = await queue.enqueue(held(1, playedArt: nil, candidateArt: nil))
        #expect(queue.entries[0].playedArtworkFile == nil)
        #expect(queue.entries[0].candidateArtworkFile == nil)
    }

    @Test("Bytes that are not an image are not kept")
    func nonImageNotKept() async {
        let (queue, _, _) = make(fetch: { _ in Data("<html>500</html>".utf8) })
        _ = await queue.enqueue(held(1))
        #expect(queue.entries[0].candidateArtworkFile == nil)
    }

    @Test("A file with no entry is swept; files of queued entries are kept")
    func sweeps() async throws {
        let data = try jpeg()
        let (queue, _, artwork) = make(fetch: { _ in data })
        _ = await queue.enqueue(held(1))
        let stray = artwork.fileURL(for: "stray.jpg")
        try FileManager.default.createDirectory(at: stray.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: stray)
        queue.sweepOrphans()
        #expect(!FileManager.default.fileExists(atPath: stray.path))
        let kept = try #require(queue.entries[0].candidateArtworkFile)
        #expect(FileManager.default.fileExists(atPath: artwork.fileURL(for: kept).path))
    }
}

/// Counts how many downloads the guarded fetcher let through.
private actor Fetched {
    private(set) var urls: [URL] = []
    func record(_ url: URL) { urls.append(url) }
}

@Suite("ReviewArtworkStore guarded fetch")
struct ReviewArtworkGuardTests {
    @Test("Only https links on an allowed domain, or its subdomains, are downloaded")
    func allowList() async throws {
        let fetched = Fetched()
        let fetch = ReviewArtworkStore.guardedFetch(allowedDomains: ["kexp.org", "mzstatic.com"]) { url in
            await fetched.record(url)
            return Data([1])
        }
        _ = await fetch(try #require(URL(string: "https://kexp.org/a.jpg")))
        _ = await fetch(try #require(URL(string: "https://is1-ssl.mzstatic.com/b.jpg")))
        _ = await fetch(try #require(URL(string: "https://evil.example.com/c.jpg")))
        var plain = URLComponents()
        plain.scheme = "http"
        plain.host = "kexp.org"
        plain.path = "/d.jpg"
        _ = await fetch(try #require(plain.url))
        _ = await fetch(try #require(URL(string: "https://notkexp.org/e.jpg")))
        #expect(await fetched.urls.map(\.host) == ["kexp.org", "is1-ssl.mzstatic.com"])
    }

    @Test("A failed download is nil, not an error")
    func failureIsNil() async throws {
        let fetch = ReviewArtworkStore.guardedFetch(allowedDomains: ["kexp.org"]) { _ in nil }
        #expect(await fetch(try #require(URL(string: "https://kexp.org/a.jpg"))) == nil)
    }
}
