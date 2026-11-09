# Design Proposal: Spinner TV (a tvOS app target)

**Status:** APPROVED 2026-11-08 and BUILT the same day on `tvos-target` (owner: "yes on the new target with iOS sources"; remote steps "yes"; "let's do the best experience for each device"). Runs on the tvOS 27.2 simulator; see §8.
**Date:** 2026-11-08
**Master Plan Reference:** Technology Stack ("tvOS is kept *ready* … but not built"); ADR-006 (a target per platform); `PlatformExperience.md` "Platform readiness". The master plan's tvOS line predates the archive and live rewind; this proposal reads what is built now.
**Facts marked (SDK) were read from the Xcode 27.2 SDK interfaces; (survey) from the compile survey in §2; (repo) from this repository at `6184370`. Anything not confirmed is marked *unverified*.**

---

### 1. Objective
The Spinner app on Apple TV, with the iOS app's sections, not a reduced player:

| Section | On tvOS |
|---|---|
| **Live** | now playing, the show and host, the Previously list, live rewind (skip back and forward, back to live) |
| **Archive** | the last fifteen days by Date, Host, Show or Genre; play a show; skip and a timeline |
| **Review** | songs waiting to be added to a playlist, and **Add to Apple Music playlist** (MusicKit's library calls exist on tvOS 16 (SDK); only macOS lacks them) |
| **Playlists** | "coming soon", as on every platform |

The Siri Remote's play/pause button, and the TV's Now Playing (Control Center, the remote's screen on iPhone), go through StationKit's `MPRemoteCommandCenter` path, as elsewhere.

### 2. What is built, and what compiles for tvOS (survey, 2026-11-08)
I built the three packages at the versions the app pins for the tvOS simulator, and type-checked every app source file except `Mac/` and `CarPlay/` against them, at tvOS 17 in Swift 6 mode:
- **Packages:** `StationKit` 0.11.0, `StationKitAdapterKEXP` and `KEXPPowerKit` all build for tvOS. "Kept ready" holds.
- **App:** with only the changes below, all of it type-checks for tvOS: Live, Archive, live rewind, Review and song saving, show information, links and diagnostics.

| Where (repo) | tvOS problem (SDK) | Proposed |
|---|---|---|
| `ArchivePlayerBar`, `LiveRewindControls` | `Slider` is unavailable | a focusable timeline the remote moves left and right (§3c); the skip buttons already work |
| `RootView` | `.badge` on tabs and the `.bar` background are unavailable | no tab badge (the Review count shows in its section); a material background |
| `PlaybackCommands` | `Commands`, `CommandMenu`, `keyboardShortcut` are unavailable | not in the TV target (no menu bar) |
| `Widget/WidgetContent`, `NowPlayingWidgetViews` | widget-only APIs | not in the TV target (no widgets on tvOS (SDK)) |
| `Audio Player/AVPlayer.swift` | `AVPlayerViewController.updatesNowPlayingInfoCenter` is unavailable | a decision under ADR-003 (§3d) |

They compile, but don't belong on a TV: the Spotify and Bandcamp web links (tvOS has no browser) and pull-to-refresh (already left out on the Mac). Both are hidden on tvOS.

*Not covered by the survey:* the uncommitted live-rewind work on `swiftui_example`, and anything that only shows up when the app runs (focus behaviour, layout at 1920×1080). Those are checked when the target is built.

### 3. Proposed Architecture
#### 3a. A separate target, sharing the iOS app's sources
`Spinner TV`: a tvOS application target, deployment target tvOS 17. It compiles the same source files as the iOS target except `CarPlay/`, `Mac/`, the widget views and `PlaybackCommands`, and links `StationKit`, `StationKitAdapterKEXP` and `KEXPPower`. tvOS-only code lives in `#if os(tvOS)` branches inside the shared files, the way `os(macOS)` and `os(visionOS)` already do (repo: 16 `os(macOS)` and 14 `os(iOS)` branches).

**Why a separate target, not a tvOS destination on the iOS target** (as visionOS has): ADR-006 says a target per platform. The survey also hit a concrete obstacle: the iOS target embeds the widget extension and the watch app, and Xcode refuses a tvOS build that embeds iOS content ("contains embedded content (Spinner Widget.appex) built for iOS Simulator"). A separate target avoids per-platform embed filters.

#### 3b. Layout
A top `TabView` with the sections, the tvOS norm, rather than the sidebar the iPad and Mac use. Lists and grids use focus: rows are buttons, so the remote moves between them and selects. The player bar sits at the bottom, as elsewhere.

#### 3c. The timeline
`Slider` does not exist on tvOS (SDK). The archive and live-rewind timelines become a focusable bar. Left on the remote goes back 15 seconds and right goes forward 30, the intervals of the existing skip buttons in both players (repo: `ArchivePlayerBar`, `LiveRewindControls`). Live rewind keeps its back-5-minutes button. This bar is the one new control. It gets unit tests for the step arithmetic, which reuses `ArchiveTransport`'s and `LiveWindow`'s existing fraction math.

#### 3d. Now Playing ownership (ADR-003)
ADR-003 makes StationKit's publisher the only writer of Now Playing. On iOS, `AVPlayer.swift` keeps that rule by setting `AVPlayerViewController.updatesNowPlayingInfoCenter = false`, and that property does not exist on tvOS (SDK). *Unverified:* whether tvOS's `AVPlayerViewController` then writes Now Playing itself and competes with the publisher. **Proposed:** check it on the simulator first. If it competes, the TV target plays audio without an `AVPlayerViewController` (the live stream has no video), which keeps ADR-003 intact.

#### 3e. Identity
Bundle ID `com.JPEnterprises.Spinner`, shared with iOS, visionOS and macOS, so tvOS joins the universal purchase (owner, 2026-11-08). **Portal step for you, when it ships:** add tvOS to that App ID. Simulator builds need no signing.

#### 3f. Not in v1
- Top Shelf
- layered app icons (App Store submission needs them; the simulator does not)
- the web links
- widgets, CarPlay and Control Center controls (none exist on tvOS (SDK))

### 4. Error Handling
Unchanged: the shared code's notices and errors are what the TV shows. There are no force unwraps, per the coding rules.

### 5. Testing Strategy
- **Unit:** the timeline step arithmetic (§3c), test-first. The shared models keep their existing tests, which run on iOS and macOS.
- **Build:** `Spinner TV` builds for the tvOS simulator, and every existing scheme still builds, since shared files gain `os(tvOS)` branches.
- **On the simulator, with sim-tap:** switch tabs, play live, open the archive and play a show, skip and move the timeline, add a song from Review. This is also sim-tap's tvOS verification.
- **Quality gate:** zero errors and warnings.

### 6. Open Questions for the Owner
1. Approve a separate `Spinner TV` target that shares the iOS sources (§3a)?
2. On the remote, left = back 15 s and right = forward 30 s on both timelines, matching the skip buttons (§3c)?
3. If tvOS's player view competes with the Now Playing publisher, approve dropping `AVPlayerViewController` on tvOS (§3d)?

### 7. Merge note
This branch (`tvos-target`) starts from `6184370`. `swiftui_example` has uncommitted changes to `project.pbxproj`, three schemes and several shared Swift files, including the live-rewind ones this target would compile. Two things follow:
- **Order:** build `Spinner TV` after that work is committed, so the TV target compiles the current live rewind, not the one at `6184370`.
- **Merging:** the two branches will meet in `project.pbxproj`. My additions are new objects and new list entries, so the conflict is mechanical, but whoever merges second should open the project in Xcode afterwards to confirm it.

### 8. As built (2026-11-08)
- **Target:** `Spinner TV` was added to `project.pbxproj` by script, in Xcode's text format. It compiles the iOS target's sources except `PlaybackCommands`, `WidgetContent`, `NowPlayingWidgetViews` and the three CarPlay files, and adds `Spinner TV/Info.plist` (background audio). The bundle ID is `com.JPEnterprises.Spinner`. It has no app icon yet (§3f).
- **§3c, simpler than proposed:** left and right on the focused timeline call the existing `browser.skip(by:)` and `player.skipLive(by:)` (back 15 s, forward 30 s), which already have tests. Nothing new needed unit tests.
- **§3d, resolved without a test:** tvOS has no use for the system player view (`VideoPlayer` is iOS and visionOS only), so the TV target never creates an `AVPlayerViewController`, and the publisher stays the only Now Playing writer.
- **Found on the simulator:** setting `AVPlayerItem.externalMetadata` crashed on tvOS ("unrecognized selector"), because the property is an AVKit addition and the TV app never loads AVKit. It fed only the system player view, so it is now iOS and visionOS only.
- **Also changed:**
  - `RootView`: tvOS always uses tabs; no tab badge; the player bar's background is a material, or solid black with Reduce Transparency.
  - The song detail: no web links on tvOS.
  - The app: no menu commands on tvOS.
- **Builds:** `Spinner TV` (tvOS), iOS, visionOS, macOS and watchOS all build, with zero warnings.
- **Runs:** on the tvOS 27.2 simulator it opens on Live with the show, host and Previously list.
- **Quality gate:**
  - Every checker but `unreachable` matches the base commit exactly. The one new finding (a material without a Reduce Transparency fallback) was fixed.
  - `unreachable` fails here and on the untouched base commit alike, because in a fresh worktree its result depends on which scheme was built last: sources shared across targets through `#if` look unreachable from whichever platform compiled last.
  - It is a checker limitation and is reported to the owner, not suppressed.
- **Checked with sim-tap's tvOS driver (2026-11-08):** the four tabs, Play, the Archive's pickers and day strip, and the Apple Music prompt from Add to playlist.
- **Found by that check, and fixed:** the TV app had no way to start live playback. The Now Playing section was compiled for iOS, visionOS and macOS only, so tvOS showed neither the play button nor the song on the air (the Previously list leaves it out), and the remote's Play/Pause reaches `MPRemoteCommandCenter` only once the app is already playing. tvOS now has its own Now Playing: a labelled Play/Pause button and the song's card. `PlaybackCommands.swift` is compiled into the TV target for `PlaybackMenuState`, with the menu itself behind `#if !os(tvOS)`.
- **Not yet done:** playing an archive show and moving its timeline, and adding a song from Review.
- **Superseded:** the `unreachable` note above. It was a checker bug (one USR per module), fixed in quality-gate 3.8.0; the gate now passes here.
