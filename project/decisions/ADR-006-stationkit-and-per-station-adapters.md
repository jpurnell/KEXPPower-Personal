# ADR-006: StationKit, per-station adapter packages, separate app targets

**Date:** 2026-11-03
**Category:** architecture
**Status:** Accepted. Phase 0 under way.

## Decision
- **Station-agnostic code lives in `StationKit`** (its own private repo, MIT). It defines `Station`, `Track` (with
  credits), `NowPlaying`, `StreamOption` and everything that works from them. It never imports a station's API.
- **Each station is an adapter package** named `StationKitAdapter<STATION>` (no hyphen, so repo, package and module
  names match), over that station's own API client. First: `StationKitAdapterKEXP` over `KEXPPowerKit`.
- **Separate app targets per platform** (iOS, visionOS, macOS) sharing **one bundle ID** (`com.JPEnterprises.Spinner`,
  universal purchase). tvOS and watchOS are kept ready: StationKit compiles for all five platforms.
- **A further `StreamingRadioKit` layer is not created.** The `Station` protocol is that layer. Revisit if a second
  adapter contains code copied from the first.
- Repos stay private until something works end to end.

## Context
See `project/plans/upcoming/PlatformExperience.md`, including the evidence gathered from KEXP, WFUV, All Classical
Portland, WBUR, WPRB (Spinitron), WHUR, WXYC, Streema, Spinitron's API and TuneIn. In short: stations describe
music differently (pop vs classical), "now playing" is not always a song, APIs differ in shape, some require
per-station keys that must never ship in a client, and the most common denominator is a stream URL.

## Consequences
- The app depends on StationKit and `StationKitAdapterKEXP` by tagged URL, as it does `KEXPPowerKit`.
- Moving the player glue (Now Playing, audio session, artwork) out of the app and into StationKit is the next step.
- Key-based stations (Spinitron) need a per-station relay that emits StationKit Now Playing JSON; keys never go in
  a client or a public registry.
