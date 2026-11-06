//
//  ReviewArtworkStore.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import StationKit

/// Keeps the album covers for held songs as small image files, so a review made later does not depend on a link that
/// has expired or on being online.
struct ReviewArtworkStore: Sendable {
    let directory: URL
    private let fetch: @Sendable (URL) async -> Data?

    /// - Parameters:
    ///   - directory: The folder the images live in, created on first save.
    ///   - fetch: Downloads an image's bytes, or `nil` if it cannot; the app's one enforces its host allow-list.
    init(directory: URL, fetch: @escaping @Sendable (URL) async -> Data?) {
        self.directory = directory
        self.fetch = fetch
    }

    /// Where a saved image lives.
    func fileURL(for name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    /// Downloads an image, shrinks it, and writes it.
    /// - Parameters:
    ///   - url: Where the cover is; `nil` saves nothing.
    ///   - name: The file name to save as.
    /// - Returns: The file name, or `nil` if there was no link, the download failed, or the bytes were not an image.
    func save(from url: URL?, as name: String) async -> String? {
        guard let url, let data = await fetch(url), let thumbnail = ArtworkThumbnail.make(from: data) else { return nil }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try thumbnail.write(to: fileURL(for: name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    /// Deletes saved images; names that are `nil` or already gone are ignored.
    func remove(_ names: [String?]) {
        for name in names.compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: fileURL(for: name))
        }
    }

    /// Deletes every file that is not in `names`, so a crash between writing and queueing cannot leave files behind.
    func sweep(keeping names: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for file in files where !names.contains(file) {
            try? FileManager.default.removeItem(at: fileURL(for: file))
        }
    }
}

extension ReviewArtworkStore {
    /// The domains review covers may come from: KEXP's, the archive that hosts most album covers, and Apple's image
    /// host for the Apple Music suggestion (*the exact domain is to be confirmed on a device*).
    static let allowedDomains = ["kexp.org", "archive.org", "mzstatic.com"]

    /// A download function that refuses any link that is not https on one of `allowedDomains`, the same rule the
    /// player's artwork loader applies, so a link in a station's data cannot send the app to an unexpected host.
    /// - Parameters:
    ///   - allowedDomains: Each matches the host itself or any subdomain.
    ///   - download: Fetches the bytes; the network by default.
    static func guardedFetch(
        allowedDomains: [String] = ReviewArtworkStore.allowedDomains,
        download: @escaping @Sendable (URL) async -> Data? = { url in try? await URLSession.shared.data(from: url).0 }
    ) -> @Sendable (URL) async -> Data? {
        let loader = ArtworkLoader(allowedDomains: allowedDomains)
        return { url in
            guard loader.isAllowed(url) else { return nil }
            return await download(url)
        }
    }
}
