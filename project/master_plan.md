# KEXPPower Master Plan

**Purpose:** Source of truth for project vision, architecture, and goals.

---

## Project Overview

### Mission
A fast, friendly, native Apple-platform listener for KEXP 90.3 FM (Seattle): a live
playlist, the live stream, and the tools to keep the music you hear. It is intended to be
quicker and more pleasant to use than the existing KEXP app.

### Target Users
- KEXP listeners on iPhone, iPad, Mac, and Apple Vision Pro (and in the car via CarPlay)
  who want to see what is playing now, hear it, and save it.
- Distribution: personal and open source, but built and reviewed to public-release
  standard. Privacy and KEXP branding are treated as approved.

### Key Differentiators
- Live playlist and now-playing as the primary screen, not a station brochure.
- One-tap save to a dedicated Apple Music playlist, and jump to the song in Apple Music.
- Archive playback from an arbitrary point in time.
- Native on every Apple platform it targets, sharing one playback layer.

---

## Architecture

### Technology Stack
- **Language:** Swift 6.x, strict concurrency, Swift 6 language mode
- **UI:** SwiftUI
- **Build System:** Xcode project (app); the library is the `jpurnell/KEXPPowerKit` package (a fork of KEXPPower), pinned `from: 4.0.1`, with `StationKit` (0.3.0) and `StationKitAdapterKEXP` (0.2.0); see ADR-001/002
- **Testing:** Swift Testing for new tests; the existing XCTest suite stays until migrated
- **Concurrency:** Swift 6 strict concurrency throughout
- **Platforms:** iOS (primary, deployment target 17), macOS (own target, `Spinner Mac`), visionOS (shares the iOS target), watchOS (`Spinner Watch`, embedded in the iOS app), CarPlay later. tvOS is kept *ready* (the generic `StationKit` package compiles for it) but not built.
- **System integration:** `MediaPlayer` (`MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`) today; the iOS 27 `NowPlaying` framework behind `#available` later.
- **Dependencies:** none external. KEXP public API (`api.kexp.org/v2`), StreamGuys streams, Apple Music (MusicKit / links).

### Module Structure

```
KEXPPower/                    Forked library sources (kept; ADR-001)
├── Models/KEXP/              Play, Show decoding
├── Models/AppleMusic/        Apple Music search result
├── Networking/               NetworkManager, Router, Reachability
├── Public API/               KEXPPower config, AvailableStreams
├── Helpers/                  Formatters, image loading
└── Archive/                  ArchiveManager and archive models
KEXPPower SwiftUI/            The app (shared SwiftUI target)
├── Audio Player/             PlayerController, notification/Now Playing layer
├── Retrievers/               ResultRetriever (play/show fetching)
├── Song List/                Live playlist views
└── Show Information/         Show views
KEXPPowerTests/               Library tests
project/                      Plans, proposals, decisions, summaries
```

### Key Types

| Type | Purpose |
|------|---------|
| `KEXPPower` | Configuration singleton: base URL, bitrate, stream URL |
| `NetworkManager` | KEXP API requests (plays, shows) |
| `PlayResult`, `ShowResult` | Decoded API models |
| `PlayerController` | Owns `AVPlayer`; drives playback state |
| `NowPlayingPublishing` (Proposal 1) | Single seam to the system Now Playing state |
| `ArtworkLoader` (Proposal 1) | Bounded, cancellable artwork fetch |

### Data Flow

```
api.kexp.org/v2/plays ──> NetworkManager ──> ResultRetriever ──> SwiftUI views
                                                   │
streamguys1 AAC stream ──> AVPlayer (PlayerController) ──> NowPlayingPublishing ──> lock screen / Control Center / CarPlay
```

---

## Core Architectural Decisions

1. **One writer to system Now Playing state.** Playback code never touches `MP*` directly; a publisher does. This is what lets the iOS 27 framework replace it without a rewrite.
2. **Availability-gated adoption.** The minimum stays iOS 17. iOS 27 features are added behind `#available`; the legacy Now Playing path remains the implementation below 27.
3. **`MusicContent` (not `RadioContent`) for the modern API.** The station-oriented type has no song, artist, or album field.
4. **Keep the in-repo fork of KEXPPower** (ADR-001). It is async/await and more modern than upstream 4.1.0; we hand-port upstream changes we want and do not send PRs to the package that powers KEXP's official app.
5. **Public-release bar.** Zero-warning quality gate, no force-unwraps or `try!` in shipping code.

---

## Current Status

