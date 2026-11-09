//
//  KEXPIntents.swift
//  KEXPPowerExampleSwiftUI
//

import AppIntents

/// Says the song on the air, or the show between songs. Does not open the app.
struct WhatsPlayingIntent: AppIntent {
    static let title: LocalizedStringResource = "What's Playing"
    static let description = IntentDescription("Says the song on KEXP now, or the show and its host between songs.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let said = AppModelRegistry.whatsPlaying()
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
            intent: BackToLiveIntent(),
            phrases: ["Back to live on \(.applicationName)"],
            shortTitle: "Back to Live", systemImageName: "bolt.fill")
        AppShortcut(
            intent: RewindLiveIntent(),
            phrases: ["Rewind \(.applicationName)"],
            shortTitle: "Rewind", systemImageName: "gobackward")
    }
}
