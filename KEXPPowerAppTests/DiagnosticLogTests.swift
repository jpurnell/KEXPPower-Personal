import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("DiagnosticLog")
struct DiagnosticLogTests {
    private func makeLog(maxBytes: Int = 4_096) -> DiagnosticLog {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("diag-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("log.txt")
        return DiagnosticLog(fileURL: url, maxBytes: maxBytes)
    }

    @Test("A line is on disk the moment record returns, so it survives a crash right after")
    func writtenImmediately() {
        let log = makeLog()
        log.record("CarPlay", "connected")
        let text = log.contents()
        #expect(text.contains("[CarPlay] connected"))
    }

    @Test("Lines keep their order and each carries a timestamp")
    func orderAndTimestamp() {
        let log = makeLog()
        log.record("CarPlay", "first")
        log.record("CarPlay", "second")
        let lines = log.contents().split(whereSeparator: \.isNewline)
        #expect(lines.count == 2)
        #expect(lines[0].hasSuffix("[CarPlay] first"))
        #expect(lines[1].hasSuffix("[CarPlay] second"))
        #expect(lines[0].first?.isNumber == true)
    }

    @Test("An empty log reads as empty, not as an error")
    func empty() {
        #expect(makeLog().contents() == "")
    }

    @Test("Past its size limit the oldest lines are dropped and the newest kept")
    func trims() {
        let log = makeLog(maxBytes: 600)
        for i in 0..<40 { log.record("T", "line number \(i)") }
        log.trim()
        let text = log.contents()
        #expect(text.utf8.count <= 600)
        #expect(text.contains("line number 39"))
        #expect(!text.contains("line number 0\n"))
    }

    @Test("Clear empties the log")
    func clears() {
        let log = makeLog()
        log.record("T", "x")
        log.clear()
        #expect(log.contents() == "")
    }

    @Test("A new line is recorded after a clear")
    func recordsAfterClear() {
        let log = makeLog()
        log.record("T", "before")
        log.clear()
        log.record("T", "after")
        #expect(log.contents().contains("[T] after"))
        #expect(!log.contents().contains("before"))
    }
}
