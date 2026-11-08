import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("HTTP messages for the local HLS server")
struct HTTPMessageTests {
    @Test("A GET request names its path")
    func getPath() {
        let request = Data("GET /live.m3u8 HTTP/1.1\r\nHost: 127.0.0.1\r\nUser-Agent: AppleCoreMedia\r\n\r\n".utf8)
        #expect(HTTPMessage.path(ofRequest: request) == "/live.m3u8")
    }

    @Test("A query string is not part of the path")
    func queryDropped() {
        #expect(HTTPMessage.path(ofRequest: Data("GET /segment3.aac?x=1 HTTP/1.1\r\n\r\n".utf8)) == "/segment3.aac")
    }

    @Test("Anything but GET is refused, and so is text that is not a request")
    func notServed() {
        #expect(HTTPMessage.path(ofRequest: Data("POST /live.m3u8 HTTP/1.1\r\n\r\n".utf8)) == nil)
        #expect(HTTPMessage.path(ofRequest: Data("hello".utf8)) == nil)
        #expect(HTTPMessage.path(ofRequest: Data()) == nil)
        #expect(HTTPMessage.path(ofRequest: Data([0xFF, 0xFE, 0x00])) == nil)
    }

    @Test("A request is complete once its headers end")
    func completeness() {
        #expect(!HTTPMessage.isComplete(Data("GET / HTTP/1.1\r\nHost: x\r\n".utf8)))
        #expect(HTTPMessage.isComplete(Data("GET / HTTP/1.1\r\nHost: x\r\n\r\n".utf8)))
    }

    @Test("A response carries its status line, length and type, then the body")
    func responseBytes() {
        let body = Data("hello".utf8)
        let bytes = HTTPMessage.bytes(for: HLSResponse(status: 200, contentType: "text/plain", body: body))
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(text.contains("Content-Length: 5\r\n"))
        #expect(text.contains("Content-Type: text/plain\r\n"))
        #expect(text.contains("Cache-Control: no-cache\r\n"))
        #expect(text.hasSuffix("\r\n\r\nhello"))
    }

    @Test("A missing page and a bad request have their own status lines")
    func statusLines() {
        let missing = String(decoding: HTTPMessage.bytes(for: .notFound), as: UTF8.self)
        #expect(missing.hasPrefix("HTTP/1.1 404 Not Found\r\n"))
        let bad = String(decoding: HTTPMessage.badRequest, as: UTF8.self)
        #expect(bad.hasPrefix("HTTP/1.1 400 Bad Request\r\n"))
    }
}

@Suite("LocalHLSServer")
struct LocalHLSServerTests {
    private func fetch(_ url: URL) async throws -> (Data, Int) {
        let (data, response) = try await URLSession(configuration: .ephemeral).data(from: url)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    @Test("The server answers on the loopback address with what the relay holds")
    func servesRelay() async throws {
        let relay = LiveRelay(windowDuration: 60, segmentDuration: 1)
        await relay.ingest(Data(ADTSFixture.frames(200)))
        let server = LocalHLSServer(relay: relay)
        let url = try await server.start()
        defer { server.stop() }
        #expect(url.host == "127.0.0.1")

        let (playlist, playlistStatus) = try await fetch(url)
        #expect(playlistStatus == 200)
        #expect(String(decoding: playlist, as: UTF8.self).hasPrefix("#EXTM3U"))

        let segmentURL = try #require(URL(string: "segment0.aac", relativeTo: url))
        let (segment, segmentStatus) = try await fetch(segmentURL)
        #expect(segmentStatus == 200)
        #expect(segment.count > 100)

        let missingURL = try #require(URL(string: "segment999.aac", relativeTo: url))
        let (_, missingStatus) = try await fetch(missingURL)
        #expect(missingStatus == 404)
    }

    @Test("After stop, the address no longer answers")
    func stops() async throws {
        let relay = LiveRelay(windowDuration: 60, segmentDuration: 1)
        await relay.ingest(Data(ADTSFixture.frames(200)))
        let server = LocalHLSServer(relay: relay)
        let url = try await server.start()
        server.stop()
        try await Task.sleep(for: .milliseconds(200))
        await #expect(throws: (any Error).self) { _ = try await fetch(url) }
    }
}
