//
//  DiagnosticLog.swift
//  KEXPPowerExampleSwiftUI
//

import DiagnosticsKit
import Foundation

/// A small log kept in files, so what happened can be read later without a computer attached.
///
/// It is a thin layer over DiagnosticsKit's `EventJournal`, opened in the `.written` durability: each line is written
/// to the file before ``record(_:_:)`` returns. That matters for the car: CarPlay can end the process with an exception,
/// and a line queued to be written afterwards would be lost with it. The journal adds rotation by size and age, a
/// retention period and owner-only permissions, which the single file this replaced did not have. The type holds only
/// the folder and the journal, so it is safe to share and to call from anywhere.
struct DiagnosticLog: Sendable {
    /// The folder the journal's files live in.
    let directory: URL
    /// `nil` when the folder cannot be used; recording then does nothing, because a log must never take the app down.
    private let journal: EventJournal?

    /// How long a file is kept after the last line in it.
    static let retention: TimeInterval = 14 * 86_400

    /// - Parameters:
    ///   - directory: Where the journal's files live; the journal creates it, readable only by this app.
    ///   - maxFileBytes: The size at which a file is closed and a new one started.
    init(directory: URL, maxFileBytes: Int = 256 * 1_024) {
        self.directory = directory
        var configuration = EventJournal.Configuration(directory: directory)
        configuration.filePrefix = "spinner"
        configuration.retention = Self.retention
        configuration.maxFileBytes = maxFileBytes
        configuration.durability = .written
        // A journal that cannot open (a file where the folder should be, a folder open to others) leaves the app running
        // without a log, which is the right failure for a log.
        self.journal = try? EventJournal(configuration: configuration, clock: { Date() })
    }

    /// The app's log, in Application Support so it is kept and is not cleared like a cache.
    ///
    /// Its own `journal` folder, not the `Diagnostics` folder the old single-file log made: the journal refuses a folder
    /// that other users can read, and the old one was created with the default permissions.
    static let app: DiagnosticLog = DiagnosticLog(
        directory: URL.applicationSupportDirectory
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("journal", isDirectory: true))

    /// Adds one timestamped line, written to disk before this returns.
    func record(_ category: String, _ message: String) {
        journal?.record(EventRecord(time: .now, kind: category, fields: ["message": .string(message)]))
    }

    /// Everything recorded so far, as entries for a shared diagnostic report: the category and the message as written.
    ///
    /// DiagnosticsKit's own rendering of a journal event is `key=value`, which would show every line as
    /// `message="..."`; the report reads better with the plain text.
    func reportEntries() -> [DiagnosticReport.LogEntry] {
        guard let events = try? EventJournal.read(directory: directory, filePrefix: "spinner") else { return [] }
        return events.map { event in
            let message: String
            if case .string(let text)? = event.fields["message"] { message = text } else { message = "" }
            return DiagnosticReport.LogEntry(timestamp: event.time, category: event.kind, level: "info", message: message)
        }
    }

    /// Everything recorded so far, oldest first, one line per event; empty when nothing has been recorded.
    func contents() -> String {
        guard let events = try? EventJournal.read(directory: directory, filePrefix: "spinner") else { return "" }
        return events.map { event in
            let message: String
            if case .string(let text)? = event.fields["message"] { message = text } else { message = "" }
            return "\(event.time.formatted(.iso8601)) [\(event.kind)] \(message)\n"
        }.joined()
    }
}
