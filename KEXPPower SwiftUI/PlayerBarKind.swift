//
//  PlayerBarKind.swift
//  KEXPPowerExampleSwiftUI
//

import StationKit

/// Which player bar a section shows beneath its content.
enum PlayerBarKind: Equatable {
    /// An archived show is playing: the full player.
    case archive(ArchiveShow)
    /// Live has been started: a slim bar with play and pause.
    case live
    /// Nothing to control yet, or the section already has its own controls.
    case none

    /// - Parameters:
    ///   - archiveShow: The archived show being heard, or `nil` on the live stream.
    ///   - liveHasPlayed: Whether the live stream has been started this session; before that there is nothing to pause.
    ///   - section: The section the bar goes in. Live has its own play button, so it gets no slim bar.
    static func kind(archiveShow: ArchiveShow?, liveHasPlayed: Bool, in section: AppSection) -> PlayerBarKind {
        if let archiveShow { return .archive(archiveShow) }
        guard liveHasPlayed, section != .live else { return .none }
        return .live
    }
}
