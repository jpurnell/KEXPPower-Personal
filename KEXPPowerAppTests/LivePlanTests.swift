import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

/// How live is played, decided from where the sound goes: the recording only where the phone is the source, the stream itself everywhere else.
@Suite("LivePlan")
struct LivePlanTests {
    @Test("Where the phone renders the sound (speaker, headphones, Bluetooth, CarPlay), it is the source")
    func phoneRoutes() {
        for route in [OutputRoute.speaker, .headphones, .bluetooth, .carPlay] {
            #expect(PlaybackSource(route: route, externalPlayback: false) == .phone)
        }
    }

    @Test("AirPlay is a receiver, and so is anything handed to external playback, whatever the route says")
    func receiverRoutes() {
        #expect(PlaybackSource(route: .airPlay, externalPlayback: false) == .receiver)
        #expect(PlaybackSource(route: .speaker, externalPlayback: true) == .receiver)
        #expect(PlaybackSource(route: .carPlay, externalPlayback: true) == .receiver)
    }

    @Test("A route this app does not know is unknown, never assumed to be the phone")
    func unknownRoute() {
        #expect(PlaybackSource(route: .other, externalPlayback: false) == .unknown)
    }

    @Test("The recording plays only where the phone is the source and a recording is available")
    func recordingOnlyOnThePhone() {
        #expect(LivePlan.choose(source: .phone, recordingAvailable: true) == .recording)
        #expect(LivePlan.choose(source: .phone, recordingAvailable: false) == .direct(.recordingUnavailable))
        #expect(LivePlan.choose(source: .receiver, recordingAvailable: true) == .direct(.receiver))
        #expect(LivePlan.choose(source: .receiver, recordingAvailable: false) == .direct(.receiver))
        #expect(LivePlan.choose(source: .unknown, recordingAvailable: true) == .direct(.unknownRoute))
    }

    @Test("The recording's controls (rewind, skip within the window) belong to the recording plan alone")
    func capabilities() {
        #expect(PlaybackCapabilities(plan: .recording) == PlaybackCapabilities(canRewind: true))
        #expect(PlaybackCapabilities(plan: .direct(.receiver)) == PlaybackCapabilities(canRewind: false))
        #expect(PlaybackCapabilities(plan: .direct(.unknownRoute)).canRewind == false)
    }

    @Test("A reason is a short code for the journal and the report, never a name")
    func reasonCodes() {
        #expect(DirectReason.allCases.map(\.rawValue) == ["receiver", "unknownRoute", "recordingUnavailable", "evidenceFallBack"])
    }
}