### What's Working
- [x] Live KEXP playlist retrieval (`/v2/plays`, `/v2/shows` verified live 2026-11-02)
- [x] Live stream playback (64 and 160 kbps AAC)
- [x] Lock-screen / Control Center Now Playing (with known defects, see Proposal 1)
- [x] Apple Music search link (partial)
- [x] macOS: plays the stream, Playback menu (Space), media keys and Now Playing; layout lines up (the show header, the rows and the scroll bars) and every Previously row is clickable (3.2.0)
- [x] watchOS: standalone app with background audio, album art, Digital Crown volume, a connection state (3.2.0)
- [x] The app owns one player and playlist, shared by every window and the menus (3.2.0)
- [x] Now Playing widget, small / medium / large, on iPhone, iPad, Mac and Vision Pro; play/pause from the widget, published within milliseconds of a player change (3.3.0)
- [x] Add to Apple Music playlist (iPhone, iPad, Vision Pro), Mac sidebar shell and translucent mini player (3.3.0)

### Known Problems
- ~~`try!` crash on artwork fetch; artwork never reaches the system (Proposal 1, G1–G3)~~ fixed (`ArtworkLoader` in StationKit)
- ~~Five independent writers to Now Playing state; `isPlaying` can drift (G4–G7)~~ fixed (one publisher; `isPlaying` mirrors `timeControlStatus`). It shipped without a view-level check: the iOS button did not follow `isPlaying` until `PlayerController` was made `@Observable` (see the changelog), and a `PlayerControllerTests` test now covers that path
- ~~The Mac UI is a port of the iPhone layout: no sidebar yet, and a row is no longer a keyboard-focusable button (a VoiceOver action stands in)~~ the sidebar shipped in 3.3.0; rows take keyboard focus again (Tab, Return), checked by a UI test; the Mac has no add-to-playlist (MusicKit), so it has an Open in Music button
- The watch needs 35–40 s on a cold network to reach the stream; the app shows "Connecting…" meanwhile
- Library fork vs upstream 4.1.0: missing `Show.programImageURI` and the 14-day archive lookback (fork uses 13); `ArchiveManager`'s async conversion is commented out (`//TODO: - ASYNC`), so archive loading does not work in the fork today
- Library endpoints: `get_streaming_url` now redirects and `get_show_start` requires a timestamp, so those are suspect
- Library models import SwiftUI/Combine and `Play` is a class; acceptable for now, but a portability cost for macOS
- ~~Project still in Swift 5 language mode~~ now Swift 6 with strict concurrency on every target

### What's Next
- [x] Playback hardening: `project/plans/completed/PlaybackHardening.md` (complete: interruption/route handling, session coordinator, Swift 6, ADR-003)
- [x] Library extracted to `jpurnell/KEXPPowerKit` (ADR-002): Swift 6, `programImageURI`, 14-day lookback, UIKit removed, 34 tests
- [x] App switched to the package (`jpurnell/KEXPPowerKit` 4.0.0, by URL; verified running on a physical iPhone); in-repo framework, podspec, UIKit example target, dead UI test targets removed; stale `origin` dropped (2026-11-02). Committed in 53f58e6.
- [x] Library: `Play.playType` decoding fixed, placeholder defaults removed, `Sendable` structs (no app `PlayItem` needed: the app only uses `Play` as a value), KEXPPowerKit `f1c7fc0`
- [ ] Finish async `ArchiveManager` (iOS 27.2 follow-up)
- [x] Phase 0 (in progress): `StationKit` 0.3.0 (core types, `MusicLinks`, player glue; 46 tests; builds for iOS/macOS/visionOS/tvOS/watchOS) and `StationKitAdapterKEXP` 0.2.0 (KEXP as a Station; 9 offline + 2 live tests; all five platforms), both private. The iOS app now consumes both (14 app tests; running on Brawn 2026-11-03). A first standalone watchOS app (`Spinner Watch`) runs on a physical watch. Next: adapt the retrievers fully to `Station`, ~~split iOS/visionOS/macOS targets~~ (macOS split out 2026-11-04 as `Spinner Mac`; visionOS still shares the iOS target), ~~embed the watch app in the iOS app~~ (done, iOS-only).
- [x] Add to Apple Music playlist on iPhone, iPad and Vision Pro (song matching by ISRC, default KEXP playlist, long-press for another or a new one; built 2026-11-04, awaiting a real-device test). **Not possible on macOS**: MusicKit's library writes are unavailable there; the Mac's options are listed in the plan.
- [x] Widget built and released in 3.3.0 (2026-11-05): `Spinner Widget` extension, three sizes, shared views, `WidgetPublisher`, play/pause intent; layouts rendered and tested, signed for iPhone and Mac; working on Brawn; not yet checked on the Mac desktop.
- [ ] Next, in order (agreed 2026-11-04): ~~app-level player and Playback menu~~ (done), ~~a Mac mini-player window (now-playing only)~~ (done, translucent), ~~the sidebar shell (`NavigationSplitView`, showable and hideable)~~ (done; Archive and Playlists are placeholders), ~~then the widget~~ (done; proposal `project/plans/proposals/NowPlayingWidget.md`, approved 2026-11-04; shipped in 3.3.0). Agreed 2026-11-05, in order: Mac clean-up, then a watch widget, then a Control Center play/pause control
- [ ] Navigation shell, ~~Mac playback~~, Mac layout, Apple Music playlists, widget + App Intents, archive UI: `project/plans/upcoming/PlatformExperience.md` (proposed; revised 2026-11-03: separate iOS/visionOS/macOS targets, generic `StationKit` repo + `StationKitAdapterKEXP` adapter repo, ISRC-based song matching)
- [ ] iOS 27 `NowPlaying` adoption: `project/plans/proposals/NowPlayingFramework.md` (on hold)

