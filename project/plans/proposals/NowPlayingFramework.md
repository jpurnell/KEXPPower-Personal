# Design Proposal: NowPlaying Framework Adoption (iOS 27+) and Native macOS / visionOS Targets

**Status:** Proposed — awaiting approval
**Date:** 2026-11-02
**Sequence:** Proposal 2 of 2. Depends on [PlaybackHardening.md](PlaybackHardening.md).

---

### 1. Objective

Adopt the iOS 27 `NowPlaying` framework behind `if #available(iOS 27, *)`, keeping the
legacy publisher from Proposal 1 as the fallback, and extend the same playback layer to
a native macOS target (visionOS already builds). tvOS and watchOS are out of scope per the master plan (decided 2026-11-02).

### 2. Motivation

**Current situation:** system integration is dictionary-and-handler based
(`MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`). iOS 27 introduces a model-owned
alternative where the player describes itself to the system. Apple's article-level
guidance, confirmed against the SDK interface, is that mixing the two on one session is
undefined behavior, so adoption is a branch, not a blend.

**Workaround today:** the legacy API keeps working on iOS 27.
**Drawback:** the legacy path gets no new system features, and the app has only an iOS /
visionOS target today even though the core `KEXPPower` framework is largely portable.

### 3. Proposed Architecture

**Verified against the iOS/macOS/tvOS/watchOS/visionOS 27.2 SDK interfaces:**

| Capability | iOS | macOS | tvOS | watchOS | visionOS |
|------------|-----|-------|------|---------|----------|
| `MediaSession`, `MediaSessionRepresentable`, `MusicContent`, `MediaPlaybackSnapshot`, `MediaCommand`, `requestToBecomeApplicationPrimary()` | 27 | 27 | 27 | 27 | 27 |
| `requestToBecomeSystemPrimary()`, `isSystemPrimary` | 27 | unavailable | unavailable | unavailable | unavailable |
| `RemoteMediaSession`, `ArtworkRepresentation` | 27 | unavailable | unavailable | unavailable | unavailable |

So the core integration is portable to every platform; only system-primary and
remote-session features are iOS-only. This proposal does not use those two.

**New Files** (shared across targets):
- `ModernNowPlayingPublisher.swift` — `@available(iOS 27, macOS 27, tvOS 27, watchOS 27, visionOS 27, *)`
  conformer to `MediaSessionRepresentable`; builds `MusicContent` and `MediaPlaybackSnapshot`.
- `NowPlayingPublisherFactory.swift` — chooses modern or legacy at runtime.

**Modified Files:**
- `AVPlayer.swift` — `PlayerController` asks the factory for a publisher.
- `KEXPPower.xcodeproj` — new targets (below).

**New Target (native, not Catalyst or "Designed for iPad"):**
- macOS app (SwiftUI). Current macOS deployment is inconsistent (12.1 / 14.0); set one value. visionOS already builds from the iOS target.
- Shared playback group compiled into all app targets; `KEXPPower` framework gains `macosx`,
  `appletvos`, `watchos` in `SUPPORTED_PLATFORMS` once a portability audit passes.

The fallback matters beyond iOS: macOS and visionOS older than 27 would use
`MPNowPlayingInfoCenter` too. `UIKit`-only code (`UIImage`, `AVPlayerViewController`,
`UIApplicationDelegate`) must sit behind a `PlatformImage` typealias and `#if canImport`.

### 4. API Surface

```swift
@available(iOS 27, macOS 27, tvOS 27, watchOS 27, visionOS 27, *)
@MainActor @Observable
final class ModernNowPlayingPublisher: MediaSessionRepresentable, NowPlayingPublishing {
    let id: String
    private(set) var snapshot: NowPlayingSnapshot

    var content: (any MediaContentRepresentable)? {
        MusicContent(
            id: snapshot.playID,
            songTitle: snapshot.title,
            artistName: snapshot.artist,
            albumName: snapshot.album,
            type: .audio,
            duration: .live,                      // MediaDuration? accepts .live
            artwork: artwork                      // Artwork(id:artworkProvider:)
        )
    }
    var playbackSnapshot: MediaPlaybackSnapshot? {
        .init(state: mappedState, elapsedTime: nil)
    }
    var commands: [MediaCommand] {
        [.play { await self.onPlay() }, .pause { await self.onPause() }]
    }
}

enum NowPlayingPublisherFactory {
    @MainActor static func make() -> any NowPlayingPublishing {
        if #available(iOS 27, macOS 27, tvOS 27, watchOS 27, visionOS 27, *) {
            return ModernNowPlayingPublisher()
        } else {
            return LegacyNowPlayingPublisher()
        }
    }
}
```

