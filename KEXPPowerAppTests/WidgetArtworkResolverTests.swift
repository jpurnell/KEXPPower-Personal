import CoreGraphics
import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

/// A small solid-colour JPEG, standing in for a downloaded cover.
private func coverData() throws -> Data {
    let context = try #require(CGContext(
        data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(red: 0.9, green: 0.7, blue: 0.1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
    let image = try #require(context.makeImage())
    return try #require(ArtworkThumbnail.jpegData(from: image))
}

@Suite("WidgetArtworkResolver")
struct WidgetArtworkResolverTests {
    private let cover = URL(string: "https://archive.org/cover.jpg")
    private let logo = URL(string: "https://kexp.org/logo.jpg")

    private func resolver(serving served: [URL: Data], failing: Set<URL> = []) -> WidgetArtworkResolver {
        WidgetArtworkResolver(
            allowedDomains: ["kexp.org", "archive.org"],
            fetch: { url in
                if failing.contains(url) { throw URLError(.timedOut) }
                guard let data = served[url] else { throw URLError(.fileDoesNotExist) }
                return data
            })
    }

    @Test("The first address that gives an image wins")
    func firstWins() async throws {
        let cover = try #require(self.cover)
        let logo = try #require(self.logo)
        let data = try coverData()
        let result = await resolver(serving: [cover: data, logo: data]).artwork(from: [cover, logo])
        #expect(result != nil)
    }

    @Test("A cover that cannot be had gives way to the next address, the station logo")
    func fallsBackWhenTheDownloadFails() async throws {
        let cover = try #require(self.cover)
        let logo = try #require(self.logo)
        let result = await resolver(serving: [logo: try coverData()], failing: [cover]).artwork(from: [cover, logo])
        #expect(result != nil)
    }

    @Test("An error page served as the cover is not an image, so the next address is used")
    func fallsBackWhenTheBodyIsNotAnImage() async throws {
        let cover = try #require(self.cover)
        let logo = try #require(self.logo)
        let errorPage = Data("<html>500</html>".utf8)
        let result = await resolver(serving: [cover: errorPage, logo: try coverData()]).artwork(from: [cover, logo])
        #expect(result != nil)
    }

    @Test("A host that is not on the list is never contacted")
    func skipsDisallowedHosts() async throws {
        let stranger = try #require(URL(string: "https://example.com/art.jpg"))
        let logo = try #require(self.logo)
        let asked = Asked()
        let resolver = WidgetArtworkResolver(
            allowedDomains: ["kexp.org"],
            fetch: { url in
                await asked.record(url)
                return try coverData()
            })
        _ = await resolver.artwork(from: [stranger, logo])
        #expect(await asked.urls == [logo])
    }

    @Test("Nothing usable gives nil, and missing addresses are skipped")
    func nothingUsable() async throws {
        let cover = try #require(self.cover)
        #expect(await resolver(serving: [:]).artwork(from: [nil, cover]) == nil)
        #expect(await resolver(serving: [:]).artwork(from: []) == nil)
    }
}

private actor Asked {
    private(set) var urls: [URL] = []
    func record(_ url: URL) { urls.append(url) }
}
