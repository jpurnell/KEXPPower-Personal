import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("ArchiveTransport")
struct ArchiveTransportTests {
    /// A show that begins 778 s into its file and runs two hours, in a file that is longer than that.
    private func twoHourShow() -> ArchiveTransport {
        ArchiveTransport(offset: 778, showLength: 7_200, fileDuration: 9_000)
    }

    /// Seconds are computed values, so they are compared to within a microsecond rather than exactly.
    private func near(_ value: Double, _ expected: Double) -> Bool {
        abs(value - expected) < 1e-6
    }

    // MARK: Range

    @Test("The range runs from where the show begins in the file for the show's length")
    func range() {
        let transport = twoHourShow()
        #expect(near(transport.lowerBound, 778))
        #expect(near(transport.upperBound, 7_978))
        #expect(near(transport.length, 7_200))
    }

    @Test("The range ends where the file does when the file is shorter than the show's slot")
    func rangeClampedToFile() {
        let transport = ArchiveTransport(offset: 778, showLength: 7_200, fileDuration: 5_000)
        #expect(near(transport.upperBound, 5_000))
        #expect(near(transport.length, 4_222))
    }

    @Test("With no next show the range runs to the end of the file")
    func rangeWithoutNextShow() {
        let transport = ArchiveTransport(offset: 778, showLength: nil, fileDuration: 5_000)
        #expect(near(transport.upperBound, 5_000))
    }

    @Test("A negative offset reads as the start of the file, as ArchivePlayback does")
    func negativeOffset() {
        let transport = ArchiveTransport(offset: -1, showLength: 100, fileDuration: 500)
        #expect(near(transport.lowerBound, 0))
        #expect(near(transport.upperBound, 100))
    }

    @Test("Durations that are not finite numbers give an empty range, not a crash")
    func notFinite() {
        #expect(ArchiveTransport(offset: 0, showLength: 100, fileDuration: .nan).isEmpty)
        #expect(ArchiveTransport(offset: 0, showLength: 100, fileDuration: .infinity).isEmpty)
        #expect(ArchiveTransport(offset: .nan, showLength: 100, fileDuration: 500).isEmpty)
        #expect(ArchiveTransport(offset: 0, showLength: .nan, fileDuration: 500).isEmpty)
        #expect(ArchiveTransport(offset: 600, showLength: 100, fileDuration: 500).isEmpty)
    }

    @Test("An empty range has no length and every position in it reads as zero")
    func emptyRange() {
        let transport = ArchiveTransport(offset: 0, showLength: 100, fileDuration: .nan)
        #expect(near(transport.length, 0))
        #expect(near(transport.elapsed(atFileTime: 50), 0))
        #expect(near(transport.fraction(atFileTime: 50), 0))
    }

    // MARK: Position

    @Test("Elapsed show time is the file time minus where the show begins")
    func elapsed() {
        #expect(near(twoHourShow().elapsed(atFileTime: 778 + 3_725), 3_725))
    }

    @Test("Before the show begins reads as the start, and after it ends as the whole show")
    func elapsedClamped() {
        let transport = twoHourShow()
        #expect(near(transport.elapsed(atFileTime: 100), 0))
        #expect(near(transport.elapsed(atFileTime: 8_500), 7_200))
    }

    @Test("A time that is not a finite number reads as the start")
    func elapsedNotFinite() {
        #expect(near(twoHourShow().elapsed(atFileTime: .nan), 0))
    }

    @Test("Remaining is what is left of the show")
    func remaining() {
        #expect(near(twoHourShow().remaining(atFileTime: 778 + 3_725), 3_475))
        #expect(near(twoHourShow().remaining(atFileTime: 100), 7_200))
    }

    @Test("The fraction played runs from zero to one for the scrubber")
    func fraction() {
        let transport = twoHourShow()
        #expect(near(transport.fraction(atFileTime: 778), 0))
        #expect(near(transport.fraction(atFileTime: 778 + 3_600), 0.5))
        #expect(near(transport.fraction(atFileTime: 7_978), 1))
    }

    // MARK: Skipping

    @Test("Skipping back 15 seconds lands 15 seconds earlier in the file")
    func skipBack() {
        #expect(twoHourShow().target(skipping: -15, from: 2_000) == .within(1_985))
    }

    @Test("Skipping back near the start stops at the start of the show, not in the previous show's tail")
    func skipBackClamps() {
        #expect(twoHourShow().target(skipping: -15, from: 785) == .within(778))
        #expect(twoHourShow().target(skipping: -15, from: 100) == .within(778))
    }

    @Test("Skipping forward 30 seconds lands 30 seconds later")
    func skipForward() {
        #expect(twoHourShow().target(skipping: 30, from: 2_000) == .within(2_030))
    }

    @Test("Skipping forward past the end of the show goes on to what follows")
    func skipForwardPastEnd() {
        #expect(twoHourShow().target(skipping: 30, from: 7_960) == .end)
        #expect(twoHourShow().target(skipping: 30, from: 7_948) == .end)
        #expect(twoHourShow().target(skipping: 30, from: 7_947) == .within(7_977))
    }

    @Test("A skip that is not a finite number goes nowhere")
    func skipNotFinite() {
        #expect(twoHourShow().target(skipping: .nan, from: 2_000) == .within(2_000))
        #expect(twoHourShow().target(skipping: 30, from: .nan) == .within(778))
    }

    @Test("An empty range has nowhere to skip to")
    func skipEmpty() {
        let transport = ArchiveTransport(offset: 0, showLength: 100, fileDuration: .nan)
        #expect(transport.target(skipping: 30, from: 0) == .within(0))
    }

    // MARK: Scrubbing

    @Test("Scrubbing to a fraction lands that far through the show")
    func scrub() {
        let transport = twoHourShow()
        #expect(transport.target(fraction: 0) == .within(778))
        #expect(transport.target(fraction: 0.5) == .within(778 + 3_600))
    }

    @Test("Scrubbing to the very end goes on to what follows; a fraction out of range is clamped")
    func scrubEnd() {
        let transport = twoHourShow()
        #expect(transport.target(fraction: 1) == .end)
        #expect(transport.target(fraction: 2) == .end)
        #expect(transport.target(fraction: -1) == .within(778))
        #expect(transport.target(fraction: .nan) == .within(778))
    }

    // MARK: Text

    @Test("Elapsed and remaining read as clock times, remaining with a minus sign")
    func text() {
        let transport = twoHourShow()
        #expect(transport.elapsedText(atFileTime: 778 + 3_725) == "1:02:05")
        #expect(transport.remainingText(atFileTime: 778 + 3_725) == "-57:55")
        #expect(transport.remainingText(atFileTime: 7_978) == "-0:00")
    }
}
