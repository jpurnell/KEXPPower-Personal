import KEXPPower
import StationKit
import Testing
@testable import KEXPPowerExampleSwiftUI

private let kexp = PlaylistSummary(id: "p-kexp", name: "KEXP")
private let road = PlaylistSummary(id: "p-road", name: "Road Trip")
private let wanted = CatalogSong(id: "cat-1", title: "Bleeding Blue", artist: "Cults")

/// Records what the model asked the saver to do.
private actor Calls {
    private(set) var saved: [(track: String, extra: String?)] = []
    private(set) var confirmed: [(song: String, extra: String?)] = []
    private(set) var created: [String] = []
    func recordCreate(_ name: String) { created.append(name) }
    func recordSave(_ track: Track, _ extra: PlaylistSummary?) { saved.append((track.id, extra?.id)) }
    func recordConfirm(_ song: CatalogSong, _ extra: PlaylistSummary?) { confirmed.append((song.id, extra?.id)) }
}

@MainActor
private func makeModel(
    outcome: SaveOutcome, calls: Calls = Calls(), playlists: [PlaylistSummary] = []
) -> SongSavingModel {
    SongSavingModel(
        save: { track, extra in await calls.recordSave(track, extra); return outcome },
        confirm: { song, extra in await calls.recordConfirm(song, extra); return outcome },
        loadPlaylists: { playlists })
}

private let play = Play(id: 42, song: "Bleeding Blue", artist: "Cults", playType: .trackplay)

@MainActor
@Suite("SongSavingModel")
struct SongSavingModelTests {
    @Test("A play nobody has touched is idle")
    func idle() {
        #expect(makeModel(outcome: .notFound).state(for: play) == .idle)
    }

    @Test("A finished save records which playlists got the song")
    func saved() async {
        let model = makeModel(outcome: .finished(wanted, added: [kexp, road], failed: []))
        await model.save(play)
        #expect(model.state(for: play) == .saved(playlists: ["KEXP", "Road Trip"], failedPlaylists: []))
    }

    @Test("A partial failure is kept visible")
    func partial() async {
        let model = makeModel(outcome: .finished(wanted, added: [kexp], failed: [road]))
        await model.save(play)
        #expect(model.state(for: play) == .saved(playlists: ["KEXP"], failedPlaylists: ["Road Trip"]))
    }

    @Test("A song that was already saved shows as saved")
    func alreadySaved() async {
        let model = makeModel(outcome: .alreadySaved(wanted))
        await model.save(play)
        #expect(model.state(for: play) == .saved(playlists: [], failedPlaylists: []))
    }

    @Test("A text match waits for confirmation, and confirming saves it")
    func confirmation() async {
        let calls = Calls()
        let model = makeModel(outcome: .needsConfirmation(wanted), calls: calls)
        await model.save(play)
        #expect(model.state(for: play) == .confirming(wanted))

        let confirming = SongSavingModel(
            save: { _, _ in .notFound },
            confirm: { song, extra in await calls.recordConfirm(song, extra); return .finished(song, added: [kexp], failed: []) },
            loadPlaylists: { [] })
        await confirming.save(play)   // notFound
        await confirming.confirm(wanted, for: play)
        #expect(confirming.state(for: play) == .saved(playlists: ["KEXP"], failedPlaylists: []))
        #expect(await calls.confirmed.map(\.song) == ["cat-1"])
    }

    @Test("Declining a suggestion returns the play to idle and saves nothing")
    func declined() async {
        let calls = Calls()
        let model = makeModel(outcome: .needsConfirmation(wanted), calls: calls)
        await model.save(play)
        model.dismissConfirmation(for: play)
        #expect(model.state(for: play) == .idle)
        #expect(await calls.confirmed.isEmpty)
    }

    @Test("Not found, unavailable and not authorised are each their own state")
    func otherOutcomes() async {
        let one = makeModel(outcome: .notFound); await one.save(play)
        #expect(one.state(for: play) == .notFound)
        let two = makeModel(outcome: .unavailable); await two.save(play)
        #expect(two.state(for: play) == .unavailable)
        let three = makeModel(outcome: .notAuthorized); await three.save(play)
        #expect(three.state(for: play) == .needsPermission)
    }

    @Test("The chosen extra playlist is passed through")
    func extraPassedThrough() async {
        let calls = Calls()
        let model = makeModel(outcome: .finished(wanted, added: [kexp, road], failed: []), calls: calls)
        await model.save(play, alsoTo: road)
        #expect(await calls.saved.map(\.extra) == ["p-road"])
    }

    @Test("Airbreaks and plays with no id are not saved")
    func notASong() async {
        let calls = Calls()
        let model = makeModel(outcome: .notFound, calls: calls)
        await model.save(Play(id: 1, playType: .airbreak))
        await model.save(Play(song: "No id", playType: .trackplay))
        #expect(await calls.saved.isEmpty)
        #expect(model.state(for: Play(id: 1, playType: .airbreak)) == .idle)
    }

    @Test("A play already being saved is not saved a second time at once")
    func noDoubleSave() async {
        let calls = Calls()
        let model = makeModel(outcome: .finished(wanted, added: [kexp], failed: []), calls: calls)
        async let first: Void = model.save(play)
        async let second: Void = model.save(play)
        _ = await (first, second)
        #expect(await calls.saved.count == 1)
    }

    @Test("The playlists to choose from come from the library; failure gives none")
    func playlistChoices() async {
        let model = makeModel(outcome: .notFound, playlists: [kexp, road])
        #expect(await model.playlists() == [kexp, road])

        struct Down: Error {}
        let failing = SongSavingModel(save: { _, _ in .notFound }, confirm: { _, _ in .notFound }, loadPlaylists: { throw Down() })
        #expect(await failing.playlists().isEmpty)
    }

