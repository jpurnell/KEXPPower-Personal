# ADR-002: The library lives in its own repository (KEXPPowerKit)

**Date:** 2026-11-02
**Category:** architecture
**Status:** Accepted. Extraction done and the app builds against it (local path dependency); the app-side changes are not yet committed.
**Amends:** ADR-001 (the fork is kept, but outside this repo).

## Decision
The KEXPPower fork was extracted, with its git history, into `jpurnell/KEXPPowerKit` (private GitHub repo,
sibling directory `../KEXPPowerKit`). The module is still named `KEXPPower`. This app repo will consume it as a
package dependency and delete its in-repo framework target.

## State at extraction
- Swift 6 language mode, tools 6.2; iOS 17, macOS 14, visionOS 1.
- 34 Swift Testing tests; the quality gate passes 47 of 49 checkers. `doc-coverage` and `doc-lint` are excluded
  by owner decision until the public API is documented.
- Ported from upstream 4.1.0: `Show.programImageURI`; archive lookback aligned to 14 days.
- UIKit removed from the library (`UIImageView+Loading.swift` had no callers).
- Archive loading remains disabled and is deferred to the iOS 27.2 follow-up.

## Done in this repo (uncommitted)
- Package dependency added; framework, tests, UIKit example, podspec, dead UI test targets deleted; `import KEXPPower` added to 10 app files; `BUILD_LIBRARY_FOR_DISTRIBUTION` turned off for the app; stale `origin` removed.

## Still to do in this repo (original list, for the record)
- Add the package dependency; delete the `KEXPPower` and `KEXPPowerTests` targets, `KEXPPower/`, `KEXPPowerTests/`,
  `KEXPPower.podspec`, the UIKit `KEXPPowerExample` target, and the dead UI test targets.
- Remove the stale `origin` remote (it points at the official KEXP/KEXPPower repository).
- App unit-test target, then Proposal 1 (playback hardening), test first.

## Consequences
Library changes are now two-repo changes while the app is the only consumer; a local path dependency keeps that cheap.
