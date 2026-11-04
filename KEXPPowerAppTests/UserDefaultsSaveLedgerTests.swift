import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

/// A throwaway defaults suite per test; the test removes it afterwards.
private func makeSuite() -> String { "UserDefaultsSaveLedgerTests-\(UUID().uuidString)" }
private func remove(_ suite: String) { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

@Suite("UserDefaultsSaveLedger")
struct UserDefaultsSaveLedgerTests {
    @Test("A fresh ledger has no default playlist and nothing saved")
    func fresh() async {
        let suite = makeSuite()
        defer { remove(suite) }
        let ledger = UserDefaultsSaveLedger(suiteName: suite)
        #expect(await ledger.defaultPlaylistID() == nil)
        #expect(await !ledger.isSaved(songID: "s", playlistID: "p"))
    }

    @Test("The default playlist and saved songs survive a new ledger over the same defaults")
    func persists() async {
        let suite = makeSuite()
        defer { remove(suite) }
        let first = UserDefaultsSaveLedger(suiteName: suite)
        await first.setDefaultPlaylistID("p-kexp")
        await first.markSaved(songID: "song-1", playlistID: "p-kexp")

        let second = UserDefaultsSaveLedger(suiteName: suite)
        #expect(await second.defaultPlaylistID() == "p-kexp")
        #expect(await second.isSaved(songID: "song-1", playlistID: "p-kexp"))
        #expect(await !second.isSaved(songID: "song-1", playlistID: "p-other"))
        #expect(await !second.isSaved(songID: "song-2", playlistID: "p-kexp"))
    }

    @Test("Past its capacity the oldest saved pairs are forgotten, and that persists too")
    func capacity() async {
        let suite = makeSuite()
        defer { remove(suite) }
        let ledger = UserDefaultsSaveLedger(suiteName: suite, capacity: 2)
        await ledger.markSaved(songID: "a", playlistID: "p")
        await ledger.markSaved(songID: "b", playlistID: "p")
        await ledger.markSaved(songID: "c", playlistID: "p")

        let reopened = UserDefaultsSaveLedger(suiteName: suite, capacity: 2)
        #expect(await !reopened.isSaved(songID: "a", playlistID: "p"))
        #expect(await reopened.isSaved(songID: "b", playlistID: "p"))
        #expect(await reopened.isSaved(songID: "c", playlistID: "p"))
    }

    @Test("Marking the same pair twice keeps one entry")
    func idempotent() async {
        let suite = makeSuite()
        defer { remove(suite) }
        let ledger = UserDefaultsSaveLedger(suiteName: suite, capacity: 2)
        await ledger.markSaved(songID: "a", playlistID: "p")
        await ledger.markSaved(songID: "a", playlistID: "p")
        await ledger.markSaved(songID: "b", playlistID: "p")
        #expect(await ledger.isSaved(songID: "a", playlistID: "p"))
        #expect(await ledger.isSaved(songID: "b", playlistID: "p"))
    }

    @Test("Unreadable stored data is treated as empty, not a crash")
    func corrupt() async {
        let suite = makeSuite()
        defer { remove(suite) }
        UserDefaults(suiteName: suite)?.set("not an array", forKey: UserDefaultsSaveLedger.savedKey)
        let ledger = UserDefaultsSaveLedger(suiteName: suite)
        #expect(await !ledger.isSaved(songID: "a", playlistID: "p"))
        await ledger.markSaved(songID: "a", playlistID: "p")
        #expect(await ledger.isSaved(songID: "a", playlistID: "p"))
    }

    @Test("Saving to playlists is supported where MusicKit can write to the library, and not on the Mac")
    func platformSupport() {
        #if os(macOS)
        #expect(!AppSongSaver.canSaveToPlaylists)
        #else
        #expect(AppSongSaver.canSaveToPlaylists)
        #endif
    }
}
