# Design Proposal: Playback Hardening

**Status:** Approved 2026-11-02 — moved to upcoming/
**Date:** 2026-11-02
**Sequence:** Proposal 1 of 2. Must land before [NowPlayingFramework.md](../proposals/NowPlayingFramework.md).

---

### 1. Objective

Bring the SwiftUI app's playback layer to a correct, crash-free baseline that builds
with the iOS 27 SDK and runs on iOS 17 through 26, using only the existing
`MediaPlayer` / `AVFoundation` APIs. No new framework adoption.

**Master Plan Reference:** none yet — `project/master_plan.md` is still the unfilled
template (see Open Question 1).

### 2. Motivation

**Current situation:** `PlayerController` (`KEXPPower SwiftUI/Audio Player/AVPlayer.swift`)
owns the `AVPlayer` and also writes to the system Now Playing state from several
places. Review found these defects:

| # | Location | Defect |
|---|----------|--------|
| G1 | `AVPlayer.swift:118` | `try!` on the artwork network fetch. A bad URL or offline state crashes the app. |
| G2 | `AVPlayer.swift:98-104` | `setupMetadata()` assigns `artwork` into `externalMetadata` before the `Task` that loads it has finished, so the loaded artwork is never used. |
| G3 | `AVPlayer.swift:195, 249` | A `String` is stored under `MPMediaItemPropertyArtwork`, which expects `MPMediaItemArtwork`. The value is ignored. |
| G4 | `AVPlayer.swift:185, 190, 232, 242`, plus `updatesNowPlayingInfoCenter = true` at line 138 | Five independent writers to `MPNowPlayingInfoCenter`, each building its own dictionary. The last writer wins, and `setNowPlayingMetadata` drops all prior keys. |
| G5 | `AVPlayer.swift:272-275` | `playOrPause()` toggles `isPlaying` regardless of whether the player actually changed state. It drifts after interruptions and remote commands. |
| G6 | `AVPlayer.swift:145-162` | Remote play/pause handlers return `.commandFailed` when `isPlaying` disagrees with the player, so a legitimate lock-screen tap can be rejected after drift (G5). |
| G7 | `AVPlayer.swift:258-266` | `pausePlayer()` deactivates the audio session on every pause, which tears down the lock-screen controls. |
| G8 | `KEXPPowerExampleSwiftUIApp.swift:54-58` | `#if os(macOS)` block inside an `#if os(iOS) \|\| os(visionOS)` region: dead code, and a bare `macViewController` expression. |
| G9 | `KEXPPowerExampleSwiftUIApp.swift:38` | `beginReceivingRemoteControlEvents()` is the legacy mechanism and unnecessary with `MPRemoteCommandCenter`. |
| G10 | No interruption or route-change handling | A phone call or unplugged headphones leaves `isPlaying` wrong. |
| G11 | Repo root | `TigerHead.swift` (248 KB), `medallionBECW.swift` (250 KB), `GameOfLife*.swift` are untracked and outside any target. |
| G12 | Project settings | `SWIFT_VERSION = 5.0`; strict concurrency is not enforced. |

**Workaround today:** none; these are latent.
**Drawback:** G1 is a crash, G4–G7 produce wrong lock-screen state, G2/G3 mean artwork
never reaches the system.

### 3. Proposed Architecture

Introduce one seam so Proposal 2 can swap the implementation without touching the UI.

**New Files** (in `KEXPPower SwiftUI/Audio Player/`):
- `NowPlayingPublishing.swift` — the protocol below plus `NowPlayingSnapshot`, a pure value type.
- `LegacyNowPlayingPublisher.swift` — the single `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` writer.
- `ArtworkLoader.swift` — async, cancellable, cached artwork fetch that never traps.
- `AudioSessionCoordinator.swift` — category setup, interruption and route-change observation.

**Modified Files:**
- `AVPlayer.swift` — `PlayerController` drives the publisher; remove direct `MP*` calls.
- `KEXPPowerExampleSwiftUIApp.swift` — remove G8 and G9.
- `KEXPPower.xcodeproj` — Swift 6 language mode (G12), app target first, then the framework target.

**Removed:** G11 files already moved out of the repo root by the owner.

### 4. API Surface

```swift
/// What the system should be told about playback. Pure data, no framework types.
struct NowPlayingSnapshot: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String
    var artworkURL: URL?
    var isLive: Bool
    var state: PlaybackState          // .stopped / .playing / .paused / .buffering
}

@MainActor
protocol NowPlayingPublishing: AnyObject {
    func publish(_ snapshot: NowPlayingSnapshot, artwork: PlatformImage?)
    func setHandlers(play: @escaping () -> Void, pause: @escaping () -> Void)
    func invalidate()
}

actor ArtworkLoader {
    func image(for url: URL) async -> PlatformImage?   // nil on any failure; cancels cleanly
}
```

`PlayerController.isPlaying` becomes derived from `player.timeControlStatus` (observed),
not toggled by hand (fixes G5, G6).

### 5. MCP Schema

N/A — this is an application's internal playback layer, not a public API consumed by
AI tools.

### 6. Constraints & Compliance

- **Concurrency:** `NowPlayingSnapshot` is `Sendable`; publisher and controller are
  `@MainActor`; `ArtworkLoader` is an actor.
