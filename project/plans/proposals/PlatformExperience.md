# Design Proposal: Navigation Shell, Mac Playback and Layout, Apple Music Playlists, Widget and App Intents

**Status:** Proposed — revised 2026-11-03 (separate per-platform targets; generic ListenKit repo; ISRC-based song matching; tvOS/watchOS kept ready) — awaiting approval
**Date:** 2026-11-02
**Delivery:** four phases, each independently shippable and each gated by its own tests. Phase D (archive) is design-only until the library's async `ArchiveManager` exists (iOS 27.2 follow-up).
**Not in scope:** the iOS 27 `NowPlaying` framework (on hold). The `NowPlayingPublishing` seam (ADR-003) keeps it a later, small change.

---

### 1. Objective

Turn the app from one live-playlist screen into a small multi-platform product:

- **A navigation shell** (Live / Archive / Playlists / Settings) that every later feature hangs from.
- **Mac playback and a Mac-native layout.** Today the Mac build shows the playlist but cannot play audio.
- **Apple Music playlists:** add the playing track to a dedicated "KEXP" playlist.
- **A widget and App Intents:** "what's playing", play/pause, and add-to-playlist from Siri, Shortcuts, the widget and Control Center.
- **Archive browsing** (design now, build after the library work).

**Master Plan Reference:** Roadmap Phase 2 (Apple Music, archive, links) and Phase 3 (macOS, visionOS).

### 2. Motivation

**Current situation (verified in this repo):**
- One screen (`ContentView`), no navigation. The archive feature has nowhere to live.
- `PlayerController` is `#if os(iOS) || os(visionOS)` only, so macOS has no playback. It also uses `AVAudioSession`, which does not exist on macOS.
- `ResultRetriever` owns both data polling and the player, so a widget or an intent cannot reuse either.
- Apple Music support is read-only: a search link (`getAppleMusicLink`) and a title button that opens it.
- The README lists "add songs directly to a dedicated KEXP Apple Music playlist" as the app's reason to exist.

**Workaround today:** none; the Mac build is a preview-quality port of the iPhone layout.
**Drawback:** the headline feature (save the music you hear) does not exist, and nothing outside the app can ask "what is playing?".

### 3. Proposed Architecture

#### 3a. Layering (the key move)
Split what the app *knows* from what it *shows*, so the app, widget and intents share one source of truth:

```
KEXPPower (library)      plays/shows over the network
   │
LiveActivityService      ← new: fetch current play + show; no UI, no player. Used by app, widget, intents.
   │
PlaybackController       ← PlayerController generalised: iOS/visionOS/macOS; owns AVPlayer + NowPlayingPublishing
PlaylistService          ← new: MusicKit find/create/add; behind a protocol for tests
   │
SwiftUI shell            ← NavigationSplitView / TabView, per platform
```

#### 3a-2. Targets and the generic package (owner decisions 2026-11-03)

**Separate app targets per platform, one shared generic package in its own repository.**

```
KEXPPowerKit (repo, exists)     KEXP's API only: plays, shows, stream URLs. Knows nothing about playback or UI.
ListenKit    (new repo)         NOT KEXP-specific. Live-stream playback glue, Now Playing publishing, audio session,
   ▲                            artwork loading, link-out builders, song matching, playlist saving. Working name; see Q1.
   │
   ├── KEXPPower (iOS app)           iOS shell; CarPlay scene later
   ├── KEXPPower Vision (visionOS)   own target (owner decision); spatial layout
   ├── KEXPPower Mac (macOS)         sidebar, menus, Settings, window management
   ├── KEXPWidget (extension)        iOS, macOS, visionOS, watchOS; links ListenKit, never the player
   ├── tvOS app    ── "ready", not built in this proposal
   └── watchOS app ── "ready", not built in this proposal
```

**What is generic (moves to ListenKit) and what stays:**

