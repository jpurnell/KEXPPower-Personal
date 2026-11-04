//
//  UserDefaultsSaveLedger.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import StationKit

/// A ``SaveLedger`` kept in `UserDefaults`, so "already saved" and the default playlist survive a relaunch.
///
/// It holds the most recent `capacity` (song, playlist) pairs; older ones are forgotten.
actor UserDefaultsSaveLedger: SaveLedger {
    static let defaultPlaylistKey = "saveLedger.defaultPlaylistID"
    static let savedKey = "saveLedger.saved"

    private let defaults: UserDefaults
    private let capacity: Int

    /// - Parameters:
    ///   - suiteName: The defaults suite to keep it in; the standard defaults when `nil`. A test supplies its own.
    ///   - capacity: The most (song, playlist) pairs to remember; at least one.
    init(suiteName: String? = nil, capacity: Int = 1000) {
        self.defaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        self.capacity = max(1, capacity)
    }

    func defaultPlaylistID() -> String? {
        defaults.string(forKey: Self.defaultPlaylistKey)
    }

    func setDefaultPlaylistID(_ id: String) {
        defaults.set(id, forKey: Self.defaultPlaylistKey)
    }

    func isSaved(songID: String, playlistID: String) -> Bool {
        stored().contains(Self.key(songID, playlistID))
    }

    func markSaved(songID: String, playlistID: String) {
        let key = Self.key(songID, playlistID)
        var pairs = stored()
        guard !pairs.contains(key) else { return }
        pairs.append(key)
        if pairs.count > capacity { pairs.removeFirst(pairs.count - capacity) }
        defaults.set(pairs, forKey: Self.savedKey)
    }

    /// The saved pairs, oldest first; anything unreadable counts as none.
    private func stored() -> [String] {
        defaults.stringArray(forKey: Self.savedKey) ?? []
    }

    private static func key(_ songID: String, _ playlistID: String) -> String {
        "\(playlistID)\u{1F}\(songID)"
    }
}