- **Safety:** no `try!`, no force unwraps (G1); all failures log with explicit
  privacy annotations and degrade to a placeholder image.
- **Determinism:** snapshot construction is a pure function of player state.
- **Quality gate:** target 0 errors / 0 warnings, no suppression comments.

### 7. Source & API Compatibility

**Breaking changes:** none to `KEXPPower` framework public API; changes are confined to
the example app target.
**Incremental adoption:** yes — each defect fix is independently committable.
**Type-checking risk:** none; no existing function overloaded.
**Deployment target:** unchanged at iOS 17 (decided; a brief move to 26 for the upstream package was reversed when the fork was kept, ADR-001).

### 8. Backend Abstraction

N/A — not compute-intensive.

### 9. Resource Budget

**Data read:** one artwork image per track change (KEXP serves roughly 100–400 KB JPEGs).
**Held vs streamed:** `ArtworkLoader` holds at most the current and previous image in an
`NSCache` with a 4 MB cost limit. Nothing accumulates.
**Growth:** none with listening time; track changes replace entries.
**Budget:** 4 MB peak and 2 MB at rest for artwork.
**Measured by:** a test that loads 500 distinct artwork URLs from a stub session and asserts
the cache count never exceeds its limit.
**Lifetime:** the app can run for days on the lock screen; the test above is the check
that it doesn't grow.

### 10. Dependencies

**Internal:** `KEXPPower` framework (`PlayResult`, `ResultRetriever`).
**External:** none new.

### 11. Test Strategy

**Test Categories:**
- Golden path: snapshot → publisher output; state transitions from `timeControlStatus`.
- Edge: nil / empty artwork URL, offline fetch, cancelled fetch, rapid track changes.
- Invalid: malformed artwork URL must not crash (G1 regression test).
- Determinism: same player state yields an equal snapshot.
- Interruption: simulated `AVAudioSession.interruptionNotification` begin and end.

**Reference Truth:** Apple's documented `MPNowPlayingInfoCenter` contract (artwork key
type, `MPNowPlayingInfoPropertyIsLiveStream`). Behavior against the real lock screen
is checked by hand on a device; the simulator does not show it faithfully.

**Validation Trace (REQUIRED):**
- Input: `title "Song"`, `artist "Artist"`, `album "Album"`, `artworkURL nil`, `isLive true`,
  `state .playing`.
- Expected dictionary (from the key contract): `MPMediaItemPropertyTitle == "Song"`,
  `MPMediaItemPropertyArtist == "Artist"`, `MPMediaItemPropertyAlbumTitle == "Album"`,
  `MPNowPlayingInfoPropertyIsLiveStream == true`, no `MPMediaItemPropertyArtwork` key
  (rather than a `String` value, G3).
- This is derived from our own spec, not an independent oracle; the on-device check is the
  independent confirmation.

### 12. Architecture Decision Review

- [ ] Reviewed `architecture_decisions.md` — none exists yet in `project/decisions/`
- Supersedes an existing ADR? No
- New ADR required? **Yes** (draft below)

**New ADR Draft:** *Single Now Playing publisher.* Category: architecture. Key decision:
exactly one type writes system Now Playing state; the player never touches `MP*` directly.

### 13. Adversarial Review

**Strongest case for a different approach:** skip this proposal and go straight to the
iOS 27 framework, which deletes G3–G7 by construction. Less work overall.

**Where this design is most likely wrong:** it assumes the legacy path will outlive iOS 27 adoption (it stays as the implementation for iOS 17–26). If the minimum target moves to 27 soon, this is throwaway.

**What an experienced critic would say:** "You're polishing the API you're about to
replace." We proceed because G1 is a crash that ships today, and the protocol seam is
what makes Proposal 2 a small diff rather than a rewrite.

### 14. Alternatives Considered

**Alternative 1: Fix defects in place with no protocol.**
- Advantage: smaller diff.
- Disadvantage: Proposal 2 then rewrites `PlayerController` internals.
- Why rejected: the seam costs about 60 lines and pays back immediately.

**Alternative 2: Use `AVPlayerViewController.updatesNowPlayingInfoCenter` only and delete
manual publishing.**
- Advantage: least code.
- Disadvantage: no control over live-stream metadata, which changes every track while
  the `AVPlayerItem` stays the same.
- Why rejected: KEXP's metadata comes from the plays API, not the stream.

### 15. Future Directions

- Could add `AVPlayerItemMetadataOutput` to read in-stream metadata if KEXP exposes it.
- Could persist the last-played stream and bitrate across launches.

### 16. Open Questions (resolved 2026-11-02)

1. `master_plan.md`: to be filled in now, by interview, before implementation.
2. Deployment target stays at iOS 17 (reaffirmed 2026-11-02 after keeping the fork).
3. Swift 6 language mode: **yes, in this proposal.**
4. Stray root-level files: moved or deleted by the owner. Done.

### 17. Documentation Strategy

**Documentation Type:** inline DocC comments on the protocol and snapshot; no `.docc`
catalog (the app target has no public API).
**Also updated:** `CHANGELOG.md` (create), `README.md` (platform and requirements
claims), session summary in `project/summaries/`.