| Piece | Today | Generic? | Change needed to extract |
|-------|-------|----------|--------------------------|
| `NowPlayingSnapshot`, `NowPlayingPublishing`, `LegacyNowPlayingPublisher` | app | Yes | none; they already take plain strings |
| `AudioSessionCoordinator` | app (iOS) | Yes | keep behind `#if`; macOS gets a no-op |
| `ArtworkLoader` | app | Yes, **but** hard-codes `kexp.org` / `archive.org` | allowed domains become an init parameter; return a platform-neutral image (macOS has no `UIImage`) |
| `MusicLinks` (Spotify/Bandcamp searches, comment links) | app | Yes | none |
| `SongResolver`, `PlaylistService` (MBID → ISRC → MusicKit) | proposed | Yes | built in ListenKit from the start |
| `PlaybackController` | app | Mostly | inject the stream URL and metadata source instead of reading `ResultRetriever` |
| `LiveActivityService` (fetch current play) | proposed | **No** | stays in the KEXP app, as an adapter from `KEXPPowerKit` to a ListenKit `NowPlayingSource` protocol |
| `Play`, `Show`, stream bitrates, KEXP branding | library/app | **No** | stay in `KEXPPowerKit` and the app |

**The rule that keeps it generic:** ListenKit never imports `KEXPPower`. It defines small protocols (`NowPlayingSource`, `StreamDescriptor`) and a plain `Track` value type (title, artist, album, artwork URL, optional MusicBrainz recording ID / ISRC). The KEXP app adapts `Play` to `Track`. A second station or service needs only its own adapter.

**Platform readiness (tvOS and watchOS "ready"):**
- ListenKit declares iOS 17, macOS 14, visionOS 1, tvOS 17 and watchOS 10 from day one, and CI builds all of them, so a platform that does not compile is caught immediately instead of at the moment a target is added.
- Verified in the 27.2 SDKs: `MediaPlayer`, `AVFoundation`, `MusicKit`, `AppIntents` and `NowPlaying` exist on iOS, tvOS, watchOS and visionOS; `WidgetKit` exists on watchOS and visionOS but **not tvOS**; `CarPlay` is iOS only. Per-API availability inside those frameworks (for example `MPNowPlayingInfoCenter` on watchOS) is checked when each target is built, not assumed.
- No `UIKit` in ListenKit's public API (macOS lacks it), so images cross the boundary as `CGImage`/`Data` with a thin SwiftUI `Image` helper.

**CarPlay (iOS target, later, not built here):** CarPlay audio apps are driven by `CPNowPlayingTemplate`, which reads the same `MPNowPlayingInfoCenter` state our `NowPlayingPublishing` already feeds, plus list templates for browsing. So most of what CarPlay needs is a by-product of ListenKit's publisher, not a separate UI. It still requires Apple's CarPlay audio entitlement. *On "HomeView": I found nothing by that name in the 27.2 SDKs (only `HomeKit` and `HomeExtensions`), so I am not designing for it. If it is a surface that reads Now Playing state, it should work through the same seam; that is a hope, not something verified.*

**Why separate targets and a separate repo:** per-platform shells, entitlements and menus diverge, and ListenKit's tests run with `swift test` in seconds, without a simulator host (today's hosted tests take about 35 seconds).
**Cost, stated honestly:** a second consumer does not exist yet. The mitigation is the dependency rule above and an adapter seam, so ListenKit stays honest rather than becoming "the KEXP app in a package".

**Phase 0 (before Phase A):**
1. Create the `ListenKit` repository (private to start; guidelines scaffold; Swift 6; the five platforms).
2. Move the already-generic, already-tested pieces with their tests (`NowPlayingSnapshot`, publisher, `AudioSessionCoordinator`, `ArtworkLoader` with injectable domains, `MusicLinks`); make the public surface explicit.
3. The KEXP app consumes ListenKit by tagged URL, as it does KEXPPowerKit.
4. Split the single multiplatform target into iOS, visionOS and macOS app targets.

#### 3b. Navigation shell
- **macOS and iPad (regular width):** `NavigationSplitView` with a sidebar: Live, Archive, Playlists. Detail pane per selection.
- **iPhone (compact):** `TabView` with the same three destinations, Settings in a sheet.
- One `AppSection` enum drives both; selection is the only shared state. Archive is present but shows "coming soon" until Phase D.

