import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("LiveRelay")
struct LiveRelayTests {
    private let clock = Date(timeIntervalSince1970: 1_800_000_000)

    private func relay(window: TimeInterval = 600) -> LiveRelay {
        let start = clock
        return LiveRelay(windowDuration: window, segmentDuration: 1, now: { start })
    }

    /// Enough frames for several one-second segments.
    private func stream(_ frames: Int = 200) -> Data { Data(ADTSFixture.frames(frames)) }

    @Test("Nothing is served until the first segment is complete")
    func emptyAtFirst() async {
        let relay = relay()
        let response = await relay.response(forPath: "/live.m3u8")
        #expect(response.status == 404)
    }

    @Test("Once segments are cut the playlist is served as an HLS playlist, and each segment it lists as audio")
    func playlistAndSegments() async {
        let relay = relay()
        await relay.ingest(stream())
        let playlist = await relay.response(forPath: "/live.m3u8")
        #expect(playlist.status == 200)
        #expect(playlist.contentType == "application/vnd.apple.mpegurl")
        let text = String(decoding: playlist.body, as: UTF8.self)
        #expect(text.hasPrefix("#EXTM3U"))
        #expect(text.contains("segment0.aac"))

        let segment = await relay.response(forPath: "/segment0.aac")
        #expect(segment.status == 200)
        #expect(segment.contentType == "audio/aac")
        #expect(segment.body.count > 100)
    }

    @Test("A segment that was never made, or has been dropped, or a path that is not a segment, is not served")
    func unknownPaths() async {
        let relay = relay()
        await relay.ingest(stream())
        #expect(await relay.response(forPath: "/segment99.aac").status == 404)
        #expect(await relay.response(forPath: "/../etc/passwd").status == 404)
        #expect(await relay.response(forPath: "/").status == 404)
    }

    @Test("The window is held: a long stream does not grow the buffer past it")
    func windowHeld() async {
        let relay = relay(window: 5)
        await relay.ingest(stream(1_000))
        let held = await relay.bufferedDuration
        #expect(held >= 5)
        #expect(held < 7)
        #expect(await relay.response(forPath: "/segment0.aac").status == 404)
    }

    @Test("A broken stream is marked, so the player jumps the gap instead of waiting through it")
    func breakIsMarked() async {
        let relay = relay()
        await relay.ingest(stream(120))
        await relay.streamBroke()
        await relay.ingest(stream(120))
        let text = String(decoding: await relay.response(forPath: "/live.m3u8").body, as: UTF8.self)
        #expect(text.contains("#EXT-X-DISCONTINUITY\n"))
    }

    @Test("A break with nothing before it marks nothing: there is no gap to jump")
    func breakAtStart() async {
        let relay = relay()
        await relay.streamBroke()
        await relay.ingest(stream())
        let text = String(decoding: await relay.response(forPath: "/live.m3u8").body, as: UTF8.self)
        #expect(!text.contains("#EXT-X-DISCONTINUITY\n"))
    }

    @Test("Starting over clears what was kept, so the old station's audio is not played back")
    func reset() async {
        let relay = relay()
        await relay.ingest(stream())
        await relay.reset()
        #expect(await relay.bufferedDuration < 0.001)
        #expect(await relay.response(forPath: "/live.m3u8").status == 404)
    }
}
