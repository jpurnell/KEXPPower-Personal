//
//  DiagnosticLog.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// A small log kept in a file, so what happened can be read later without a computer attached.
///
/// Each line is written to disk before ``record(_:_:)`` returns. That matters for the car: CarPlay can end the process
/// with an exception, and a line queued to be written afterwards would be lost with it. The type holds only the file's
/// location, so it is safe to share and to call from anywhere.
struct DiagnosticLog: Sendable {
    let fileURL: URL
    let maxBytes: Int

    /// - Parameters:
    ///   - fileURL: Where the log lives; its folder is created on first write.
    ///   - maxBytes: The size ``trim()`` cuts the file back to.
    init(fileURL: URL, maxBytes: Int = 64 * 1_024) {
        self.fileURL = fileURL
        self.maxBytes = maxBytes
    }

    /// The app's log, in Application Support so it is kept and is not cleared like a cache.
    static let app: DiagnosticLog = {
        let base = URL.applicationSupportDirectory
        return DiagnosticLog(fileURL: base.appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("spinner-log.txt"))
    }()

    /// Adds one timestamped line, written to disk before this returns.
    func record(_ category: String, _ message: String) {
        let line = "\(Date.now.formatted(.iso8601)) [\(category)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !manager.fileExists(atPath: fileURL.path) {
                try Data().write(to: fileURL)
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } catch {
            // A log that cannot be written must never take the app down with it.
            return
        }
    }

    /// Everything recorded so far, oldest first; empty when nothing has been recorded.
    func contents() -> String {
        guard let data = try? Data(contentsOf: fileURL) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Cuts the file back under ``maxBytes`` by dropping the oldest whole lines.
    func trim() {
        guard let data = try? Data(contentsOf: fileURL), data.count > maxBytes else { return }
        var kept = data.suffix(maxBytes)
        if let newline = kept.firstIndex(of: UInt8(ascii: "\n")) {
            kept = kept[kept.index(after: newline)...]
        }
        try? Data(kept).write(to: fileURL, options: .atomic)
    }

    /// Empties the log.
    func clear() {
        try? Data().write(to: fileURL, options: .atomic)
    }
}
