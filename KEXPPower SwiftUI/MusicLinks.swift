//
//  MusicLinks.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import OSLog

/// Links out of the app: search pages on other music services, and the links DJs put in their comments.
enum MusicLinks {
    private static let logger = Logger(#function)

    /// Characters left as-is when a name becomes part of a URL. Everything else, including `/`, `&`, and `+`,
    /// is percent-encoded so a name cannot change the structure of the URL it is placed in.
    private static let unreserved = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    private static let linkDetector: NSDataDetector? = {
        do {
            return try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        } catch {
            logger.error("Link detection unavailable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()

    /// A Spotify search for a track.
    /// - Parameters:
    ///   - artist: The artist, if known.
    ///   - track: The track title, if known.
    /// - Returns: The search URL, or `nil` when both are missing.
    static func spotifySearchURL(artist: String?, track: String?) -> URL? {
        guard let encoded = encodedSearchTerm(artist, track) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "open.spotify.com"
        components.percentEncodedPath = "/search/" + encoded
        return components.url
    }

    /// A Bandcamp search for an album.
    /// - Parameters:
    ///   - artist: The artist, if known.
    ///   - album: The album title, if known.
    /// - Returns: The search URL, or `nil` when both are missing.
    static func bandcampSearchURL(artist: String?, album: String?) -> URL? {
        guard let encoded = encodedSearchTerm(artist, album) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "bandcamp.com"
        components.path = "/search"
        components.percentEncodedQuery = "q=" + encoded
        return components.url
    }

    /// The web links (http and https) in a piece of text, in order and without repeats.
    /// - Parameter text: A DJ's comment.
    static func links(in text: String) -> [URL] {
        var seen = Set<URL>()
        return webMatches(in: text).compactMap { match in
            seen.insert(match.url).inserted ? match.url : nil
        }
    }

    /// The comment with its web links made tappable.
    /// - Parameter text: A DJ's comment.
    static func linkedComment(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        for match in webMatches(in: text) {
            if let range = Range(match.range, in: attributed) {
                attributed[range].link = match.url
            }
        }
        return attributed
    }

    private static func webMatches(in text: String) -> [(url: URL, range: NSRange)] {
        guard let linkDetector, !text.isEmpty else { return [] }
        let whole = NSRange(text.startIndex..., in: text)
        return linkDetector.matches(in: text, range: whole).compactMap { match in
            guard let url = match.url, url.scheme == "https" || url.scheme == "http" else { return nil }
            return (url, match.range)
        }
    }

    private static func encodedSearchTerm(_ parts: String?...) -> String? {
        let words = parts.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        return words.joined(separator: " ").addingPercentEncoding(withAllowedCharacters: unreserved)
    }
}
