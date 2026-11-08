//
//  PlayerBarKind.swift
//  KEXPPowerExampleSwiftUI
//

import StationKit

/// Which player bar a section shows beneath its content.
enum PlayerBarKind: Equatable {
    /// An archived show is playing: the full player.
    case archive(ArchiveShow)
    /// Live has been started: a slim bar with play and pause, and the rewind controls when live can be rewound.
    case live
    /// Nothing to control yet, or the section already has its own controls.
    case none

    /// - Parameters:
    ///   - archiveShow: The archived show being heard, or `nil` on the live stream.
    ///   - liveHasPlayed: Whether the live stream has been started this session; before that there is nothing to pause.
    ///   - isTimeShifted: Whether live plays through the recording, so it has rewind controls that belong in the bar.
    ///   - section: The section the bar goes in. Live has its own play button, so without rewind controls it gets no
    ///     slim bar.
    static func kind(
        archiveShow: ArchiveShow?, liveHasPlayed: Bool, isTimeShifted: Bool = false, in section: AppSection
    ) -> PlayerBarKind {
        if let archiveShow { return .archive(archiveShow) }
        guard liveHasPlayed else { return .none }
        return section != .live || isTimeShifted ? .live : .none
    }
}
