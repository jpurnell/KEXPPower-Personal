import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

@MainActor
@Suite("UserDefaultsReviewStore")
struct UserDefaultsReviewStoreTests {
    private func makeStore() -> (UserDefaultsReviewStore, UserDefaults) {
        let name = "review-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return (UserDefaultsReviewStore(defaults: defaults), defaults)
    }

    private func entry(_ id: Int) -> ReviewEntry {
        ReviewEntry(
            id: id, playedTitle: "T", playedArtist: "A", playedAlbum: nil, candidateID: "c", candidateTitle: "T",
            candidateArtist: "A", candidateAlbum: "Greatest Hits", extraPlaylistID: "p", extraPlaylistName: "Road",
            heldAt: Date(timeIntervalSince1970: 1_000), playedArtworkFile: "1-played.jpg", candidateArtworkFile: nil)
    }

    @Test("Nothing saved reads as empty")
    func empty() {
        #expect(makeStore().0.load().isEmpty)
    }

    @Test("Entries round-trip with every field, in order")
    func roundTrip() {
        let (store, _) = makeStore()
        store.save([entry(2), entry(1)])
        #expect(store.load() == [entry(2), entry(1)])
        #expect(store.load()[0].extraPlaylist?.name == "Road")
    }

    @Test("Unreadable saved data reads as empty instead of failing")
    func unreadable() {
        let (store, defaults) = makeStore()
        defaults.set(Data("not json".utf8), forKey: UserDefaultsReviewStore.key)
        #expect(store.load().isEmpty)
    }

    @Test("Saving replaces what was there")
    func replaces() {
        let (store, _) = makeStore()
        store.save([entry(1), entry(2)])
        store.save([entry(3)])
        #expect(store.load().map(\.id) == [3])
    }
}
