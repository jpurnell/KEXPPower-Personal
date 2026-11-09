# Design Proposal: Siri and Shortcuts (App Intents)

**Status:** PROPOSED 2026-11-09. The owner asked for it ("I'd like to get Siri and Shortcuts intents built") and approved the list of intents in §3 ("I like each of those"). APPROVED 2026-11-09 with every open question answered (§16). Builds on `PlatformExperience.md` §3e, which sketched it before the widget, archive and live rewind existed.
**Date:** 2026-11-09
**Facts marked (repo) were read in this repository on 2026-11-09. Anything about how Siri or the system behaves that was not checked on a device is marked *unverified*.**

---

## 1. Objective

Let the listener ask for the things the app already does without opening it, by voice or from Shortcuts: what is
playing, play live, pause, add the song to the playlist, go back to live, go back five minutes, and play an archived
show by name. Phrases are registered so they work in Siri with no setup.

## 2. Motivation

**Today (repo):**
- Two intents exist, both for controls: `PlayPauseIntent` (the widget) and `SetPlayingIntent` (Control Center, iOS 18 and
  macOS 26). They are `AudioPlaybackIntent`s that call `AppModelRegistry.togglePlayback()` / `setPlayback(_:)`
  (`Widget/`). They are not offered to Siri or Shortcuts as phrases: there is no `AppShortcutsProvider`.
- `AppModelRegistry` holds the app's `ResultRetriever`, `SongSavingModel` and `ArchiveBrowserModel` as statics, set in
  the app's `init`, so an intent that launches the app in the background reaches the same player as a window does. That
  path is checked for the widget and Control Center (owner, 2026-11-09).
- Everything the new intents need already exists as a method: `playLive()`, `pausePlayer()`, `catchUpToLive()`,
  `rewindLive()`, `returnToLive()` (player and archive model), `SongSavingModel.save(_:holdingGuesses:)`, and
  `ArchiveBrowserModel.load()` / `play(_:)`.

**Why now:** the listener drives, walks and rides a subway with this app. Hands-free is its use case, and CarPlay has
no voice of its own for it.

## 3. Proposed Architecture

Seven intents and one provider, all in the app targets (not the widget extension), each a thin call into an existing
method through a small, tested layer in `AppModelRegistry`.

| Intent | Does | Notes |
|---|---|---|
| `WhatsPlayingIntent` | Says and returns "Song by Artist on KEXP", or the show if between songs | Archive playing: the song heard (`heardTrack`) and its show. Does not open the app |
| `PlayKEXPIntent` | Plays the live stream; from an archived show, goes back to live first | `AudioPlaybackIntent`; explicit, unlike the existing toggle |
| `PauseKEXPIntent` | Pauses whatever plays | `AudioPlaybackIntent` |
| `AddSongToPlaylistIntent` | Adds the song heard to the default playlist | iPhone, iPad, Vision Pro; not offered on the Mac (MusicKit cannot write there). `holdingGuesses: true`, as in the car |
| `BackToLiveIntent` | Catches up to live from a rewind or an archived show | |
| `RewindLiveIntent` | Goes back by the rewind step (five minutes, or the window if shorter) | Needs live time-shifted; otherwise says so |
| `PlayArchivedShowIntent` | Plays a show from its start | Parameter is a `ShowEntity` (below) |
| `KEXPShortcuts: AppShortcutsProvider` | Registers phrases for the above | |

`PlayPauseIntent` and `SetPlayingIntent` stay as they are: they serve the widget and Control Center, which want a toggle
and a set-value, not a phrase.

