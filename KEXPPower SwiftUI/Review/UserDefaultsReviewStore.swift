//
//  UserDefaultsReviewStore.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// A ``ReviewStore`` kept as JSON in `UserDefaults`, so held songs survive a relaunch.
@MainActor
struct UserDefaultsReviewStore: ReviewStore {
    static let key = "review.entries"

    private let defaults: UserDefaults

    /// - Parameter defaults: Where to keep it; the standard defaults in the app, a private suite in a test.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [ReviewEntry] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([ReviewEntry].self, from: data)) ?? []
    }

    func save(_ entries: [ReviewEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