**Content type, checked against the SDK interface:** `RadioContent` carries only
`stationName`, `programName`, `genre`, `artwork`, `isExplicit` and `duration`. It has no
song, artist or album field, so it cannot show what KEXP is playing; it would describe
the station, not the track. `MusicContent` has `songTitle`, `artistName`, `albumName`,
`composer`, `isrc`, plus the shared `genre` / `artwork` / `duration`, and accepts
`duration: .live`. `GenericContent` (title / subtitle) is the lossy fallback. Decision:
**`MusicContent` with `.live`.** The earlier draft of this section proposed `RadioContent`;
that was wrong.

Still to verify on a device: how the system renders a `.live` `MusicContent` (does it show
a scrubber or a Live badge), and the observation rules for `@Observable` conformers.

### 5. MCP Schema

N/A — application code, not a public API for AI tools.

### 6. Constraints & Compliance

- **Concurrency:** all `MediaSessionRepresentable` members are `@MainActor`; the
  closures in `MediaCommand` are `async throws` and hop to the main actor.
- **Imports:** the interface uses `InternalImportsByDefault` and `MemberImportVisibility`;
  an explicit `import NowPlaying` is needed in each file that touches the types.
- **Safety:** no `try!`; `requestToBecomeApplicationPrimary()` errors
  (`MediaSessionError`) are logged and fall back to the legacy publisher for that session.
- **Single-writer rule:** once the modern publisher is active, the legacy publisher is never
  instantiated, and `AVPlayerViewController.updatesNowPlayingInfoCenter` is set to `false`.

### 7. Source & API Compatibility

**Breaking changes:** none to the `KEXPPower` framework API. New targets are additive.
**Incremental adoption:** yes — iOS branch first, then macOS and visionOS, each behind its own
target and commit.
**Type-checking risk:** none.
**Deployment targets:** unchanged for existing iOS; new targets pick their own minimums, with
the legacy path covering anything below 27.

### 8. Backend Abstraction

N/A — not compute-intensive.

### 9. Resource Budget

