# ADR-003: One writer for system Now Playing state

**Date:** 2026-11-02
**Category:** architecture
**Status:** Accepted

## Decision
Exactly one type, behind the `NowPlayingPublishing` protocol, writes to `MPNowPlayingInfoCenter` and
`MPRemoteCommandCenter`. Today that is `LegacyNowPlayingPublisher`. `PlayerController` describes playback as a
`NowPlayingSnapshot` (pure data) and hands it over; it never touches `MP*` directly, and
`AVPlayerViewController.updatesNowPlayingInfoCenter` is `false`.

## Context
Before this, five places wrote the lock-screen dictionary independently, so the last writer won and keys were
dropped; artwork was stored as a `String`, which the system ignores; and `isPlaying` was toggled by hand and drifted
from the player after remote commands. Mixing the old `MediaPlayer` API with the iOS 27 `NowPlaying` framework is
also documented as undefined behavior, so the app needs a single place to choose between them.

## Consequences
- The iOS 27 `NowPlaying` framework (deferred by the owner) becomes a second conformer behind this protocol,
  selected with `#available`, not a rewrite of `PlayerController`.
- `PlayerController.isPlaying` mirrors `AVPlayer.timeControlStatus` and is never toggled by hand.
- Audio session setup and interruption/route handling live in `AudioSessionCoordinator`, not the app delegate
  (which no longer exists).
