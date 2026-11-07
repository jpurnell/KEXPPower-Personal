import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

/// Builds ADTS frames without any audio in them: a valid header, then filler.
enum ADTSFixture {
    /// A frame of `length` bytes (at least 7) at the sampling-frequency index given (4 is 44.1 kHz, 3 is 48 kHz).
    static func frame(length: Int, samplingIndex: Int = 4, filler: UInt8 = 0x55) -> [UInt8] {
        var bytes: [UInt8] = [
            0xFF,
            0xF1,  // sync, MPEG-4, layer 0, no CRC
            UInt8(0x40 | (samplingIndex << 2)),  // AAC-LC, the rate, channel configuration high bit 0
            UInt8(0x80 | ((length >> 11) & 0x03)),  // channel configuration 2, then the top of the length
            UInt8((length >> 3) & 0xFF),
            UInt8(((length & 0x07) << 5) | 0x1F),
            0xFC,
        ]
        bytes += [UInt8](repeating: filler, count: length - 7)
        return bytes
    }

    /// `count` frames of 100 bytes whose filler counts up, so a lost or repeated frame shows in the bytes.
    static func frames(_ count: Int, length: Int = 100, samplingIndex: Int = 4) -> [UInt8] {
        (0..<count).flatMap { frame(length: length, samplingIndex: samplingIndex, filler: UInt8($0 % 200)) }
    }

    /// One frame's duration in seconds.
    static func frameDuration(rate: Double = 44_100) -> Double {
        guard rate > 0 else { return 0 }
        return 1_024 / rate
    }
}

@Suite("ADTSSegmenter")
struct ADTSSegmenterTests {
    private func close(_ a: Double, _ b: Double, tolerance: Double = 1e-9) -> Bool { abs(a - b) <= tolerance }

    @Test("A segment ends at the first frame boundary at or after the target duration")
    func cutsAtTarget() {
        var segmenter = ADTSSegmenter(targetDuration: 1)
        let segments = segmenter.append(Data(ADTSFixture.frames(100)))
        // 43 frames last 0.9985 s and 44 last 1.0216 s, so a segment is 44 frames. Of the 100, the last has no frame
        // after it to prove it is one, so 99 are placed: two segments and 11 waiting.
        #expect(segments.map(\.frameCount) == [44, 44])
        #expect(close(segments[0].duration, 44 * ADTSFixture.frameDuration()))
    }

    @Test("Flushing hands over what is waiting, including the last frame")
    func flush() {
        var segmenter = ADTSSegmenter(targetDuration: 1)
        _ = segmenter.append(Data(ADTSFixture.frames(100)))
        let rest = segmenter.flush()
        #expect(rest?.frameCount == 12)
    }

    @Test("Nothing is lost or repeated: the segments and the flush are the input, byte for byte")
    func bytesPreserved() {
        let input = ADTSFixture.frames(100)
        var segmenter = ADTSSegmenter(targetDuration: 1)
        var output = Data()
        for segment in segmenter.append(Data(input)) { output.append(segment.data) }
        if let rest = segmenter.flush() { output.append(rest.data) }
        #expect(Array(output) == input)
    }

    @Test("The way the bytes arrive does not change the segments: one at a time, or all at once")
    func chunkingDoesNotMatter() {
        let input = ADTSFixture.frames(100)
        var whole = ADTSSegmenter(targetDuration: 1)
        var wholeSegments = whole.append(Data(input))
        if let rest = whole.flush() { wholeSegments.append(rest) }

        var drip = ADTSSegmenter(targetDuration: 1)
        var dripSegments: [ADTSSegmenter.Segment] = []
        for byte in input { dripSegments += drip.append(Data([byte])) }
        if let rest = drip.flush() { dripSegments.append(rest) }

        #expect(dripSegments == wholeSegments)
    }

