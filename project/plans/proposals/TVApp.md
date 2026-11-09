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
- **Not yet done:** ~~playing an archive show and moving its timeline~~ (done 2026-11-09, below), and adding a song from Review.
- **Superseded:** the `unreachable` note above. It was a checker bug (one USR per module), fixed in quality-gate 3.8.0; the gate now passes here.

### 9. Player column (2026-11-09)
- **Checked with sim-tap:** an archive show plays, with the truncation note; the timeline moves right +30 s and left −15 s; Pause holds the position, Back 15 works while paused, and Play resumes. Review shows its empty state; a queue with entries needs a signed-in Apple Music account, so it is left for a real Apple TV.
- **Found:** the player bar, at the bottom as §3 proposed, could be reached only past the last row of the list above it: the focus engine takes the next row before anything beneath the list. On a long day that was a dozen presses or more.
- **Changed, departing from §3's "the player bar sits at the bottom, as elsewhere":** on tvOS the bar is a 560-point column on the right, one focus section, so Right from a row at any height reaches it, and Left returns. Checked: Right from the fifth show of Nov 7 landed on the timeline; Down then Right reached Back 15 and Pause.
- **Added:** the remote's Play/Pause button calls `playOrPause()` from anywhere. It is on the `TabView`, not inside a section, because at launch focus is in the tab bar, outside every section; on the section it did nothing until focus moved into the content. Checked from a list row (paused and resumed an archive show) and from the tab bar at launch (started live).
- **Also fixed:** two-digit days in the day strip wrapped a digit per line ("3" over "0"), which is why the Oct 25–30 tiles were taller; the number is now one line, shrinking if needed.
- **Not changed:** the Oct 30 "That show is no longer available" was a station outage that day, not a bug.

### 10. Now Playing tab, replacing the column (2026-11-09)
- **The column was wrong.** Seen by the owner in DeviceHub: folded, it was a dark third of every screen holding one line; it squeezed the Host grid until names broke a syllable per line; on Live it stood beside the existing Play button, so Right from a song led to a fold chevron. Struck: ~~the 560-point column of §9~~.
- **Now:** a Now Playing tab (`AppSection.nowPlaying`, shown by `visible(canSaveToPlaylists:showsNowPlaying:)` only on tvOS once something has played). It shows the archive player, or the live bar with its rewind controls and the song's card, unfolded (`canFold: false`). Sections have no player bar on tvOS. Menu goes to the tab bar from anywhere, then Right to the tab: the tvOS route, and the one Apple Music used on Apple TV.
- **Also found by the owner:** the archive playlist sheet collapsed to its title line, because a tvOS sheet sizes to its content and a list has none; it is now 1200 × 820. Its time column (96 pt, a phone's width) wrapped "12:03:14 AM EST" over three lines; 220 on tvOS.
- **Cards:** 520-point minimum columns on tvOS, names two lines at most, counts never wrapped, and each card as tall as its row.
- **Checked with sim-tap:** Menu then Right ×4 reached Now Playing; Down reached the timeline, then Back 15, Pause, Forward 30 and Playlist in that order; the playlist opened full size. sim-tap's own scan for "Playlist" ran out of moves where the plain arrows worked, a sim-tap limitation to look at there.

### 11. Grids and the player, tuned for focus (2026-11-09)
From the owner's DeviceHub screenshots:
- **Date:** the adaptive 84-point grid ran fifteen narrow tiles across the screen with an uneven tail. Now five fixed columns (three even rows), 180-point tiles, 40 points apart.
- **Host, Show, Genre:** cards were too short and too close for the focus lift, which covered neighbours. Now 136 points tall at least, 24-point insets, 88-point pictures, 48 points apart; the show count moved beneath the name and the chevron is gone on tvOS, so a name has the card's width.
- **Button style:** `.plain` on tvOS drew a focus platter around the tile's own background (a frame within a frame); tiles and cards now use `.card`, which lifts the tile.
- **Player:** rows were 8 points apart, so the lifted Catch-up button covered the timeline; 32 on tvOS, a 32-point inset, 12 between the timeline and its clocks. The focusable timeline showed no focus at all; it now thickens and gets a highlight capsule.

### 12. Add to playlist from Live (2026-11-09)
- **Found by the owner:** Select on a Live song's + expanded the row and saved nothing. `CombinedView`'s `.onTapGesture` (expand) on the row also fires for Select on the `SaveButton` in its overlay. tvOS rows are not focusable, so the gesture only ever fired by accident; it is now left out on tvOS, and rows there do not expand.
- **Checked with sim-tap:** Select on the Now Playing + no longer expands the row and runs the save, which on the lab simulator stops at the lock (Apple Music access was denied there on 2026-11-08). A completed add still needs a real Apple TV signed in to Apple Music.
- **Details (owner request):** a ⓘ button beside + on each song. Tried first as the iPhone's in-place expansion: the expanded row was taller than the screen and held nothing focusable, so focus stuck on its buttons and the notes could not be scrolled to. Now a sheet (`PlayDetailsSheet`, tvOS only): artwork, song, artist, album, release · label, and the notes split into focusable paragraphs. Checked with sim-tap on an airbreak, and on Lou Reed's "Satellite of Love" with two paragraphs of notes; Menu closes it.
- **The lock:** it means Apple Music access was denied (`needsPermission`); pressing it asks again, which tvOS answers from the stored decision. `xcrun simctl privacy <udid> reset media-library com.JPEnterprises.Spinner` brings the prompt back on a simulator. ~~There is no route from the lock to Settings yet.~~ Done (§13).

### 13. Icon, Settings from the lock, no Playlists (2026-11-09)
- **Icon (§3f, resolved):** `App Icon & Top Shelf Image.brandassets` in the shared catalog, set as the TV target's `ASSETCATALOG_COMPILER_APPICON_NAME`. A two-layer image stack, bars in front of the gradient (the visionOS icon's Front and Middle layers), at 400×240 @1x/@2x and 1280×768 for the App Store; Top Shelf 1920×720 and wide 2320×720, @1x/@2x. Opaque images carry no alpha channel (App Store validation refuses one in a back layer). Seen on the simulator's Home screen and on Spinner's Settings page. Not seen: the Top Shelf banner itself; the simulator's Home screen went black (the screensaver, after Menu presses) before it could be looked at.
- **Lock → Settings:** `SaveState.opensSettings` (tested) is true only for `needsPermission`; the button then opens `UIApplication.openSettingsURLString`. Checked: revoked access, + showed the lock, Select on it opened Spinner's page in Settings at "Media & Apple Music: Never".
- **Playlists removed** on every platform at the owner's word that it is enabled nowhere. `AppSection.playlists`, `isAvailable`, `comingSoonMessage` and `ComingSoonView` are gone.

### 14. Merged with Settings and the CarPlay archive (2026-11-09)
- `swiftui_example` gained Settings (`ListeningSettings`, `ShowTimeZone`, a gear on iPhone and iPad, the Mac's Settings window) and CarPlay's Archive tab while this branch was open. Merged into `tvos-target`: the project file's four conflicts were both sides adding entries; the archive playlist's clock takes the chosen zone and keeps the tvOS width.
- Spinner TV now compiles `ListeningSettings.swift` and `ShowTimeZone.swift`, which the shared views use. **Gap:** tvOS has no way into Settings yet (the gear is iPhone and iPad only), so a TV uses the default stream and time zone.
- Checked after the merge: every platform builds, 417 app tests pass, and on the tvOS simulator Live, the Archive (Show mode), an archived show in Now Playing and the Top Shelf all work.