---

## Quality Standards

### Code Quality
- All code follows `coding_rules.md`
- TDD: failing tests before implementation
- Documentation for all public APIs
- No warnings in build output
- Quality gate: 0 errors, 0 warnings before every commit

### Documentation Quality
- DocC comments for all public functions
- Usage examples in documentation
- Articles for complex topics

---

## Collaboration Principles

### AI as Sparring Partner, Not Oracle

AI proposes; the human interrogates. High AI confidence triggers harder questions, not faster acceptance.

- **Interrogate confident outputs.** When the AI states something with certainty, ask for the counterargument before accepting.
- **Demand counterarguments.** Before locking in an approach, require an explicit case for the strongest alternative.
- **Sit with discomfort.** Resist the pull to take the first plausible answer.

This principle is operationalized in the **Adversarial Review** step of `design_proposal.md`.

---

## Roadmap

### Phase 1: Solid foundation on current OS (now)
- [ ] Playback hardening and Swift 6 (iOS 17+)
- [ ] Fork upkeep (ADR-001): program image field, 14-day lookback, Swift 6 mode for the framework

### Phase 2: The features this app exists for
- [x] Spotify and Bandcamp search links; tappable links in DJ comments (`MusicLinks`)
- [ ] Apple Music: add to a dedicated KEXP playlist; open the song in Apple Music (finish)
- [ ] Archive playback from an arbitrary point (needs the async `ArchiveManager` finished)
- [ ] Other links: Spotify, Bandcamp, links parsed from DJ comments

### Phase 3: Platforms
- [ ] iOS 27 `NowPlaying` adoption behind `#available`
- [ ] Native macOS target (fork's UIKit-only helper needs a guard)
- [ ] visionOS polish
- [ ] CarPlay Audio: Apple approved the entitlement 2026-11-05 (eligibility confirmed); proposal `project/plans/proposals/CarPlayAudio.md` revised 2026-11-05 (add to playlist in the car, show and host on the root screen, an Archive tab) awaiting the portal step; the Archive tab depends on `ArchiveBrowser.md`
- [x] Watch widget built 2026-11-05 (`project/plans/proposals/WatchWidget.md`; StationKit 0.7.0 `WidgetFeed`; same App Group as the phone, auto-registered); awaiting a check on a watch
- [ ] Archive browser by Date / Host / Show, like kexp.org/archive, on every platform and in CarPlay: `project/plans/proposals/ArchiveBrowser.md` (proposed 2026-11-05; replaces the "Finish async `ArchiveManager`" item as the route)
- [x] Control Center play/pause control built 2026-11-05 (`project/plans/proposals/ControlCenterControl.md`; iOS 18 and macOS 26; visionOS cannot get controls in this SDK); awaiting a check in Control Center on a device

### Future
- Track history by song and by DJ ("what usually follows this song")
- Spotify add-to-playlist
- tvOS and watchOS targets: kept ready by the generic package (compile-checked from day one); not built or shipped yet.

---

**Last Updated:** 2026-11-05 (proposals added for the watch widget, Control Center control and CarPlay Audio; Mac clean-up: keyboard access, Open in Music, UI test target; 3.3.0: reconciled widget, playlist, mini player and sidebar from proposed to shipped; next-up order recorded; earlier: 3.2.0: reconciled status with shipped code — Mac playback, watch app, app-owned player, fixed problems struck through; macOS target split out; filled from template by interview; evaluated upstream KEXP/KEXPPower 4.1.0 and decided to keep the fork, ADR-001; deployment target stays iOS 17)
