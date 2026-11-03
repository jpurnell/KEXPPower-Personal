# ADR-001: Keep the in-repo fork of KEXPPower

**Date:** 2026-11-02
**Category:** architecture
**Status:** Accepted
**Supersedes:** the earlier "separate package repo" plan (never implemented) and the withdrawn `UpstreamPackageAdoption` proposal (`plans/archive/`).

## Decision
The app keeps using its own fork of KEXPPower as an in-repo framework target. We do not depend on `KEXP/KEXPPower` and do not submit pull requests to it.

## Context
Upstream `KEXP/KEXPPower` 4.1.0 (verified 2026-11-02) is a Swift package (`.iOS("26.0")` only, Swift 5 mode, completion-handler API, unguarded `import UIKit` in 7 files). The fork is async/await, and the app's views are written against it. The package powers KEXP's official app, so contributions there create review work for its maintainers.

## Consequences
- **Deployment target stays at iOS 17.** The iOS 26 minimum was only needed for upstream; the earlier decision to keep 17 stands.
- The fork is ours to maintain, including macOS support (the fork has no UIKit-only code on the model/networking path to guard beyond `UIImageView+Loading.swift`, to be confirmed when the macOS target is built).
- We hand-port worthwhile upstream changes. As of 2026-11-02 two are missing from the fork: `Show.programImageURI` / `programImageURL`, and the archive lookback of 14 days (fork uses 13).
- The fork's `ArchiveManager` async conversion is commented out (`//TODO: - ASYNC`); upstream's works. Archive Playback is a Phase 2 priority, so finishing it is owed work, not a regression we can ignore.
- Revisit if upstream gains async, Sendable, and multi-platform support, or if the fork's drift becomes costly.
