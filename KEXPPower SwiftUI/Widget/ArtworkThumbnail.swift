//
//  ArtworkThumbnail.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Shrinks artwork to the few hundred pixels a widget can afford. A widget extension is stopped if it uses too much
/// memory, so the full-size image must never be decoded into the timeline.
enum ArtworkThumbnail {
    /// Encoded JPEG data for the image scaled to `maxPixel` on its longer side, or `nil` if the data is not an image.
    /// An image already smaller than the limit keeps its size.
    /// - Parameters:
    ///   - data: The encoded image as downloaded.
    ///   - maxPixel: The longest side to allow, in pixels.
    ///   - quality: JPEG quality, 0 to 1.
    static func make(from data: Data, maxPixel: Int = 400, quality: Double = 0.8) -> Data? {
        guard maxPixel > 0, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return jpegData(from: image, quality: quality)
    }

    /// Encodes an image as JPEG without going through UIKit or AppKit.
    /// - Parameters:
    ///   - image: The image to encode.
    ///   - quality: JPEG quality, 0 to 1.
    /// - Returns: The JPEG bytes, or `nil` if the image cannot be encoded.
    static func jpegData(from image: CGImage, quality: Double = 0.8) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
