//
//  ArtworkLoader.swift
//  KEXPPowerExampleSwiftUI
//

import UIKit

/// Loads artwork images for the player, never trapping and never contacting an unexpected host.
///
/// Images come from URLs in KEXP's API responses, so every URL is checked against a small
/// allow-list before any request is made. Results are cached with a fixed memory cost limit.
actor ArtworkLoader {
    /// Fetches the bytes at a URL. Injected so tests need no network.
    typealias Fetch = @Sendable (URL) async throws -> Data

    /// Hosts artwork may come from, matched on the host itself or any subdomain.
    nonisolated static let allowedDomains = ["kexp.org", "archive.org"]

    /// Upper bound for the in-memory cache, in bytes of decoded pixels.
    nonisolated static let cacheCostLimit = 4 * 1024 * 1024

    nonisolated static let fetchOverNetwork: Fetch = { url in
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    private let fetch: Fetch
    private let cache = NSCache<NSString, UIImage>()

    init(fetch: @escaping Fetch = ArtworkLoader.fetchOverNetwork) {
        self.fetch = fetch
        cache.totalCostLimit = Self.cacheCostLimit
    }

    /// Whether artwork may be requested from this URL: https, on an allowed domain.
    /// - Parameter url: The artwork URL.
    nonisolated static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return allowedDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// The image at a URL string, or `nil` if the string is unusable, the host is not allowed,
    /// the request fails, or the data is not an image.
    /// - Parameter urlString: The artwork URL as KEXP's API returns it.
    func image(for urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString), Self.isAllowed(url) else { return nil }

        let key = url.absoluteString as NSString
        if let cached = cache.object(forKey: key) { return cached }

        guard
            let data = try? await fetch(url),
            let image = UIImage(data: data)
        else { return nil }

        let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }
}
