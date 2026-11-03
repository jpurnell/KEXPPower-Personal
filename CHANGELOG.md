# Changelog

## Unreleased

### Added
- A standalone watchOS app, `Spinner Watch` (`com.JPEnterprises.Spinner.watchkitapp`, watchOS 10): live KEXP stream on the 64 kbps option, now-playing and play/pause, lock-screen and remote-command integration through `StationKit`, long-form audio session. Not yet embedded in the iOS app. The button shows a spinner while the stream buffers and a tap then cancels; album art is shown. Background audio is declared with `WKBackgroundModes` (a build setting for the key is silently dropped on watchOS, which made audio fade out when the app left the foreground). The audio mode is also declared with `UIBackgroundModes`, which is what made background playback work on the Ultra. Player status, waiting reason, item errors and the audio route are logged (category `WatchPlayer` / the iOS player's category). The Digital Crown sets the volume through the system volume control.

### Changed
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
