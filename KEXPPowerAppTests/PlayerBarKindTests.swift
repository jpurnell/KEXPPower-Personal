import Foundation
import StationKit
import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("PlayerBarKind")
struct PlayerBarKindTests {
    private func show() -> ArchiveShow {
        ArchiveShow(id: "1", programName: "The Morning Show", hostNames: [], tagline: nil, imageURL: nil,
                    startTime: Date(timeIntervalSince1970: 1_762_000_000), tags: [])
    }

    @Test("An archived show playing gets the archive player, in every section")
    func archive() {
        for section in AppSection.allCases {
            #expect(PlayerBarKind.kind(archiveShow: show(), liveHasPlayed: true, in: section) == .archive(show()))
        }
    }

    @Test("Live that has been started gets the slim live bar in every section but Live, which has its own controls")
    func live() {
        #expect(PlayerBarKind.kind(archiveShow: nil, liveHasPlayed: true, in: .archive) == .live)
        #expect(PlayerBarKind.kind(archiveShow: nil, liveHasPlayed: true, in: .review) == .live)
        #expect(PlayerBarKind.kind(archiveShow: nil, liveHasPlayed: true, in: .live) == .none)
    }

    @Test("When live can be rewound, the Live section gets the bar too, since the controls belong at the bottom there as everywhere")
    func liveRewindableInLive() {
        for section in AppSection.allCases {
            #expect(PlayerBarKind.kind(archiveShow: nil, liveHasPlayed: true, isTimeShifted: true, in: section) == .live)
        }
    }

    @Test("A rewindable live that has not been started has no bar, and an archived show still wins")
    func rewindableEdges() {
        #expect(PlayerBarKind.kind(archiveShow: nil, liveHasPlayed: false, isTimeShifted: true, in: .live) == .none)
        #expect(PlayerBarKind.kind(archiveShow: show(), liveHasPlayed: true, isTimeShifted: true, in: .live) == .archive(show()))
    }

    @Test("Before anything has played there is no bar")
    func none() {
        for section in AppSection.allCases {
            #expect(PlayerBarKind.kind(archiveShow: nil, liveHasPlayed: false, in: section) == .none)
        }
    }
}
