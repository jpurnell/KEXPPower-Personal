import Testing
import UIKit
@testable import KEXPPowerExampleSwiftUI

/// Counts fetches made by a test's stub, safely across concurrency domains.
private actor FetchCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

private func pngData() throws -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1   // pixels == points, so the decoded size does not depend on the device
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2), format: format)
    let image = renderer.image { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    }
    return try #require(image.pngData())
}

@Suite("ArtworkLoader host allow-list")
struct ArtworkHostTests {
    @Test("https URLs on kexp.org and archive.org, including subdomains, are allowed",
          arguments: [
              "https://kexp.org/static/assets/img/kexp_logo.jpg",
              "https://www.kexp.org/media/filer_public/d5/4b/drivetime-800x800.jpg",
              "https://ia800501.us.archive.org/23/items/mbid-5c32edc4/thumb500.jpg",
              "https://archive.org/download/x/y.jpg",
          ])
    func allowed(_ string: String) throws {
        #expect(ArtworkLoader.isAllowed(try #require(URL(string: string))))
    }

    @Test("Other hosts, look-alike hosts, and plain http are refused",
          arguments: [
              "https://evil.example.com/a.jpg",
              "https://notarchive.org/a.jpg",
              "https://archive.org.evil.com/a.jpg",
              "file:///etc/hosts",
          ])
    func refused(_ string: String) throws {
        #expect(!ArtworkLoader.isAllowed(try #require(URL(string: string))))
    }

    @Test("A permitted host over plain http is refused")
    func httpRefused() throws {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "www.kexp.org"
        components.path = "/a.jpg"
        #expect(!ArtworkLoader.isAllowed(try #require(components.url)))
    }
}

@Suite("ArtworkLoader loading")
struct ArtworkLoadingTests {
    private let goodURL = "https://www.kexp.org/media/a.jpg"

    @Test("An empty or malformed string yields nil and makes no request")
    func malformed() async {
        let counter = FetchCounter()
        let loader = ArtworkLoader { _ in await counter.increment(); return Data() }
        #expect(await loader.image(for: "") == nil)
        #expect(await loader.image(for: "not a url") == nil)
        #expect(await counter.count == 0)
    }

    @Test("A host outside the allow-list yields nil and makes no request")
    func disallowedHost() async {
        let counter = FetchCounter()
        let loader = ArtworkLoader { _ in await counter.increment(); return Data() }
        #expect(await loader.image(for: "https://evil.example.com/a.jpg") == nil)
        #expect(await counter.count == 0)
    }

    @Test("A failed fetch yields nil instead of crashing")
    func fetchFailure() async {
        let loader = ArtworkLoader { _ in throw URLError(.notConnectedToInternet) }
        #expect(await loader.image(for: goodURL) == nil)
    }

    @Test("Data that is not an image yields nil")
    func notAnImage() async {
        let loader = ArtworkLoader { _ in Data("not an image".utf8) }
        #expect(await loader.image(for: goodURL) == nil)
    }

    @Test("A good fetch returns the image, and a repeat is served from cache")
    func successAndCache() async throws {
        let data = try pngData()
        let counter = FetchCounter()
        let loader = ArtworkLoader { _ in await counter.increment(); return data }
        let first = await loader.image(for: goodURL)
        #expect(first?.size == CGSize(width: 2, height: 2))
        _ = await loader.image(for: goodURL)
        #expect(await counter.count == 1)
    }
}
