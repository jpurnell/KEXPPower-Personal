import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import KEXPPowerExampleSwiftUI

/// A solid-colour JPEG of a given size.
private func makeJPEG(width: Int, height: Int) throws -> Data {
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    return try #require(ArtworkThumbnail.jpegData(from: image))
}

/// The pixel size of encoded image data.
private func pixelSize(of data: Data) throws -> (width: Int, height: Int) {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
    let height = try #require(properties[kCGImagePropertyPixelHeight] as? Int)
    return (width, height)
}

@Suite("ArtworkThumbnail")
struct ArtworkThumbnailTests {
    @Test("A large image is scaled so its longer side is the limit, keeping its proportions")
    func scalesDown() throws {
        let thumbnail = try #require(ArtworkThumbnail.make(from: try makeJPEG(width: 1000, height: 600), maxPixel: 400))
        let size = try pixelSize(of: thumbnail)
        #expect(size.width == 400)
        #expect(size.height == 240)
    }

    @Test("A small image is not scaled up")
    func notScaledUp() throws {
        let thumbnail = try #require(ArtworkThumbnail.make(from: try makeJPEG(width: 100, height: 100), maxPixel: 400))
        let size = try pixelSize(of: thumbnail)
        #expect(size.width <= 100)
        #expect(size.height <= 100)
    }

    @Test("The result is a JPEG, and much smaller than a large original")
    func isJPEG() throws {
        let original = try makeJPEG(width: 2000, height: 2000)
        let thumbnail = try #require(ArtworkThumbnail.make(from: original, maxPixel: 300))
        #expect(Array(thumbnail.prefix(3)) == [0xFF, 0xD8, 0xFF])
        #expect(thumbnail.count < original.count)
    }

    @Test("Data that is not an image gives nothing, not a crash")
    func notAnImage() {
        #expect(ArtworkThumbnail.make(from: Data("not an image".utf8), maxPixel: 400) == nil)
        #expect(ArtworkThumbnail.make(from: Data(), maxPixel: 400) == nil)
    }

    @Test("A limit of zero or less gives nothing")
    func badLimit() throws {
        let data = try makeJPEG(width: 100, height: 100)
        #expect(ArtworkThumbnail.make(from: data, maxPixel: 0) == nil)
        #expect(ArtworkThumbnail.make(from: data, maxPixel: -5) == nil)
    }
}
