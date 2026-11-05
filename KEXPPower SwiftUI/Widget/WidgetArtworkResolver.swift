//
//  WidgetArtworkResolver.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import OSLog
import StationKit

/// Finds the artwork a widget shows: the first address that gives a real image, scaled small enough for a widget.
///
/// A cover can fail for reasons nobody controls (archive.org answers some albums with an error page), so the caller
/// passes the cover first and the station's logo after it, and the widget never shows an empty square.
struct WidgetArtworkResolver: Sendable {
    private let loader: ArtworkLoader
    private let fetch: ArtworkLoader.Fetch
    private let logger = Logger(subsystem: "com.JPEnterprises.Spinner.widget", category: "WidgetArtworkResolver")

    /// - Parameters:
    ///   - allowedDomains: The hosts artwork may be fetched from, each matching itself and its subdomains.
    ///   - fetch: How to download an address; the network by default.
    init(allowedDomains: [String], fetch: @escaping ArtworkLoader.Fetch = ArtworkLoader.fetchOverNetwork) {
        loader = ArtworkLoader(allowedDomains: allowedDomains, fetch: fetch)
        self.fetch = fetch
    }

    /// The first usable artwork among the addresses, as scaled JPEG data.
    /// - Parameters:
    ///   - urls: Addresses to try in order; missing ones are skipped.
    ///   - maxPixel: The longest side to allow, in pixels.
    /// - Returns: The image data, or `nil` if no address gave an image.
    func artwork(from urls: [URL?], maxPixel: Int = 400) async -> Data? {
        for case let url? in urls {
            guard loader.isAllowed(url) else { continue }
            do {
                let data = try await fetch(url)
                if let thumbnail = ArtworkThumbnail.make(from: data, maxPixel: maxPixel) { return thumbnail }
                let skipped = "Artwork at \(url.absoluteString) is not an image; trying the next address"
                logger.info("\(skipped, privacy: .public)")
            } catch {
                let failed = "Could not download artwork at \(url.absoluteString): \(error.localizedDescription)"
                logger.error("\(failed, privacy: .public)")
            }
        }
        return nil
    }
}