    @Test("Only plays that are songs can be saved: not airbreaks, not plays with no song or no id")
    func canSave() {
        #expect(SongSavingModel.canSave(play))
        #expect(!SongSavingModel.canSave(Play(id: 1, playType: .airbreak)))
        #expect(!SongSavingModel.canSave(Play(id: 2, artist: "Someone", playType: .trackplay)))
        #expect(!SongSavingModel.canSave(Play(song: "No id", playType: .trackplay)))
        #expect(!SongSavingModel.canSave(nil))
    }

    @Test("Each state has an icon and a spoken label")
    func presentation() {
        let states: [SaveState] = [
            .idle, .saving, .saved(playlists: ["KEXP"], failedPlaylists: []),
            .saved(playlists: ["KEXP"], failedPlaylists: ["Road Trip"]), .confirming(wanted),
            .notFound, .unavailable, .needsPermission,
        ]
        #expect(states.allSatisfy { !$0.symbolName.isEmpty && !$0.accessibilityLabel.isEmpty })
        #expect(Set(states.map(\.accessibilityLabel)).count == states.count)
        #expect(SaveState.saved(playlists: ["KEXP"], failedPlaylists: []).accessibilityLabel.contains("KEXP"))
    }
}

@MainActor
@Suite("SongSavingModel: new playlists")
struct SongSavingModelNewPlaylistTests {
    private func model(calls: Calls, failCreate: Bool = false) -> SongSavingModel {
        SongSavingModel(
            save: { track, extra in await calls.recordSave(track, extra); return .finished(wanted, added: [kexp], failed: []) },
            confirm: { _, _ in .notFound },
            loadPlaylists: { [] },
            createPlaylist: { name in
                await calls.recordCreate(name)
                if failCreate { throw CancellationError() }
                return PlaylistSummary(id: "p-new", name: name)
            })
    }

    @Test("A new playlist is created with the trimmed name, and the song goes to it as the extra playlist")
    func createsThenSaves() async {
        let calls = Calls()
        let model = model(calls: calls)
        await model.save(play, toNewPlaylistNamed: "  Road Trip ")
        #expect(await calls.created == ["Road Trip"])
        #expect(await calls.saved.map(\.extra) == ["p-new"])
    }

    @Test("A blank name creates nothing and saves nothing")
    func blankName() async {
        let calls = Calls()
        let model = model(calls: calls)
        await model.save(play, toNewPlaylistNamed: "   ")
        #expect(await calls.created.isEmpty)
        #expect(await calls.saved.isEmpty)
        #expect(model.state(for: play) == .idle)
    }

    @Test("If the playlist cannot be created the song is not saved and the play shows unavailable")
    func createFails() async {
        let calls = Calls()
        let model = model(calls: calls, failCreate: true)
        await model.save(play, toNewPlaylistNamed: "Road Trip")
        #expect(await calls.saved.isEmpty)
        #expect(model.state(for: play) == .unavailable)
    }
}

@MainActor
@Suite("SongSavingModel with archive tracks")
struct SongSavingModelTrackTests {
    /// An archived song, as the adapter maps KEXP's play 42.
    private let archived = Track(id: "kexp-42", title: "Bleeding Blue", credits: [Credit(role: .performer, name: "Cults")])

    @Test("A track can be saved when its id says which KEXP play it came from")
    func canSave() {
        #expect(SongSavingModel.canSave(archived))
        #expect(!SongSavingModel.canSave(Track(id: "apple-1", title: "A Song")))
        #expect(!SongSavingModel.canSave(Track(id: "kexp-x", title: "A Song")))
    }

    @Test("Saving a track hands it to the saver and records where it went")
    func saveTrack() async {
        let calls = Calls()
        let model = makeModel(outcome: .finished(wanted, added: [kexp], failed: []), calls: calls)
        await model.save(archived)
        #expect(model.state(for: archived) == .saved(playlists: ["KEXP"], failedPlaylists: []))
        #expect(await calls.saved.map(\.track) == ["kexp-42"])
    }

    @Test("A song saved from the archive shows as saved on Live, and the other way round: they are one play")
    func sharedWithLive() async {
        let model = makeModel(outcome: .finished(wanted, added: [kexp], failed: []))
        await model.save(archived)
        #expect(model.state(for: play) == .saved(playlists: ["KEXP"], failedPlaylists: []))
        let other = makeModel(outcome: .alreadySaved(wanted))
        await other.save(play)
        #expect(other.state(for: archived) == .saved(playlists: [], failedPlaylists: []))
    }

    @Test("A track that did not come from a KEXP play is not sent to the saver")
    func notSaveable() async {
        let calls = Calls()
        let model = makeModel(outcome: .notFound, calls: calls)
        await model.save(Track(id: "apple-1", title: "A Song"))
        #expect(await calls.saved.isEmpty)
    }

    @Test("A text match for a track is asked about, and confirming it saves it")
    func confirmTrack() async {
        let calls = Calls()
        let model = makeModel(outcome: .needsConfirmation(wanted), calls: calls)
        await model.save(archived)
        #expect(model.state(for: archived) == .confirming(wanted))
        await model.confirm(wanted, for: archived)
        #expect(await calls.confirmed.map(\.song) == ["cat-1"])
    }

    @Test("Saying a suggested match is wrong clears the question")
    func dismissTrack() async {
        let model = makeModel(outcome: .needsConfirmation(wanted))
        await model.save(archived)
        model.dismissConfirmation(for: archived)
        #expect(model.state(for: archived) == .idle)
    }
}