**Data read:** one artwork image per track (same as Proposal 1); an `Artwork` provider
may be asked for several sizes, so requests go through the shared `ArtworkLoader` cache.
**Held vs streamed:** no new retained data; the `MediaSession` holds the representable only.
**Growth:** none with listening time.
**Budget:** unchanged — 4 MB peak, 2 MB at rest for artwork. Per-target binary size
measured and recorded, not budgeted.
**Measured by:** the same cache-bound test as Proposal 1, run against the modern provider.
**Lifetime:** long-running; the `MediaSession` is created once per playback session and
released on stop (per the framework's release-to-remove semantics).

### 10. Dependencies

**Internal:** Proposal 1's protocol, `ArtworkLoader`, `AudioSessionCoordinator`; `KEXPPower`.
**External:** Apple `NowPlaying.framework` (system); no packages.
**Toolchain:** Xcode with the 27.2 SDKs (present locally); `NowPlaying` is
`-language-mode 6`, so Swift 6 mode (Proposal 1, Open Question 3) is a prerequisite.

### 11. Test Strategy

**Test Categories:**
- Golden path: player state → `content` / `playbackSnapshot` / `commands` mapping (pure, testable
  without a system session).
- Edge: no current track, unknown show, artwork failure, command invoked while stopped.
- Gating: factory returns legacy on a simulated pre-27 runtime and modern on 27+; on 27 the
  legacy publisher is never constructed (single-writer rule).
- Platform: each new target builds and launches; playback starts on a device or simulator.

**Reference Truth:** the SDK `.swiftinterface` signatures quoted above for compile-time
shape; behavior on the lock screen, Control Center, and the macOS / visionOS Now Playing UI
confirmed by hand on devices. Behavioral claims from the third-party article are not used
as test oracles.

**Validation Trace (REQUIRED):**
- Input: station "KEXP 90.3 FM", state `.playing`, no elapsed time.
- Expected: `playbackSnapshot?.state == .playing(rate: 1.0)`, `content` is a `MusicContent` with
  `duration == .live`, `commands` contains play and pause.
- Spec-derived; independent confirmation is the on-device check.

### 12. Architecture Decision Review

- [ ] Review `project/decisions/` (the ADR from Proposal 1 is a dependency)
- Amends Proposal 1's ADR? **Yes** — "single publisher" now has two conformers behind a factory.
- New ADR required? **Yes**

**New ADR Draft:** *Gate the NowPlaying framework with availability, not a deployment bump.*
Category: api. Key decision: support pre-27 systems via the legacy publisher until the
minimum OS is raised deliberately.

### 13. Adversarial Review

**Strongest case for a different approach:** raise the minimum to OS 27 across all targets,
delete the legacy publisher and the factory, and ship one code path. Half the code, no
branch to test, no risk of the two paths diverging.

**Where this design is most likely wrong:** it assumes we can verify the modern path
without the final OS. The SDK is 27.2 but device behavior (lock screen, Control Center
rendering, how a live `MusicContent` displays) has not been observed by us. How a live `MusicContent` renders (scrubber vs Live badge) may look wrong in the UI.

**What an experienced critic would say:** "You're building a second code path and three new
platform targets to adopt an API you haven't seen run." We proceed in phases: iOS first,
with an on-device checkpoint before adding macOS, and we abandon the platform
target if the checkpoint shows the mapping needs rework.

### 14. Alternatives Considered

**Alternative 1: Bump to 27 and drop legacy.** Simplest; excludes every user not on 27.
Rejected for now; revisit when adoption justifies it.

**Alternative 2: Mac Catalyst / iPad-on-Mac instead of a native macOS target.** Cheaper, but
you asked for native, and `SUPPORTS_MACCATALYST` is currently NO.

**Alternative 3: Separate repos per platform.** Rejected: the shared playback layer is the
point.

### 15. Future Directions

- **watchOS streaming app — feasible.** `NowPlaying` is available on watchOS 27, KEXP's
  streams are plain AAC over HTTPS, and `AVPlayer` can stream on watchOS. A watch app could
  stream independently over Wi-Fi or cellular without the phone. Constraints to confirm
  before committing to a proposal: audio route policy (watchOS typically requires routing
  long-form audio to Bluetooth headphones; whether built-in speaker playback is acceptable
  on current watchOS needs to be checked), the `audio` background mode, and battery cost of
  a continuous 64 kbps stream (the app already has a 64 kbps option in `AvailableStreams`).
  I have not verified these on a device. Could be its own proposal.
- Could adopt `RemoteMediaSession` on iOS to represent playback on an external speaker.
- Could add `requestToBecomeSystemPrimary()` on iOS for a foreground "take over" action.
- Could add visionOS as a fifth target; it needs no extra framework work.

### 16. Open Questions

1. ~~watchOS proposal?~~ Out of scope per master plan (2026-11-02). Feasibility notes in section 15 are kept for the record.
2. ~~`RadioContent` or `MusicContent`?~~ Resolved: `MusicContent` (see section 4).
3. Does the macOS app need the full song list and Apple Music search UI, or just
   a player? Recommendation: player plus current track first.
4. Minimum version for the new macOS target, assuming the legacy fallback.

### 17. Documentation Strategy

**Documentation Type:** inline DocC on the publishers and factory; `README.md` gains a
platform matrix (iOS, macOS, visionOS; CarPlay later).
**Also updated:** `CHANGELOG.md`, `project/master_plan.md` status and roadmap,
session summary.