    @Test("Joining mid-frame: the bytes before the first frame are dropped, and the first segment begins on a frame")
    func startsMidFrame() {
        let garbage = [UInt8](repeating: 0x42, count: 37)
        let frames = ADTSFixture.frames(10)
        var segmenter = ADTSSegmenter(targetDuration: 1)
        var output = Data(segmenter.append(Data(garbage + frames)).flatMap { $0.data })
        if let rest = segmenter.flush() { output.append(rest.data) }
        #expect(Array(output) == frames)
    }

    @Test("A header that claims a frame shorter than its own header is skipped")
    func impossibleLength() {
        // 0xFF 0xF1 and a length of 5, which cannot be a frame.
        let bogus: [UInt8] = [0xFF, 0xF1, 0x50, 0x80, 0x00, 0xA0, 0xFC]
        let frames = ADTSFixture.frames(10)
        var segmenter = ADTSSegmenter(targetDuration: 1)
        var output = Data(segmenter.append(Data(bogus + frames)).flatMap { $0.data })
        if let rest = segmenter.flush() { output.append(rest.data) }
        #expect(Array(output) == frames)
    }

    @Test("A false header, whose claimed frame is not followed by another header, is dropped, not believed")
    func falseSync() {
        // A plausible header claiming 100 bytes, then 100 bytes of filler that do not end at a header.
        let fake = ADTSFixture.frame(length: 100, filler: 0x11)
        let junk = [UInt8](repeating: 0x22, count: 13)
        let frames = ADTSFixture.frames(10)
        var segmenter = ADTSSegmenter(targetDuration: 1)
        var output = Data(segmenter.append(Data(fake + junk + frames)).flatMap { $0.data })
        if let rest = segmenter.flush() { output.append(rest.data) }
        #expect(Array(output) == frames)
    }

    @Test("A frame cut off when the stream ends is not handed over")
    func trailingPartialFrame() {
        let frames = ADTSFixture.frames(5)
        var segmenter = ADTSSegmenter(targetDuration: 10)
        _ = segmenter.append(Data(frames + ADTSFixture.frame(length: 100).prefix(60)))
        #expect(segmenter.flush()?.frameCount == 5)
    }

    @Test("A frame's length is read from the header: frames of different sizes are kept whole")
    func variableLengths() {
        let a = ADTSFixture.frame(length: 150, filler: 1)
        let b = ADTSFixture.frame(length: 2_100, filler: 2)  // above 2,047, so the top length bits are used
        let c = ADTSFixture.frame(length: 90, filler: 3)
        var segmenter = ADTSSegmenter(targetDuration: 10)
        _ = segmenter.append(Data(a + b + c + a))
        let rest = segmenter.flush()
        #expect(rest?.frameCount == 4)
        #expect(rest?.data.count == a.count * 2 + b.count + c.count)
    }

    @Test("Duration follows the sampling rate in the header: 48 kHz frames are shorter than 44.1 kHz ones")
    func samplingRate() {
        var segmenter = ADTSSegmenter(targetDuration: 10)
        _ = segmenter.append(Data(ADTSFixture.frames(10, samplingIndex: 3)))
        let rest = segmenter.flush()
        #expect(rest != nil)
        #expect(close(rest?.duration ?? 0, 10 * ADTSFixture.frameDuration(rate: 48_000)))
    }

    @Test("Nothing in, nothing out")
    func empty() {
        var segmenter = ADTSSegmenter(targetDuration: 1)
        #expect(segmenter.append(Data()).isEmpty)
        #expect(segmenter.flush() == nil)
    }

    @Test("A target that is not a usable number falls back to two seconds rather than cutting a segment per frame")
    func unusableTarget() {
        for target in [0.0, -1, .nan, .infinity] {
            var segmenter = ADTSSegmenter(targetDuration: target)
            let segments = segmenter.append(Data(ADTSFixture.frames(200)))
            // Two seconds is 87 frames at 44.1 kHz.
            #expect(segments.first?.frameCount == 87)
        }
    }
}