**The show entity.** `ShowEntity: AppEntity` wraps one archived airing (`ArchiveShow.id`, program name, hosts, start
time). Its query (`ShowEntityQuery: EntityStringQuery`) matches a spoken name against program name and host, newest
first, across the loaded fifteen days (`ArchiveBrowserModel`'s index), loading the archive first if it is idle. A name
with several airings ("Variety Mix" runs most days) offers them as "Variety Mix, Saturday 3:00 PM" and Siri asks which;
`suggestedEntities()` gives the day's shows. *Whether Siri's disambiguation is pleasant with ~15 candidates is
unverified; the match is capped at the newest five unless the spoken text names a day.*

**Dialogs.** Every intent returns a short spoken line, written by pure functions (§4) so they can be tested and so a
failure says what happened ("Nothing is playing", "Rewind is off in Settings", "That show is no longer available").

## 4. API Surface

```swift
// Pure, tested (new file: Intents/IntentSpeech.swift)
enum IntentSpeech {
    /// "Song by Artist on KEXP", the show if no song is known, or "Nothing is playing".
    static func whatsPlaying(song: NowPlayingSummary?, show: String?, isPlaying: Bool, fromArchive: Bool) -> String
    /// What to say after trying to save: "Added X to your KEXP playlist", "Held for review on your phone", ...
    static func saved(_ state: SaveState, title: String) -> String
    /// Why a rewind could not happen, or `nil` when it can.
    static func rewindRefusal(window: RewindWindow, isLiveShifted: Bool, isArchive: Bool) -> String?
}

enum ShowMatching {
    /// Shows whose program or hosts match a spoken phrase, newest first, at most `limit`.
    static func matches(_ phrase: String, in shows: [StationKit.ArchiveShow], limit: Int) -> [StationKit.ArchiveShow]
}

// Registry (existing enum gains thin, @MainActor entry points)
extension AppModelRegistry {
    static func playLive() async
    static func pause()
    static func whatsPlaying() -> String
    static func addSong() async -> String
    static func backToLive() async -> String
    static func rewind() async -> String
    static func playShow(id: String) async -> String
}

// Intents (app targets; guarded #if !WIDGET_EXTENSION where they touch the registry)
struct WhatsPlayingIntent: AppIntent { ... }
struct PlayKEXPIntent: AudioPlaybackIntent { ... }
struct PlayArchivedShowIntent: AudioPlaybackIntent {
    @Parameter(title: "Show") var show: ShowEntity
}
struct ShowEntity: AppEntity { let id: String; ... }
struct ShowEntityQuery: EntityStringQuery { ... }
struct KEXPShortcuts: AppShortcutsProvider { ... }
```

Phrases, each containing `\(.applicationName)` as the system requires: "What's playing on KEXP", "Play KEXP",
"Pause KEXP", "Add this song on KEXP", "Back to live on KEXP", "Rewind KEXP", "Play a show on KEXP". Seven shortcuts,
inside the system's ten-shortcut limit.

## 5. MCP Schema

N/A. App Intents are this product's machine-readable surface, as `PlatformExperience.md` §5 noted; nothing is added to
`KEXPPowerKit`, `StationKit` or the adapter.

## 6. Constraints & Compliance

**Concurrency:** registry entry points are `@MainActor`; the intents `await` them (one isolated call each, as the
gate's concurrency auditor wants). `ShowEntity` is a `Sendable` value.
**Safety:** no force unwraps; an intent that runs before the registry is set (a cold background launch) returns a
spoken "KEXP is not ready, try again" instead of failing silently. *The cold-launch ordering is checked for the widget;
re-check for each new intent on a device.*
**Privacy:** nothing leaves the device that does not already. Spoken results contain a song title and artist that KEXP
published. Add-to-playlist uses the MusicKit permission the app already requests.
**Authentication:** `AddSongToPlaylistIntent` and `PlayArchivedShowIntent` do not need the phone unlocked for Siri's
sake, but writing to a listener's library from a locked phone is a decision: **open question 1**.
**Platform:** `AddSongToPlaylistIntent` is `#if !os(macOS)`. The watch has its own app and is not in scope.
**Localization:** English only, as the app is.

## 7. Source & API Compatibility

**Breaking changes:** none; additions. The two existing intents keep their types, titles and behavior, so widgets and
controls already placed keep working.
**Deployment target:** the intents are iOS 17 and macOS 14 (`AudioPlaybackIntent`, `AppShortcutsProvider`, `AppEntity`);
no `#available` is needed. `SetPlayingIntent` keeps its own iOS 18 gate.
**Incremental adoption:** each intent is independent; §17's steps land separately.

## 8. Backend Abstraction

N/A.

## 9. Resource Budget

Intents are short and run in the app process. The one costly path is `PlayArchivedShowIntent` and its entity query when
the archive has not been loaded: one request for the last fifteen days (`ArchiveBrowserModel.load()`), the call the
Archive screen makes. Siri's time limit for a query is *unverified*; if it is tight, the query returns the shows already
loaded and kicks off the load for the next ask. No new storage, no new background work.

## 10. Dependencies

`AppIntents` (system). No new packages. `StationKit` and the adapter are unchanged.

## 11. Test Strategy

Red first, by layer:
- **`IntentSpeechTests`**: every sentence, including the empty states (no song, airbreak, archive, not playing,
  rewind off, saved, held, failed).
- **`ShowMatchingTests`**: exact name, partial name, host name, case and diacritics, no match, the newest-first order
  and the `limit`, several airings of one program.
- **Registry tests** (`@MainActor`) with the app's real `PlayerController` test doubles (the ones `PlayerControllerTests`
  uses): `playLive` from an archive returns to live first; `pause`; `rewind` refuses when the window is Off; `backToLive`
  from an archive and from a rewind; `addSong` for a live play and for an archived song; `playShow` for an id that is
  and is not in the loaded index.
- **Entity tests:** `ShowEntity` round-trips an `ArchiveShow`; the query's `entities(for:)` returns what was asked,
  `suggestedEntities()` the day's shows.
- **Not testable offline:** Siri's recognition, disambiguation and the phrases' registration. Checked on Brawn: each
  phrase by voice, each intent from the Shortcuts app, and the cold-launch case (app quit, phone locked).

## 12. Architecture Decision Review

**ADR Check:**
- [x] Reviewed `project/decisions/` (ADR-001, 002, 003, 006, 009, 010).
- [x] Supersedes an existing ADR? No.
- [x] Amends an existing ADR? No. ADR-003 (one writer for Now Playing) holds: intents call the player, which publishes.
- [x] New ADR required? **No.** The decision is local and reversible.

## 13. Adversarial Review

**Strongest case for a different approach:** ship `WhatsPlaying`, `Play` and `Pause` only, and leave the archive show
intent for later. The archive entity is the one real piece of design here (a query, disambiguation, a possibly slow
load), and the others are one-liners over existing calls. A reviewer would say shipping seven at once spreads the device
checking thin. We include it because the owner asked for it and it is what makes Siri useful for the archive.

**Where this design is most likely wrong:**
- Voice: "Play Positive Vibrations" may be heard as another program, or a show has many airings and Siri asks too often.
  The cap of five and the day word ("Saturday") are the mitigation; real use will show whether it is enough.
- An intent run while the app is not running depends on the registry being set by the time `perform()` runs. It works
  for the two existing intents; a longer path (archive load) widens the window.
- `AddSongToPlaylistIntent` can add the wrong song if the song changes between the ask and the save. The intent saves
  the play shown at the moment it runs, which is what the button does too.

**What an experienced critic would say:** "Seven intents is a lot of surface to keep working across iOS, macOS and
visionOS." The answer is that each is a few lines over a tested method, and the pure sentence and match types carry the
logic; the cost is the device checking, which is listed.

## 14. Alternatives Considered

**Alternative 1: Siri through Now Playing only** (the system's own "play/pause/skip" voice commands). Advantage:
nothing to build. Disadvantage: no "what's playing", no add-to-playlist, no archive. Already works, and is not enough.

**Alternative 2: one intent with a `command` parameter** ("KEXP, do X"). Advantage: one type. Disadvantage: no spoken
phrase per action; Shortcuts shows one opaque action. Rejected.

**Alternative 3: intents in the widget extension, so they run without launching the app.** Advantage: faster.
Disadvantage: they need the live player, which only the app has; the widget's `WIDGET_EXTENSION` guard exists for this
reason. Rejected.

## 15. Future Directions

- **Parameters on the rewind** ("rewind 10 minutes"), once the window is the limit.
- **Donating intents** after the listener does something by hand, so Siri suggests them. *Unverified*, small.
- **A Shortcuts action to start the archive at a song or a time** ("play the Midday Show from 12:15").
- **Watch and CarPlay entry points** are separate; none is needed for the iPhone's Siri.
- **Siri in the Spinner TV target**, when that target is polished.

## 16. Open Questions

Answered by the owner on 2026-11-09: (1) **Yes** to add-to-playlist while the phone is locked. (2) **"Play a show on KEXP"** and Siri asks which: "we can't know all show titles ahead of time", so no per-program phrases. (3) **"That's good for airbreak"**: the show and host. Nothing is open. Original questions follow, as asked.

1. **Locked phone.** May `AddSongToPlaylistIntent` run from a locked phone (Siri on a locked phone, CarPlay's voice), or
   should it require unlocking? *Recommendation:* allow it, because the car button already does and the listener may be
   driving; it only adds to their own playlist.
2. **Archive-show phrasing.** "Play a show on KEXP" then Siri asks which, versus "Play Positive Vibrations on KEXP" as
   a per-program shortcut. *Recommendation:* the first for this change; per-program phrases would need an entity-based
   phrase and are *unverified*.
3. **What `WhatsPlaying` says in an airbreak.** *Recommendation:* the show and its host ("The Midday Show with Cheryl
   Waters"), since that is what the car's Live row shows.

## 17. Documentation Strategy

**Documentation Type:** API Docs Only (the types are small; the phrases are documented once, in the README).

**Reconciled on approval and on shipping:** this file's status; the master plan's What's Working and Roadmap; the
README's "not built yet" list (Siri and Shortcuts leave it); CHANGELOG at each step.

**Order of work (each step: tests first, gate clean, path-scoped commit)**
1. `IntentSpeech` and `ShowMatching`, with their tests.
2. Registry entry points (`playLive`, `pause`, `whatsPlaying`, `backToLive`, `rewind`), with tests; the five simple
   intents and the provider.
3. `AddSongToPlaylistIntent` (non-Mac), with tests.
4. `ShowEntity`, its query and `PlayArchivedShowIntent`, with tests.
5. Device check: each phrase by voice and from Shortcuts, with the app quit and the phone locked; the Mac's phrases.
