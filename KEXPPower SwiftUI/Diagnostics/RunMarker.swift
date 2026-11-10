//
//  RunMarker.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// How the previous run of the app ended, as far as the app can tell.
enum PreviousRun: String, Sendable, Equatable {
    /// No earlier run was recorded.
    case firstLaunch
    /// The app was last seen in use: it was closed from the foreground, or it crashed.
    case endedWhileActive
    /// The app was last seen in the background: the system may have ended it there, which is normal.
    case endedInBackground
    /// The app was quit (the Mac's Quit, which gives the app a moment to say so).
    case quit

    /// The ending as a phrase for the log.
    var sentence: String {
        switch self {
        case .firstLaunch: "first launch"
        case .endedWhileActive: "ended while the app was in use"
        case .endedInBackground: "ended in the background"
        case .quit: "quit"
        }
    }
}

/// Remembers, in one small file, the last thing the app saw itself do, so the next launch can say how the run before it
/// ended.
///
/// It records what it witnessed (active, in the background, quit) and claims no more: "ended while the app was in use"
/// means a crash or a force-quit from the foreground, and the log cannot tell those apart. The file holds one word and is
/// written without throwing: a folder that cannot be used leaves the app running with no marker, which is the right
/// failure for a diagnostic.
struct RunMarker: Sendable {
    /// Where the one word is kept.
    let fileURL: URL

    /// The app's marker, in Application Support beside the log.
    static let app = RunMarker(
        fileURL: URL.applicationSupportDirectory
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("run-state"))

    private enum State: String {
        case active, background, quit
    }

    /// Reads how the last run ended and marks this one active. Call once, when the app starts.
    func begin() -> PreviousRun {
        let previous = read()
        write(.active)
        return previous
    }

    /// The app came to the foreground.
    func markActive() { write(.active) }

    /// The app went to the background.
    func markBackground() { write(.background) }

    /// The app is quitting.
    func markQuit() { write(.quit) }

    private func read() -> PreviousRun {
        guard let data = try? Data(contentsOf: fileURL),
              let state = State(rawValue: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        else { return .firstLaunch }
        switch state {
        case .active: return .endedWhileActive
        case .background: return .endedInBackground
        case .quit: return .quit
        }
    }

    private func write(_ state: State) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(state.rawValue.utf8).write(to: fileURL, options: .atomic)
        } catch {
            // A marker that cannot be written must never take the app down with it.
            return
        }
    }
}
