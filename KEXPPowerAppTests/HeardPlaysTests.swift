import Foundation
import KEXPPower
import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("HeardPlays")
struct HeardPlaysTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func iso(_ secondsAgo: TimeInterval) -> String {
        ISO8601DateFormatter().string(from: now.addingTimeInterval(-secondsAgo))
    }

    /// Four plays, newest first, aired 30 s, 4 min, 9 min and 15 min ago.
    private var plays: [Play] {
        [
            Play(id: 4, song: "Four", airdate: iso(30)),
            Play(id: 3, song: "Three", airdate: iso(240)),
            Play(id: 2, song: "Two", airdate: iso(540)),
            Play(id: 1, song: "One", airdate: iso(900)),
        ]
    }

    private func ids(_ plays: [Play]) -> [Int?] { plays.map(\.id) }

    @Test("At or near live nothing changes: the newest play is the one being heard")
    func nearLive() {
        #expect(ids(HeardPlays.plays(plays, behind: 0, now: now)) == [4, 3, 2, 1])
        #expect(ids(HeardPlays.plays(plays, behind: 3, now: now)) == [4, 3, 2, 1])
    }

    @Test("Behind live, plays that aired after the moment being heard are left out")
    func behind() {
        #expect(ids(HeardPlays.plays(plays, behind: 120, now: now)) == [3, 2, 1])
        #expect(ids(HeardPlays.plays(plays, behind: 300, now: now)) == [2, 1])
        #expect(ids(HeardPlays.plays(plays, behind: 600, now: now)) == [1])
    }

    @Test("Further behind than the plays reach, the oldest is the nearest honest answer")
    func beyondTheList() {
        #expect(ids(HeardPlays.plays(plays, behind: 3_600, now: now)) == [1])
    }

    @Test("A play with no usable air time is kept rather than guessed at")
    func unparseable() {
        let mixed = [Play(id: 9, song: "No date", airdate: nil), Play(id: 8, song: "Old", airdate: iso(900))]
        #expect(ids(HeardPlays.plays(mixed, behind: 300, now: now)) == [9, 8])
    }

    @Test("A lag that is not a usable number is treated as live")
    func notANumber() {
        #expect(ids(HeardPlays.plays(plays, behind: .nan, now: now)) == [4, 3, 2, 1])
        #expect(ids(HeardPlays.plays(plays, behind: -5, now: now)) == [4, 3, 2, 1])
    }

    @Test("No plays gives none")
    func empty() {
        #expect(HeardPlays.plays([], behind: 300, now: now).isEmpty)
    }
}