#### 3c. Mac playback and layout (in the separate Mac target)
- `PlayerController` becomes `PlaybackController`. Platform differences are isolated behind small protocols, not `#if` through the file:
  - `AudioSessionCoordinator` stays iOS/visionOS; macOS gets a no-op that satisfies the same protocol (macOS has no `AVAudioSession`).
  - Now Playing publishing via `LegacyNowPlayingPublisher` is unchanged (`MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` exist on macOS), so media keys and Control Center work on the Mac.
- Layout: a resizable window (minimum about 420×560), a "Now Playing" hero with large artwork, the playlist as a `List` with selection, keyboard shortcuts (Space play/pause, ⌘L jump to Live), and a **Playback** menu (Play/Pause, Stream Quality).
- Optional **menu bar extra** (compact now-playing + play/pause). Listed as an open question, not a commitment.

#### 3d. Apple Music playlists (MusicKit)
- `PlaylistService` (protocol) with a MusicKit implementation:
  - `authorize()` via `MusicAuthorization.request()`.
  - `ensureKEXPPlaylist()`: find the user's playlist by stored ID, else by name, else `MusicLibrary.shared.createPlaylist(name:)`. The ID is stored in `UserDefaults`.
  - `add(play:)`: resolve the play to a catalog `Song`, then `MusicLibrary.shared.add(song, to: playlist)`.
