import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("LiveBuffer")
struct LiveBufferTests {
    /// 2026-11-04 21:00:00 UTC.
    private let start = Date(timeIntervalSince1970: 1_793_826_000)

    private func segment(_ duration: TimeInterval = 2, bytes: [UInt8] = [1, 2, 3]) -> ADTSSegmenter.Segment {
        ADTSSegmenter.Segment(data: Data(bytes), duration: duration, frameCount: 87)
    }

    /// A buffer of `count` two-second segments, each starting two seconds after the last.
    private func filled(window: TimeInterval, count: Int) -> LiveBuffer {
        var buffer = LiveBuffer(windowDuration: window)
        for index in 0..<count {
            buffer.append(segment(bytes: [UInt8(index % 200)]), startDate: start.addingTimeInterval(Double(index) * 2))
        }
        return buffer
    }

    // MARK: Segments

    @Test("Segments are numbered from zero, each served as the timestamp tag followed by the segment's own bytes")
    func numbering() throws {
        let buffer = filled(window: 600, count: 3)
        #expect(buffer.entries.map(\.sequence) == [0, 1, 2])
        let served = try #require(buffer.data(forSequence: 1))
        #expect(served.prefix(3) == Data("ID3".utf8))
        #expect(served.last == 1)
        #expect(served.count == ID3Timestamp.tag(presentationTime: 0).count + 1)
    }

    @Test("A sequence number that is not in the buffer has no data")
    func unknownSequence() {
        let buffer = filled(window: 600, count: 3)
        #expect(buffer.data(forSequence: 3) == nil)
        #expect(buffer.data(forSequence: -1) == nil)
    }

    @Test("Each segment's tag carries where it is on the buffer's own clock, in 90 kHz ticks: 0, then 2 s, then 4 s")
    func timestamps() throws {
        let buffer = filled(window: 600, count: 3)
        func ticks(_ sequence: Int) throws -> UInt64 {
            let served = try #require(buffer.data(forSequence: sequence))
            let tag = ID3Timestamp.tag(presentationTime: 0)
            // The tag is the same length for every segment; its last eight bytes are the time.
            return served.prefix(tag.count).suffix(8).reduce(0) { ($0 << 8) | UInt64($1) }
        }
        #expect(try ticks(0) == 0)
        #expect(try ticks(1) == 180_000)
        #expect(try ticks(2) == 360_000)
    }

    @Test("The buffer keeps at least its window and drops the oldest segments beyond it")
    func trimming() {
        let buffer = filled(window: 10, count: 8)
        #expect(buffer.entries.map(\.sequence) == [3, 4, 5, 6, 7])
        #expect(buffer.data(forSequence: 0) == nil)
        #expect(buffer.data(forSequence: 7) != nil)
        #expect(abs(buffer.totalDuration - 10) < 1e-9)
    }

    @Test("A window that is not a whole number of segments keeps one segment more, never less than the window")
    func trimmingUneven() {
        let buffer = filled(window: 11, count: 10)
        #expect(buffer.entries.count == 6)
        #expect(buffer.totalDuration >= 11)
    }

    @Test("A window that is not a usable number reads as ten minutes")
    func unusableWindow() {
        for window in [0.0, -5, .nan, .infinity] {
            #expect(abs(filled(window: window, count: 400).totalDuration - 600) < 2)
        }
    }

    @Test("The size held is the sum of what would be served")
    func byteCount() {
        let buffer = filled(window: 600, count: 3)
        #expect(buffer.byteCount == (ID3Timestamp.tag(presentationTime: 0).count + 1) * 3)
    }

    // MARK: Playlist

    private func lines(_ playlist: String) -> [String] {
        playlist.split(whereSeparator: \.isNewline).map(String.init)
    }

