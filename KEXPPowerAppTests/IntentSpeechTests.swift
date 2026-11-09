import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("IntentSpeech")
struct IntentSpeechTests {
    // MARK: What's playing

    @Test("A song on the air is named with its artist")
    func liveSong() {
        let said = IntentSpeech.whatsPlaying(
            song: IntentSpeech.Song(title: "Heart of Darkness", artist: "Fat Dog"),
            show: "The Midday Show", hosts: ["Cheryl Waters"], isPlaying: true, fromArchive: false)
        #expect(said == "Heart of Darkness by Fat Dog, on KEXP.")
    }

    @Test("Between songs it names the show and its host, as the car's Live row does")
    func airbreak() {
        let said = IntentSpeech.whatsPlaying(
            song: nil, show: "The Midday Show", hosts: ["Cheryl Waters"], isPlaying: true, fromArchive: false)
        #expect(said == "The Midday Show with Cheryl Waters, on KEXP.")
    }

    @Test("Several hosts are joined as a list, and none leaves just the show")
    func hostsListed() {
        let two = IntentSpeech.whatsPlaying(
            song: nil, show: "Variety Mix", hosts: ["Morgan", "Troy"], isPlaying: true, fromArchive: false)
        #expect(two == "Variety Mix with Morgan and Troy, on KEXP.")
        let none = IntentSpeech.whatsPlaying(
            song: nil, show: "Variety Mix", hosts: [], isPlaying: true, fromArchive: false)
        #expect(none == "Variety Mix, on KEXP.")
    }

    @Test("An archived show is named with the show it comes from")
    func archive() {
        let said = IntentSpeech.whatsPlaying(
            song: IntentSpeech.Song(title: "Location", artist: "Sampa the Great"),
            show: "Variety Mix", hosts: ["Morgan"], isPlaying: true, fromArchive: true)
        #expect(said == "Location by Sampa the Great, from Variety Mix in the archive.")
    }

    @Test("An archived show before its first song names the show")
    func archiveBeforeFirstSong() {
        let said = IntentSpeech.whatsPlaying(
            song: nil, show: "Variety Mix", hosts: ["Morgan"], isPlaying: true, fromArchive: true)
        #expect(said == "Variety Mix with Morgan, from the archive.")
    }

    @Test("A pause is said, since the song named is not being heard")
    func paused() {
        let said = IntentSpeech.whatsPlaying(
            song: IntentSpeech.Song(title: "Heart of Darkness", artist: "Fat Dog"),
            show: "The Midday Show", hosts: [], isPlaying: false, fromArchive: false)
        #expect(said.hasSuffix("Playback is paused."))
    }

    @Test("With nothing known, it says nothing is playing")
    func nothing() {
        let said = IntentSpeech.whatsPlaying(song: nil, show: nil, hosts: [], isPlaying: false, fromArchive: false)
        #expect(said == "Nothing is playing.")
    }

    @Test("Blank names are not spoken")
    func blanks() {
        let said = IntentSpeech.whatsPlaying(
            song: nil, show: "  ", hosts: ["  "], isPlaying: true, fromArchive: false)
        #expect(said == "Nothing is playing.")
    }

    // MARK: Saving

    @Test("Each way a save can end has a sentence that says what happened")
    func saved() {
        #expect(IntentSpeech.saved(.saved(playlists: ["KEXP"], failedPlaylists: []), title: "Location") == "Added Location to KEXP.")
        #expect(IntentSpeech.saved(.saved(playlists: [], failedPlaylists: []), title: "Location") == "Location is already in your playlists.")
        #expect(IntentSpeech.saved(.saved(playlists: ["KEXP"], failedPlaylists: ["Road"]), title: "Location") == "Added Location to KEXP, but not to Road.")
        #expect(IntentSpeech.saved(.saved(playlists: [], failedPlaylists: ["Road"]), title: "Location") == "Could not add Location to Road.")
        #expect(IntentSpeech.saved(.heldForReview, title: "Location") == "Location is held for review on your phone.")
        #expect(IntentSpeech.saved(.notFound, title: "Location") == "Apple Music has nothing for Location.")
        #expect(IntentSpeech.saved(.unavailable, title: "Location") == "Apple Music could not be reached.")
        #expect(IntentSpeech.saved(.needsPermission, title: "Location") == "Allow Spinner to use Apple Music in Settings, then try again.")
        #expect(IntentSpeech.saved(.saving, title: "Location") == "Still adding Location.")
        #expect(IntentSpeech.saved(.idle, title: "Location") == "Nothing was added.")
    }

    // MARK: Rewinding

    @Test("A rewind says why it cannot happen, and says nothing when it can")
    func rewindRefusal() {
        #expect(IntentSpeech.rewindRefusal(window: .tenMinutes, isLiveShifted: true, isArchive: false) == nil)
        #expect(IntentSpeech.rewindRefusal(window: .off, isLiveShifted: false, isArchive: false)?.contains("off") == true)
        #expect(IntentSpeech.rewindRefusal(window: .tenMinutes, isLiveShifted: false, isArchive: false)?.contains("not ready") == true)
        #expect(IntentSpeech.rewindRefusal(window: .tenMinutes, isLiveShifted: false, isArchive: true)?.contains("archived show") == true)
    }
}
