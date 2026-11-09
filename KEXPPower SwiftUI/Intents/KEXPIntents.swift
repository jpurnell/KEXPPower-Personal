//
//  KEXPIntents.swift
//  KEXPPowerExampleSwiftUI
//

import AppIntents
import StationKit

/// Says the song on the air, or the show between songs. Does not open the app.
struct WhatsPlayingIntent: AppIntent {
    static let title: LocalizedStringResource = "What's Playing"
    static let description = IntentDescription("Says the song on KEXP now, or the show and its host between songs.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let said = await AppModelRegistry.whatsPlaying()
        return .result(value: said, dialog: IntentDialog(stringLiteral: said))
    }
}

/// Plays the live stream, returning to it first from an archived show.
struct PlayKEXPIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play KEXP Live"
    static let description = IntentDescription("Plays the live KEXP stream.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await AppModelRegistry.playLive()))
    }
}

/// Pauses whatever is playing.
struct PauseKEXPIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Pause KEXP"
    static let description = IntentDescription("Pauses KEXP.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: AppModelRegistry.pause()))
    }
}

/// Catches up to live from a rewind or an archived show.
struct BackToLiveIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Back to Live"
    static let description = IntentDescription("Catches up to the live KEXP stream.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await AppModelRegistry.backToLive()))
    }
}

/// Goes back by the rewind step (five minutes, or the whole window if it is shorter).
struct RewindLiveIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Rewind KEXP"
    static let description = IntentDescription("Goes back a few minutes in the live stream.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await AppModelRegistry.rewind()))
    }
}

/// One archived airing of a show, as Siri and Shortcuts see it. A program that airs most days is several of these, told
/// apart by their day and time.
struct ShowEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Show")
    static let defaultQuery = ShowEntityQuery()

    let id: String
    let programName: String
    /// The hosts and the day and time it began, such as "Morgan · Sat 3:00 PM".
    let subtitle: String

    init(_ show: StationKit.ArchiveShow) {
        id = show.id
        programName = show.programName
        let when = ArchiveTiming.dayAndClock(show.startTime, zone: AppModelRegistry.shownZone)
        let hosts = show.hostNames.isEmpty ? "" : show.hostNames.formatted(.list(type: .and)) + " · "
        subtitle = hosts + when
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(programName)", subtitle: "\(subtitle)")
    }
}

/// Finds shows by id, by what the listener says, and as suggestions. Show titles are not known ahead of time, so it
/// looks through the archive's last two weeks.
struct ShowEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [ShowEntity] {
        let wanted = Set(identifiers)
        return await AppModelRegistry.archivedShows().filter { wanted.contains($0.id) }.map(ShowEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [ShowEntity] {
        await AppModelRegistry.showsMatching(string).map(ShowEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [ShowEntity] {
        await AppModelRegistry.suggestedShows().map(ShowEntity.init)
    }
}

/// Plays an archived show from its start. Siri asks which show when the name fits several airings.
struct PlayArchivedShowIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play an Archived Show"
    static let description = IntentDescription("Plays a show from the KEXP archive from its start.")

    @Parameter(title: "Show", requestValueDialog: IntentDialog("Which show?"))
    var show: ShowEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await AppModelRegistry.playShow(id: show.id)))
    }
}

#if !os(macOS)
/// Adds the song heard to the playlist, without unlocking the phone: the car's button does the same.
struct AddSongToPlaylistIntent: AppIntent {
    static let title: LocalizedStringResource = "Add This Song"
    static let description = IntentDescription("Adds the song playing on KEXP to your KEXP playlist in Apple Music.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await AppModelRegistry.addSong()))
    }
}
#endif

/// The phrases Siri understands with no setup. Each must contain the app's name.
struct KEXPShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatsPlayingIntent(),
            phrases: ["What's playing on \(.applicationName)", "What song is this on \(.applicationName)"],
            shortTitle: "What's Playing", systemImageName: "music.note")
        AppShortcut(
            intent: PlayKEXPIntent(),
            phrases: ["Play \(.applicationName)", "Play KEXP live on \(.applicationName)"],
            shortTitle: "Play Live", systemImageName: "play.fill")
        AppShortcut(
            intent: PauseKEXPIntent(),
            phrases: ["Pause \(.applicationName)"],
            shortTitle: "Pause", systemImageName: "pause.fill")
        #if !os(macOS)
        AppShortcut(
            intent: AddSongToPlaylistIntent(),
            phrases: ["Add this song on \(.applicationName)", "Save this song on \(.applicationName)"],
            shortTitle: "Add This Song", systemImageName: "plus.circle")
        #endif
        AppShortcut(
            intent: PlayArchivedShowIntent(),
            phrases: ["Play a show on \(.applicationName)", "Play an archived show on \(.applicationName)"],
            shortTitle: "Play a Show", systemImageName: "archivebox")
        AppShortcut(
            intent: BackToLiveIntent(),
            phrases: ["Back to live on \(.applicationName)"],
            shortTitle: "Back to Live", systemImageName: "bolt.fill")
        AppShortcut(
            intent: RewindLiveIntent(),
            phrases: ["Rewind \(.applicationName)"],
            shortTitle: "Rewind", systemImageName: "gobackward")
    }
}