    @Test("The playlist is a live one: version, target duration, first sequence, each segment, and no end marker")
    func playlist() {
        let buffer = filled(window: 600, count: 3)
        #expect(lines(buffer.playlist()) == [
            "#EXTM3U", "#EXT-X-VERSION:3", "#EXT-X-TARGETDURATION:2", "#EXT-X-MEDIA-SEQUENCE:0",
            "#EXT-X-PROGRAM-DATE-TIME:2026-11-04T21:00:00.000Z",
            "#EXTINF:2.000,", "segment0.aac", "#EXTINF:2.000,", "segment1.aac", "#EXTINF:2.000,", "segment2.aac",
        ])
        #expect(!buffer.playlist().contains("ENDLIST"))
    }

    @Test("After segments are dropped the playlist begins at the first one left")
    func playlistAfterTrimming() {
        let text = lines(filled(window: 10, count: 8).playlist())
        #expect(text.contains("#EXT-X-MEDIA-SEQUENCE:3"))
        #expect(text.contains("segment3.aac"))
        #expect(!text.contains("segment2.aac"))
    }

    @Test("The target duration is the longest segment rounded up")
    func targetDuration() {
        var buffer = LiveBuffer(windowDuration: 600)
        buffer.append(segment(2.4), startDate: start)
        buffer.append(segment(1.9), startDate: start.addingTimeInterval(2.4))
        #expect(lines(buffer.playlist()).contains("#EXT-X-TARGETDURATION:3"))
    }

    @Test("A break in the stream is marked before the segment that follows it, with that segment's own time of day")
    func discontinuity() {
        var buffer = LiveBuffer(windowDuration: 600)
        buffer.append(segment(), startDate: start)
        buffer.append(segment(), startDate: start.addingTimeInterval(95), isDiscontinuity: true)
        let text = lines(buffer.playlist())
        let index = text.firstIndex(of: "#EXT-X-DISCONTINUITY")
        #expect(index != nil)
        guard let index else { return }
        #expect(text[index + 1] == "#EXT-X-PROGRAM-DATE-TIME:2026-11-04T21:01:35.000Z")
        #expect(text[index + 3] == "segment1.aac")
    }

    @Test("Once a segment that began a new run has been dropped, the playlist counts it")
    func discontinuitySequence() {
        var buffer = LiveBuffer(windowDuration: 4)
        buffer.append(segment(), startDate: start)
        buffer.append(segment(), startDate: start.addingTimeInterval(2), isDiscontinuity: true)
        buffer.append(segment(), startDate: start.addingTimeInterval(4))
        #expect(!lines(buffer.playlist()).contains { $0.hasPrefix("#EXT-X-DISCONTINUITY-SEQUENCE") })
        buffer.append(segment(), startDate: start.addingTimeInterval(6))
        #expect(lines(buffer.playlist()).contains("#EXT-X-DISCONTINUITY-SEQUENCE:1"))
    }

    @Test("An empty buffer has a playlist with no segments")
    func emptyPlaylist() {
        #expect(lines(LiveBuffer(windowDuration: 600).playlist()) == [
            "#EXTM3U", "#EXT-X-VERSION:3", "#EXT-X-TARGETDURATION:2", "#EXT-X-MEDIA-SEQUENCE:0",
        ])
    }

    // MARK: Paths

    @Test("A segment's address round-trips to its number, and anything else in the folder is not a segment")
    func paths() {
        #expect(LiveBuffer.sequence(inPath: "/segment12.aac") == 12)
        #expect(LiveBuffer.sequence(inPath: "segment0.aac") == 0)
        for odd in ["/other.aac", "/segmentx.aac", "/../segment1.aac", "/segment-1.aac", "/segment1.mp3", "/segment99999999999999999999.aac", ""] {
            #expect(LiveBuffer.sequence(inPath: odd) == nil)
        }
    }
}

@Suite("ID3Timestamp")
struct ID3TimestampTests {
    @Test("The tag is an ID3v2.4 header and one PRIV frame owned by Apple's transport-stream-timestamp, then eight bytes of time")
    func structure() {
        let tag = [UInt8](ID3Timestamp.tag(presentationTime: 0x0102_0304_05))
        let owner = Array("com.apple.streaming.transportStreamTimestamp".utf8) + [0]
        #expect(Array(tag.prefix(5)) == [0x49, 0x44, 0x33, 0x04, 0x00])  // "ID3", 2.4.0
        #expect(tag[5] == 0)  // no flags
        #expect(Array(tag[10..<14]) == Array("PRIV".utf8))
        #expect(Array(tag[20..<(20 + owner.count)]) == owner)
        #expect(Array(tag.suffix(8)) == [0, 0, 0, 1, 2, 3, 4, 5])
    }

    @Test("The sizes in the tag add up: the header's size covers everything after it, the frame's size everything after the frame header")
    func sizes() {
        let tag = [UInt8](ID3Timestamp.tag(presentationTime: 0))
        let tagSize = tag[6..<10].reduce(0) { ($0 << 7) | Int($1) }
        #expect(tagSize == tag.count - 10)
        let frameSize = tag[14..<18].reduce(0) { ($0 << 7) | Int($1) }
        #expect(frameSize == tag.count - 20)
        #expect(tag[6..<10].allSatisfy { $0 < 0x80 } && tag[14..<18].allSatisfy { $0 < 0x80 })
    }

    @Test("The time is thirty-three bits: a larger one wraps, as a transport stream's clock does")
    func wraps() {
        let tag = [UInt8](ID3Timestamp.tag(presentationTime: (1 << 33) + 5))
        #expect(Array(tag.suffix(8)) == [0, 0, 0, 0, 0, 0, 0, 5])
    }
}
