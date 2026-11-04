import CoreGraphics
import Foundation
import ImageIO
import StationKit
import SwiftUI
import Testing
@testable import KEXPPowerExampleSwiftUI

/// A gradient JPEG standing in for album art.
private func sampleArtwork() -> Data? {
    guard
        let context = CGContext(
            data: nil, width: 400, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [CGColor(red: 0.95, green: 0.7, blue: 0.13, alpha: 1), CGColor(red: 0.2, green: 0.1, blue: 0.3, alpha: 1)] as CFArray,
            locations: [0, 1])
    else { return nil }
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 400, y: 400), options: [])
    return context.makeImage().flatMap { ArtworkThumbnail.jpegData(from: $0) }
}

/// The distinct colours in an image, sampled on a grid: a blank render has one, a drawn layout has many.
private func distinctColours(in image: CGImage) -> Int {
    guard
        let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
        let pixels = { context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)); return context.data }()
    else { return 0 }
    let bytes = pixels.assumingMemoryBound(to: UInt8.self)
    var seen = Set<UInt32>()
    for y in stride(from: 0, to: image.height, by: 3) {
        for x in stride(from: 0, to: image.width, by: 3) {
            let i = (y * image.width + x) * 4
            seen.insert(UInt32(bytes[i]) << 16 | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2]))
        }
    }
    return seen.count
}

@MainActor
@Suite("Widget layouts render")
struct WidgetLayoutRenderTests {
    private func content(playing: Bool = false, artwork: Bool = true) -> NowPlayingWidgetContent {
        var content = NowPlayingWidgetContent.sample
        content.artwork = artwork ? sampleArtwork() : nil
        content.isPlaying = playing
        return content
    }

    /// Renders a view at a widget size, and saves a PNG if `WIDGET_RENDER_DIR` is set, for looking at.
    private func render<V: View>(_ view: V, size: CGSize, name: String) throws -> CGImage {
        let framed = view
            .frame(width: size.width, height: size.height)
            .background(.background)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        if let directory = ProcessInfo.processInfo.environment["WIDGET_RENDER_DIR"],
           let destination = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: directory).appendingPathComponent("\(name).png") as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
        return image
    }

    @Test("Small draws its artwork and text", arguments: [false, true])
    func small(playing: Bool) throws {
        let image = try render(SmallNowPlayingView(content: content(playing: playing)), size: CGSize(width: 158, height: 158), name: "small-\(playing)")
        #expect(image.width == 316 && image.height == 316)
        #expect(distinctColours(in: image) > 40)
    }

    @Test("Medium draws, with or without artwork")
    func medium() throws {
        let withArt = try render(MediumNowPlayingView(content: content()).padding(14), size: CGSize(width: 338, height: 158), name: "medium-art")
        let without = try render(MediumNowPlayingView(content: content(artwork: false)).padding(14), size: CGSize(width: 338, height: 158), name: "medium-noart")
        #expect(distinctColours(in: withArt) > 40)
        #expect(distinctColours(in: without) > 10)
    }

    @Test("Large draws its details, links and comment, playing or not", arguments: [false, true])
    func large(playing: Bool) throws {
        let image = try render(LargeNowPlayingView(content: content(playing: playing)).padding(16), size: CGSize(width: 338, height: 354), name: "large-\(playing)")
        #expect(distinctColours(in: image) > 40)
    }

    @Test("A snapshot with no show, no links and no comment still lays out")
    func sparse() throws {
        var sparse = content()
        sparse.snapshot = WidgetSnapshot(nowPlaying: .message("Airbreak"), stationName: "KEXP", fallbackArtworkURL: nil, fetchedAt: Date())
        let image = try render(LargeNowPlayingView(content: sparse).padding(16), size: CGSize(width: 338, height: 354), name: "large-airbreak")
        #expect(distinctColours(in: image) > 10)
    }

    @Test("The time line says when a song was last played")
    func timeLine() {
        #expect(content().timeLine.hasPrefix("Last played "))
        var message = content()
        message.snapshot = WidgetSnapshot(nowPlaying: .message("Airbreak"), stationName: "KEXP", fallbackArtworkURL: nil, fetchedAt: Date())
        #expect(message.timeLine.hasPrefix("As of "))
    }
}