- **Resolving the song uses identifiers, not guesses.** KEXP's API already gives each trackplay a MusicBrainz *recording ID* (`recording_id`; 38 of the last 40 trackplays carry one). The pipeline:
  1. `Play.recordingID` → **MusicBrainz** `recording/<id>?inc=isrcs` → one or more ISRCs (checked live: R.E.M. "Blue" → `USWB11004206`, `USWB11400926`; Ceremony "Other Hells" → `US2642664602`).
  2. ISRC → **MusicKit** `MusicCatalogResourceRequest<Song>(matching: \.isrc, equalTo:)` (type-checks against the macOS SDK; iOS 16+/macOS 14+). Try each ISRC and take the song available in the user's storefront.
  3. **If that resolves, add immediately** (with an undo): an ISRC identifies the recording.
  4. **If it does not** (no recording ID, no ISRC, not in the user's catalog), fall back to text search (the existing iTunes lookup) and **ask the user to confirm** the matched title/artist/album before adding.
- **Why not an audio-matching service (the AcoustID/Chromaprint approach in `concordance`)?** Fingerprinting needs audio in hand and returns a MusicBrainz recording ID, which KEXP already supplies. The identification step is done for us; an audio service would add a third party, captured audio and latency to arrive where we start. It stays a last-resort fallback for plays with no MBID (Future Directions).
- **Library change (additive, KEXPPowerKit 4.1.0):** the 2024 model trim dropped `track_id`, `recording_id`, `release_id` and `release_group_id`; `Play` regains them as optional fields, test-first.
- **MusicBrainz etiquette:** needs a descriptive `User-Agent` and about one request per second; results are cached by recording ID; `musicbrainz.org` joins the host allow-list.
- States the UI must show: not authorized, matching, added, already in playlist, no match, failed.
- Platform support verified in the SDK: `MusicLibrary`, `createPlaylist`, `add(_:to:)` and `MusicAuthorization.request()` are available on iOS 16+, macOS 14+ and visionOS 1+.

#### 3e. Widget and App Intents
- **Shared data:** a `LiveActivityService` that fetches the latest play (`limit=1`) and show. The widget and intents call it directly; they do not depend on the player.
- **Widget (WidgetKit):** small/medium "Now Playing" — artwork thumbnail, song, artist, show name. WidgetKit refreshes on the system's budget (on the order of minutes, not seconds), so the widget shows "last played at 3:42 PM", never "live". Interactive buttons (play/pause, add to playlist) are `Button(intent:)`.
- **Control Center control** (`ControlWidgetButton`, iOS 18+, not visionOS/tvOS) for play/pause, behind `#available`.
- **App Intents** (all in a framework-neutral file set shared by app and widget):
  - `WhatsPlayingIntent` — returns "Song by Artist on KEXP" as a spoken/shown result; runs without opening the app.
  - `PlayKEXPIntent` / `PauseKEXPIntent` — conform to `AudioPlaybackIntent` (verified: iOS 17+, macOS 14+) so playback can start in the background.
  - `AddNowPlayingToKEXPPlaylistIntent` — uses `PlaylistService`.
  - `AppShortcutsProvider` with spoken phrases ("What's playing on KEXP", "Play KEXP").
- **Targets and capabilities:** a widget extension target; an App Group so the widget can show the last-known play instantly from shared storage; MusicKit enabled on the App ID and `NSAppleMusicUsageDescription` in Info.plist. **These need action in the Apple Developer portal — flagged early, as the process requires.**

#### 3f. Archive (design only; build after the library work)
- **Prerequisite (library):** finish the async `ArchiveManager` (parked for 27.2). The shell provides the destination; this phase fills it.
- **View:** the 14-day window as a day picker (`ArchiveWindow.days()`), a list of shows for the chosen day (grouped by show/host/genre as the existing models do), a show detail with a start-time picker, and playback from a chosen offset (`getArchiveStreamURL(timestamp:)`).
- Archive playback reuses `PlaybackController` with a finite-duration item; Now Playing for archive reports elapsed time (the snapshot already carries `isLive`).

**New/changed files (indicative):**
`App/AppSection.swift`, `App/RootView.swift`, `Services/LiveActivityService.swift`, `Services/PlaylistService.swift`, `Services/MusicKitPlaylistService.swift`, `Audio Player/PlaybackController.swift` (renamed), `Mac/…Layout views`, `Intents/*.swift`, `KEXPWidget/` (new target), `Archive/ArchiveView.swift` (Phase D).

### 4. API Surface

```swift
enum AppSection: String, CaseIterable, Identifiable { case live, archive, playlists }

protocol LiveActivityProviding: Sendable {
    func currentPlay() async throws -> Play
    func currentShow() async throws -> Show
}

protocol PlaylistServing: Sendable {
    func authorize() async -> PlaylistAuthorization          // .authorized / .denied / .restricted / .notDetermined
    func match(_ play: Play) async throws -> PlaylistMatch?  // what we'd add, for confirmation
    func add(_ match: PlaylistMatch) async throws -> PlaylistAddResult   // .added / .alreadyInPlaylist
}

struct PlaylistMatch: Equatable, Sendable { let songID: String; let title: String; let artist: String; let album: String }

struct WhatsPlayingIntent: AppIntent { /* returns a String result */ }
struct PlayKEXPIntent: AudioPlaybackIntent { }
```

### 5. MCP Schema

N/A — application code. (App Intents are the machine-readable surface for this product: they expose "what's playing" and playback control to Siri and Shortcuts, which is this app's equivalent of the MCP-readiness rule.)

### 6. Constraints & Compliance

- **Concurrency:** Swift 6. Services are actors or `Sendable` structs; `PlaybackController` stays `@MainActor`. Intents hop to the main actor only to touch playback.
- **Safety:** no force unwraps or `try!`; MusicKit and network failures map to typed results, never crashes.
- **Privacy:** playlist adds happen only on an explicit user action (button or intent); the privacy manifest gains the MusicKit/UserDefaults declarations; widget storage holds only the last play's public metadata.
- **Hosts:** artwork and API calls stay behind the existing allow-lists (`ArtworkLoader`, `Router`).
- **Quality gate:** 0 errors / 0 warnings; no new exclusions.

### 7. Source & API Compatibility

**Breaking changes:** none to the library. Within the app, `PlayerController` is renamed `PlaybackController`; its call sites are few (`ResultRetriever`, `PlayerView`, `VideoPlayer`).
**Incremental adoption:** yes, phase by phase. The shell can ship before Mac playback; the playlist feature before the widget.
**Deployment targets:** unchanged (iOS 17, macOS 14). Control Center control behind `#available(iOS 18, *)`.

### 8. Backend Abstraction

N/A.

### 9. Resource Budget

**Data read:**
- Widget refresh: 1 play (`limit=1`, about 1 KB JSON) and 1 thumbnail (the 250 px `thumbnail_uri`, tens of KB) per refresh, at most a few times an hour.
- Live view: 50 plays per refresh every 5 seconds (existing).
- Archive day list: one 14-day window of shows, roughly 170–200 shows (one request at `limit=200`).
**Held vs streamed:** the widget holds one decoded thumbnail. The app keeps at most the 50 latest plays. The "already added" set is capped at 1,000 play IDs.
**MusicBrainz:** at most one lookup per added song, cached by recording ID; cache capped at 500 entries (a few hundred bytes each).
**Growth:** none with uptime; each cap is fixed.
**Budget:** widget extension 10 MB peak (WidgetKit's limit is tighter than the app's; the number is a target to be measured); app artwork cache stays 4 MB; added-IDs set under 50 KB.
**Measured by:** a test that feeds 5,000 plays to the playlist store and asserts the added-ID cap; the widget's memory measured on device with Instruments before release.
**Lifetime:** the app can run for days; the widget runs in short bursts. Neither accumulates.

### 10. Dependencies

**Internal:** `KEXPPower` 4.1.0 (adds MusicBrainz IDs to `Play`), `ArtworkLoader`, `NowPlayingPublishing`, `AudioSessionCoordinator`, `MusicLinks`.
**External (non-Apple):** MusicBrainz web service (public IDs only are sent; descriptive `User-Agent`, about 1 request/second, cached).
**External (Apple):** MusicKit, WidgetKit, AppIntents (all present in the 27.2 SDKs on iOS and macOS; checked).
**Library work needed:** async `ArchiveManager` (Phase D only).
**Portal:** MusicKit App ID service and an App Group (user action).

### 11. Test Strategy

**Order inside each phase:** failing tests first, then implementation, then the device check.
**Test categories:**
- **Shell:** `AppSection` ↔ selection mapping; a pure `NavigationModel` (what is shown for each size class) tested without a view.
- **LiveActivityService:** decodes a recorded `/v2/plays/?limit=1` response; failure → typed error.
- **SongResolver:** recorded MusicBrainz responses (R.E.M. "Blue" → two ISRCs; Ceremony "Other Hells" → one) through a fake MusicKit adapter. ISRC hit adds immediately; first ISRC misses and second hits; no ISRC → fallback requires confirmation; no MBID → fallback; MusicBrainz down or rate-limited → fallback; cache hit makes no request.
- **PlaylistService (the careful one):** a fake MusicKit adapter. Golden path (authorized, playlist exists, match, add → `.added`), already in playlist, denied authorization, no match, wrong-match confirmation required, duplicate add, network failure. No test touches the real library.
- **Intents:** `WhatsPlayingIntent` result string for a fixture play; airbreak (no song) phrasing.
- **Widget:** timeline entry building for a play and for failure (shows last-known), refresh policy date.
- **Mac playback:** the platform protocol with a fake player, and that `isPlaying` still mirrors `timeControlStatus`.
- **Archive (Phase D):** window days, grouping, offset selection.

**Reference Truth:** SDK interfaces checked for this proposal (`MusicLibrary.createPlaylist`, `add(_:to:)`, `MusicAuthorization.request()`, `AudioPlaybackIntent`, `AppShortcutsProvider`, `ControlWidgetButton`), plus live API responses (play 3726579, show 68216 captured 2026-11-02). Behaviors of Siri, the widget gallery and the real Apple Music library are confirmed by hand on a device, not asserted in tests.

**Validation Trace (REQUIRED):**
- Input: `Play.fixture()` (id 3000448, "I Was Riding My Bike To Work When I Realized I Have No Job" by Teezo Touchdown, album "Making Flippy Floppy").
- Expected: `WhatsPlayingIntent` result == `"I Was Riding My Bike To Work When I Realized I Have No Job by Teezo Touchdown on KEXP"`; widget entry `title == song`, `subtitle == artist`; `PlaylistMatch` for it shows the same title/artist/album before any add.
- These come from our own spec; the independent check is performing each on Brawn.

### 12. Architecture Decision Review

- Amends ADR-003 (publisher seam) — no, extends it: macOS uses the same publisher.
- **New ADR-004:** *The app/widget/intents share a `LiveActivityService`; the player is not a data source.*
- **New ADR-005:** *Navigation is an `AppSection` shell (sidebar on Mac/iPad, tabs on iPhone).*
- **New ADR-006:** *Separate app targets per platform (iOS, visionOS, macOS; tvOS/watchOS kept ready); platform-neutral code lives in `ListenKit`, its own repository, which never imports `KEXPPower`.*
- **New ADR-007:** *Songs are matched by MusicBrainz recording ID → ISRC → MusicKit, with text search plus confirmation only as the fallback.*

### 13. Adversarial Review

**Strongest case for a different approach:** ship only the Apple Music playlist button and the "what's playing" intent. A sidebar shell, a menu bar extra, a widget and a Control Center control add four surfaces to maintain for a one-developer app, and the widget cannot be live.

**Where this design is most likely wrong:**
1. **Song matching.** The MBID → ISRC path is precise, but a MusicBrainz recording can carry several ISRCs, and an ISRC can map to a different release than the one KEXP played (a reissue, a compilation). A near-duplicate is a smaller error than the wrong song. The fallback text search can still return a live version, so it asks first. About 5% of trackplays have no MBID and take the fallback.
2. **Widget freshness.** Users will read "now playing" as live; a widget that is 10 minutes stale is wrong in a way the app never is. The design shows "last played at", but the expectation gap may remain.
3. **Mac playback parity.** `MPNowPlayingInfoCenter` behaves differently on macOS (no `AVAudioSession`, different interruption model); media keys may not route as on iOS.

**What an experienced critic would say:** "You are designing a platform before you've shipped the one feature you built the app for." We proceed in phases ordered by that criticism: playlist and shell first, widget and intents after, archive last.

### 14. Alternatives Considered

**Alternative 1: One multiplatform target with `#if os(macOS)`.** Least wiring, but shells, entitlements and menus diverge enough that `#if` spreads through every file. *Rejected by the owner in favor of a separate Mac target, with shared code in a local package.*
**Alternative 2: Mac Catalyst.** Cheap, but the target is already a native multiplatform one and Catalyst would regress it.
**Alternative 3: Add to the Apple Music library directly via the iTunes track ID, with no confirm step.** Fewer taps, higher wrong-song risk. Kept as a setting ("Add without asking") rather than the default.
**Alternative 4: Share the widget's data through the player's `ResultRetriever`.** Couples the widget to app lifecycle; widgets run when the app does not. Rejected.

### 15. Future Directions

- Could add a Live Activity / Dynamic Island for the current track.
- Could add audio fingerprinting (AcoustID/Chromaprint, as `concordance` does) as a last-resort matcher for the ~5% of plays with no MusicBrainz ID, by sampling the live stream.
- Could add CarPlay (needs Apple's audio-app entitlement; confirm eligibility first).
- Could add Spotify playlist add (needs OAuth and a registered app).
- Could add a share extension ("add this link to my KEXP playlist").
- Could reintroduce the iOS 27 `NowPlaying` framework as a second publisher.
- Could sync the "added" set across devices with iCloud key-value storage.

### 16. Open Questions

1. ~~One target or two?~~ Resolved: a separate Mac target. Still open: sidebar layout (Live / Archive / Playlists), or a single window with a menu-bar extra as the primary surface? 
   New Q: package name — `ListenKit` is a working name (alternatives: `StationKit`, `StreamDeck`-free names only; avoid `NowPlayingKit`, which collides conceptually with Apple's `NowPlaying` framework). And: what is "HomeView"?
2. ~~Confirm every add?~~ Resolved: ISRC-resolved songs add immediately with undo; fallback matches ask first. Still open: does the undo suit you, or should the ISRC path also confirm until you trust it?
3. Dedicated playlist name — "KEXP"? One per user, created on first use?
4. Widget sizes: small and medium only, or also a lock-screen accessory?
5. Control Center control on iOS 18+: include in Phase C or defer?
6. Archive playback: start from the show's beginning only, or an arbitrary minute?
7. Are you willing to enable the MusicKit service and an App Group in the Developer portal now? (The widget and playlist phases are blocked without them.)

### 17. Documentation Strategy

**Documentation Type:** inline DocC on the services, intents, and `AppSection`; README gains a Features section and a platform matrix (iOS, macOS, visionOS; widget/intents where supported).
**Also updated:** CHANGELOG per phase, `project/master_plan.md` (module structure and roadmap), ADR-004/005, privacy manifest, and a session summary for each phase.
