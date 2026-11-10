import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

/// The app's diagnostic log, now kept in DiagnosticsKit's `EventJournal` with each line written before `record` returns.
@Suite("DiagnosticLog")
struct DiagnosticLogTests {
    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("diag-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeLog(directory: URL? = nil, maxFileBytes: Int = 256 * 1_024) -> DiagnosticLog {
        DiagnosticLog(directory: directory ?? makeDirectory(), maxFileBytes: maxFileBytes)
    }

    @Test("A line is on disk the moment record returns, so it survives a crash right after")
    func writtenImmediately() {
        let directory = makeDirectory()
        let log = makeLog(directory: directory)
        log.record("CarPlay", "connected")
        // A different log object over the same folder stands in for the next launch: nothing was flushed or closed.
        let afterCrash = makeLog(directory: directory)
        #expect(afterCrash.contents().contains("[CarPlay] connected"))
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

    @Test("A later launch adds to what an earlier one wrote")
    func laterLaunchAppends() {
        let directory = makeDirectory()
        makeLog(directory: directory).record("T", "launch one")
        makeLog(directory: directory).record("T", "launch two")
        let lines = makeLog(directory: directory).contents().split(whereSeparator: \.isNewline)
        #expect(lines.count == 2)
        #expect(lines[0].hasSuffix("[T] launch one"))
        #expect(lines[1].hasSuffix("[T] launch two"))
    }

    @Test("Past its file size the journal starts a new file, and every line is still read, in order")
    func rotates() throws {
        let directory = makeDirectory()
        let log = makeLog(directory: directory, maxFileBytes: 600)
        for index in 0..<40 { log.record("T", "line number \(index)") }
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".jsonl") }
        #expect(files.count > 1)
        let lines = log.contents().split(whereSeparator: \.isNewline)
        #expect(lines.count == 40)
        #expect(lines.first?.hasSuffix("line number 0") == true)
        #expect(lines.last?.hasSuffix("line number 39") == true)
    }

    @Test("A folder that cannot be a journal never crashes the app: recording does nothing and the log reads empty")
    func unusableFolder() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("not-a-folder-\(UUID().uuidString)")
        try Data("x".utf8).write(to: file)
        let log = DiagnosticLog(directory: file, maxFileBytes: 1_000)
        log.record("T", "dropped")
        #expect(log.contents() == "")
    }

    @Test("The app's log lives in a folder of its own, not the old Diagnostics folder with its looser permissions")
    func appFolder() {
        #expect(DiagnosticLog.app.directory.lastPathComponent == "journal")
        #expect(DiagnosticLog.app.directory.deletingLastPathComponent().lastPathComponent == "Diagnostics")
    }
}
