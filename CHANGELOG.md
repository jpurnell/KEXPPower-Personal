# Changelog

## Unreleased

### Fixed
- The widget's play/pause icon lagged and sometimes stayed wrong. The app published the playing state only on its five-second poll (measured: 3.5 to 5 seconds to flip after Play), and a poll that failed skipped the heartbeat, so the flag could go stale while playing. Now the state is published about 5 ms after the player changes and the widget is reloaded then; the widget's own button publishes the state it is about to cause before returning, so the reload WidgetKit does after a tap shows the right icon, and the poll does not undo it while the stream starts; a failed poll still refreshes the flag. A reload is still the system's to schedule: background reloads are budgeted, so a change can still show late. The app and the widget log each published change and each entry built (subsystem `com.JPEnterprises.Spinner` and `com.JPEnterprises.Spinner.widget`).

### Added
- A Now Playing widget in three sizes (iPhone and iPad home screen, Mac desktop, Vision Pro on visionOS 26): small is the art with the song and artist; medium is the now-playing row (art, time, title, artist, album, release date and label) with play/pause; large adds the show and host, Spotify and Bandcamp links and the start of the DJ's comment. It shows "Last played 3:36 PM", never "live", and asks to be refreshed every five minutes (the system decides how often it actually does). The app publishes the current song to an App Group and reloads the widget only when the song, the show or the play state changes, so it does not spend WidgetKit's refresh budget on every poll. Play/pause runs in the app without opening it. The app and the widget share data through an App Group, which differs by platform: `group.com.JPEnterprises.Spinner` on iOS and visionOS (registered in the portal) and a Team-ID-prefixed group on the Mac, where a `group.` identifier is refused without an explicit profile (found when the Mac app's writes to the group were refused). Verified: the Mac app writes the current song, show and host to its group. Not yet verified on a device: please add the widget on Brawn and the Mac.
- Add to playlist (iPhone, iPad, Vision Pro): a button on each song in the list, and one on the "Now Playing" line (not on airbreaks, which are not songs; the Now Playing row keeps its full width). A tap adds the song to a "KEXP" playlist (made on first use); a press and hold also offers another of your playlists, or a new one, to add it to as well. Songs are matched by ISRC when KEXP supplies a MusicBrainz recording id (looked up on MusicBrainz, paced and cached), otherwise by a text search that asks "Is this the song?" before adding. A song is never added to the same playlist twice, including across launches. The button shows added, partly added, needs confirmation, not found, Apple Music unavailable, and needs permission. Needs the MusicKit service on the App ID and an Apple Music subscription.
- The iOS app declares the App Group `group.com.JPEnterprises.Spinner` (the widget will share data through it). That makes Xcode sign with a profile for the explicit App ID instead of the wildcard `*` profile, which grants no capabilities.
- When an add to a playlist fails, the log records MusicKit's own error and the account state (authorization, catalog playback, cloud library), because MusicKit's description of these failures is often just "An unknown error occurred".
- macOS has no add button: MusicKit marks adding to playlists and creating them unavailable on the Mac (checked in the macOS 27.2 SDK). The Mac can search the catalog and read the library; the plan's earlier note that it could write was wrong and is corrected.
- macOS: a mini player window, translucent (the desktop shows through, blurred; solid with Reduce Transparency; draggable by its background), with just what is playing (artwork, title, artist, play/pause and a button back to the full window). Playback menu: Show Mini Player (⇧⌘M) and Show Full Window (⌥⌘M). The main window is a single-instance window, so switching never opens a second one.
- `NowPlayingSummary`: the title and artist lines shown for a play ("Airbreak" and "KEXP" when missing), shared by the mini player and, later, the widget.

### Changed
- Requires `StationKit` 0.6.0 (the widget layer) and `StationKitAdapterKEXP` 0.4.0 (labels, release date and the current show), on top of the earlier requirements below.
- Requires `StationKit` 0.4.0 (song matching) and `StationKitAdapterKEXP` 0.3.0 (the mapping carries the MusicBrainz recording id), as well as
  `KEXPPowerKit` 4.1.0, which gives `Play` its MusicBrainz ids (`recordingID`, `releaseID`, `releaseGroupID`, `trackID`) for matching songs to Apple Music.
- The app has a frame: a sidebar (Live, Archive, Playlists) on the Mac, iPad and Vision Pro that can be shown and hidden (toolbar button, View menu), and tabs on the iPhone. Live is what the app showed before; Archive and Playlists say they are coming. `AppSection` drives both.
- Starting the playlist is idempotent (`startIfNeeded`), so the mini window can start it on its own and several windows can ask.

## 3.2.0 - 2026-11-04

First tagged version of the app (the number continues this repository's tag history, which ends at 3.1.1 from the library it was forked from; `0.1.0` was already taken by an old upstream tag): live KEXP playlist and stream on iPhone, iPad, Mac, Vision Pro and Apple Watch, built on `StationKit`, `StationKitAdapterKEXP` and `KEXPPowerKit`. Private until it has been used for a while; the Apple Music playlist, widget and archive features are not built yet.

### Added
- A standalone watchOS app, `Spinner Watch` (`com.JPEnterprises.Spinner.watchkitapp`, watchOS 10): live KEXP stream on the 64 kbps option, now-playing and play/pause, lock-screen and remote-command integration through `StationKit`, long-form audio session. A fresh launch can take 35–40 s to reach a working connection on a cold watch network, so the app shows "Connecting…" until the stream is ready (a tap then means "play when ready"), retries track info after 3, 6, 9 s and so on up to 15 s, and offers "Tap to retry" if the stream fails. Embedded in the iOS app (iOS builds only; the macOS and visionOS builds of the same target leave it out). The button shows a spinner while the stream buffers and a tap then cancels; album art is shown. Background audio is declared with `WKBackgroundModes` (a build setting for the key is silently dropped on watchOS, which made audio fade out when the app left the foreground). The audio mode is also declared with `UIBackgroundModes`, which is what made background playback work on the Ultra. Player status, waiting reason, item errors and the audio route are logged (category `WatchPlayer` / the iOS player's category). Volume changes are logged. The Digital Crown sets the volume through an invisible system volume control, and a slim level bar shows along the right edge only while the volume is changing.

### Changed
- The player and playlist are owned by the app, not created inside `ContentView`, so every window and the menus share one player. New Playback menu (Space plays or pauses; its title follows the player). The Play/Pause wording lives in one place (`PlaybackMenuState`).
- macOS is its own target, `Spinner Mac` (`Spinner.app`, bundle ID `com.JPEnterprises.Spinner`, macOS 14, hardened runtime): it shares the app's source files and assets but has its own entitlements (sandbox and outgoing network only; the iOS file's `network.server` is not carried over), build settings and scheme. The iOS target now builds for iOS and visionOS only. The Mac app still has no playback; that is the next step.
- New app icon on every platform: four bars in a yellow gradient with the proportions of the KEXP logo (same heights, spacing, bottom-aligned), without the wordmark. The wave is its own transparent layer on visionOS; iOS and the App Store icon sit it on a dark warm background (opaque); macOS bakes the rounded tile into the canvas; the watch icon is the wave on near-black, sized to stay inside the circle the system masks it to.
- Player glue (Now Playing snapshot and publisher, audio session coordinator, artwork loader) now comes from `StationKit` 0.2.0, and the KEXP stream and now-playing mapping from `StationKitAdapterKEXP` 0.2.0; the app's copies and their tests (moved to StationKit) are removed. `KEXPPowerKit` is 4.0.1.
- visionOS: the app icon's last layer is opaque and the logo is its own transparent layer; the App Store icon has no alpha; the macOS icon fills the standard icon grid. `allowsExternalPlayback` is not used on visionOS, where it does not exist.
- The app consumes the KEXPPower library as a package (`jpurnell/KEXPPowerKit` 4.0.0, by URL; `Play` is now a `Sendable` struct) instead of
  compiling a fork's sources into the app target. See `project/decisions/ADR-002-library-in-its-own-repo.md`.
- Now Playing: a single publisher (`LegacyNowPlayingPublisher`) writes system state; the player no longer
  does. `PlayerController.isPlaying` mirrors the player's own `timeControlStatus`, so remote commands and
  interruptions cannot leave it out of step.
- The playlist refresh requests 50 plays instead of 2,000 every five seconds, and a refresh can no longer
  start a second, overlapping loop.
- Controls honor Reduce Transparency; icons carry accessibility labels.

### Fixed
- macOS: the app now plays the stream (`PlayerController` is no longer iOS/visionOS-only; Now Playing, media keys and the play/pause button work; artwork is encoded with ImageIO instead of UIKit). A refresh no longer replaces the player, which would have cut off playback.
- macOS: the show header and "Now Playing" label were hidden and the edges were rough, because a play row's blurred backdrop was not clipped and spilled over its neighbours. The backdrop is now the row's clipped background, list rows have no alternating bands, rows fill the window width, and the expanded details use up to 720 pt of it (340 pt on iOS and visionOS). The DJ comment was drawn twice on macOS; it is drawn once.
- macOS: a Previously row only answered a click in its top half (the tap handler sat on the row's content, inside the scroll view; measured with a click log, taps 31 and 63 pt down fired and 85 pt and deeper did not). The tap handler is now on the finished row, so the whole row toggles, and the expanded details no longer contain a nested scroll view on the Mac, which would also have taken clicks. The overlay-scroller helper no longer takes clicks.
- macOS: the play/pause button sits on the "Now Playing" label line instead of beside the row, so the row keeps the full width. The playlist is a scroll view with the same margins as Now Playing (a Mac `List` added its own insets), and scrollers are overlay-style, so a permanent scrollbar no longer takes a gutter.
- iOS: the play/pause button did not follow the player. `PlayerController` was an `ObservableObject` held by an `@Observable` `ResultRetriever`, so a change to `isPlaying` never reached the view; it is `@Observable` now, with a test that a view reading `isPlaying` is notified.
- Playback resumes after an interruption (a phone call) when the system says it may, and pauses when headphones are unplugged.
- Artwork loading no longer crashes on an unreachable or malformed URL (`try!`), and only contacts
  kexp.org and archive.org over https. Loaded artwork now actually reaches the lock screen.
- Removed `.animation(_, value: 1.0)` modifiers that keyed off a constant and never animated.

### Removed
- The in-repo KEXPPower framework, its XCTest target, the UIKit `KEXPPowerExample` app, the CocoaPods podspec,
  and two dead UI-test targets.
- `beginReceivingRemoteControlEvents()` and a dead macOS block in the app delegate.

### Added
- Links out: Spotify and Bandcamp searches for the playing track, and web links in DJ comments are now tappable (`MusicLinks`).
- `AudioSessionCoordinator` owns the audio session; the app delegate is removed.
- The app and its tests build in Swift 6 language mode.
- Stream quality setting (160 kbps standard, 64 kbps data saver), in Settings on macOS.
- `ArtworkLoader`, `NowPlayingSnapshot`, `NowPlayingPublishing`, and a hosted unit-test target
  (`KEXPPowerAppTests`, Swift Testing).
- Privacy manifest (`PrivacyInfo.xcprivacy`; no tracking, no collected data).

## 3.0.0

The CocoaPods release of KEXPPower (podspec 3.0.0) that this project forked. See the git history.
