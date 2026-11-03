# Design Proposal: Adopt the Official KEXP/KEXPPower Package (4.1.0)

**Status:** WITHDRAWN 2026-11-02 — owner chose to keep the fork. Kept for the record; see `project/decisions/ADR-001-keep-the-fork.md`.
**Why withdrawn:** the fork is more modern (async/await, no completion handlers); the package powers KEXP's official app, so upstream PRs (Sendable, UIKit guards, async) would burden those maintainers; adopting upstream as-is would force iOS 26 and lose macOS.
**Date:** 2026-11-02
**Supersedes:** `KEXPPowerPackage.md` (a new separate repo). The official package already exists, so that proposal is withdrawn.
**Sequence:** Independent of Proposal 1 except for the iOS 26 deployment bump, which this proposal forces and Proposal 1 records.

---

### 1. Objective

Replace this repo's divergent fork of the KEXPPower library (framework target, podspec) with the official Swift package `https://github.com/KEXP/KEXPPower`, pinned at `4.1.0`, and move the fork-only behavior the app relies on into the app.

**Master Plan Reference:** Roadmap Phase 1; Core Architectural Decision 4.

### 2. Motivation

**Verified 2026-11-02 against the upstream repo (read via the GitHub API, not cloned):**
- `main` is exactly tag `4.1.0` (0 commits ahead or behind); latest commit 2026-05-25 ("Add program image support and align archive lookback to 14 days"). Tags run `3.0.0` … `4.0.0`, `4.0.1`, `4.1.0`.
- `Package.swift`: `swift-tools-version: 6.0`, `platforms: [.iOS("26.0")]`, `swiftLanguageModes: [.v5]`, no dependencies, test resources under `KEXPPowerTests/Samples`.
- Same layout as this fork (Archive, Models, Networking, Public API, Helpers) and 18 of 22 source files within a few lines of the fork after ignoring whitespace; the fork's `PlayResult.swift` and `NetworkManager.swift` are far from upstream.

**What the fork has that upstream does not** (from signatures and a whitespace-insensitive diff):

| # | Fork-only behavior | Upstream today | Plan |
|---|--------------------|----------------|------|
| U1 | `async throws` API on `NetworkManager` | completion handlers with a `queue:` argument | App-side adapter (below) |
| U2 | `Play` is a `class`, `ObservableObject`, `Hashable`, `Identifiable`; `PlayResult` has a `UUID` id and defaults `plays` to a fixture | `Play` and `PlayResult` are `Decodable` structs | App-side view model mapped from upstream `Play` |
| U3 | `Play.fixture()` and friends in the library | none in the library | Move to the app's test/preview support |
| U4 | `getAppleMusicLink(artist:track:album:)` | `getAppleMusicLink(artist:track:)` | Open Question 2 |
| U5 | `KEXPPower` is `@MainActor` with a public `init` and `fixture(...)` | private init, singleton | Use the singleton; app wraps config |
| U6 | `import SwiftUI` / `Combine` in the library models | none | Not carried over (an improvement) |
| U7 | `URL(string: "")!` fallback in `getShowURL` | `URL(string:)!` | Not our code once upstream is used |

**What upstream has that the fork lacks:** program image support, the 14-day archive lookback fix (4.1.0), and a real version tag history.

**Constraints that follow from upstream:**
- **iOS 26 minimum.** The package declares `.iOS("26.0")`, so the app's deployment target moves from 17 to 26 (owner agreed). This reverses the earlier "keep iOS 17" decision, which is why Proposal 1 is updated.
- **No macOS today.** Seven source files do an unguarded `import UIKit` (`UIImageView+Loading.swift` among them), and the manifest declares only iOS. A macOS app target cannot link the package until upstream guards those imports. visionOS has UIKit and may build; untested.
- **Swift 5 language mode inside the package.** The app is moving to Swift 6 mode; upstream's public types are not marked `Sendable`, which Swift 6 will flag when they cross actors.
- **Completion handlers:** upstream's `queue: DispatchQueue = .main` default means callbacks arrive on the main queue; the adapter must not assume otherwise.

### 3. Proposed Architecture

**Dependency:** add `https://github.com/KEXP/KEXPPower` as a package dependency, `exact: "4.1.0"` (or `from:`; Open Question 3).

**New app files** (`KEXPPower SwiftUI/Data/`):
- `KEXPClient.swift` — thin `actor` that wraps upstream `NetworkManager` calls in `async throws` using continuations.
- `PlayItem.swift` — `@Observable`, `Hashable`, `Identifiable` view model built from upstream `Play` (replaces the fork's `Play` class for views).
- `PlayItem+Fixtures.swift` — preview and test fixtures (replaces the library fixtures).

**Modified:** `ResultRetriever.swift`, `AppleMusicRetriever.swift`, `PlayResultStore.swift`, and the views that use `Play` (they take `PlayItem`).
**Removed after parity:** the `KEXPPower` framework target, `KEXPPowerTests` target, `KEXPPower/` sources, `KEXPPower.podspec`, and `KEXPPower/Documentation`. Before deleting, tag the current commit `fork-final` so the fork is recoverable.

### 4. API Surface

```swift
actor KEXPClient {
    init(manager: NetworkManager = NetworkManager())

    func plays(airdateBefore: String? = nil, limit: Int = 50, offset: Int = 0) async throws -> [PlayItem]
    func play(id: Int) async throws -> PlayItem
    func shows(startAfter: String? = nil, startBefore: String? = nil, limit: Int = 50) async throws -> [Show]
    func show(id: String) async throws -> Show
    func archiveStreamURL(timestamp: String) async throws -> URL
    func appleMusicLink(artist: String, track: String) async throws -> URL?
}

@Observable final class PlayItem: Identifiable, Hashable { /* mapped from upstream Play */ }
```

Continuation wrappers resume exactly once; the wrapper checks that upstream's `Result` is mapped to a thrown `KEXPClientError` rather than force-unwrapping.

### 5. MCP Schema

N/A — application code.

### 6. Constraints & Compliance

- **Concurrency:** `KEXPClient` is an actor; `PlayItem` is `@MainActor`-bound for UI; values crossing isolation are copied into `Sendable` structs first. Upstream types are imported with `@preconcurrency import KEXPPower` only if a real diagnostic requires it, with a comment naming the upstream gap — never as a blanket suppression.
- **Safety:** no `try!`, no force-unwrap; continuations never leak (every path resumes once).
- **Default page size:** the fork's `getPlay` defaults to `limit: 2000`. The adapter defaults to 50 and callers must ask for more.

### 7. Source & API Compatibility

**Breaking changes:** to the app's internal use of the fork's `Play` class only; views change to `PlayItem`. The fork's API is not preserved.
**Incremental adoption:** yes — add the dependency alongside the framework target? No: both define module `KEXPPower`, so they cannot coexist in one target graph. Adoption is therefore one cutover branch, kept small by the adapter.
**Type-checking risk:** none.

### 8. Backend Abstraction

N/A.

### 9. Resource Budget

**Data read:** `/v2/plays` pages (a play is roughly 1 KB of JSON; observed 2026-11-02) and `/v2/shows` (68,065 shows today, growing by about 8–10 a day, never fetched unbounded).
**Held vs streamed:** the live playlist holds the most recent pages the user has scrolled, not history. The adapter itself holds nothing.
**Growth:** memory follows pages loaded, not archive size.
**Budget:** 5 MB peak per request (a page of 200 plays); the playlist view caps retained plays at 500 (about 0.5 MB of models plus artwork thumbnails through the shared `ArtworkLoader` cache from Proposal 1).
**Measured by:** a test that feeds 5,000 plays through the playlist store and asserts the retained count never exceeds 500.
**Lifetime:** long-running; scrolling and refreshing for days must not grow the retained set.

### 10. Dependencies

**External:** `KEXP/KEXPPower` 4.1.0 (MIT license; no transitive dependencies).
**Internal:** Proposal 1's `ArtworkLoader`.
**Toolchain:** tools 6.0 manifest builds on the local toolchain; the package compiles in Swift 5 mode.

### 11. Test Strategy

**Test Categories:**
- Golden path: decode upstream's recorded `PlaySample.json` and `ShowSample.json` into `PlayItem` / `Show`.
- Edge: null optional fields, empty `plays`, missing artwork.
- Adapter: success, failure, and "callback arrives once" for every wrapped call.
- Retention: the 500-play cap above.
- Contract: an opt-in live test that fetches `/v2/plays?limit=1` and asserts the response still maps.

**Reference Truth:** upstream's own samples in `KEXPPowerTests/Samples/` plus live responses captured 2026-11-02 (play 3726579, "VHS Sex", show 68216).

**Validation Trace (REQUIRED):**
- Input: live response for `/v2/plays/?limit=1` captured 2026-11-02.
- Expected: `PlayItem.id == 3726579`, `song == "VHS Sex"`, `show == 68216`.

### 12. Architecture Decision Review

- Supersedes an existing ADR? No; **supersedes the withdrawn separate-repo decision** recorded in the master plan (updated).
- **New ADR required? Yes.** *Depend on the official KEXPPower package; keep app-specific models in the app.*

### 13. Adversarial Review

**Strongest case for a different approach:** keep the fork. It already works, it is async, and the app's views are written against it. Switching spends effort to get back to where the app already is, in exchange for tracking upstream.

**Where this design is most likely wrong:** it assumes upstream stays maintained and that the continuation adapter is thin. If upstream's `NetworkManager` has threading or error behavior the adapter cannot paper over (it calls back on a queue the adapter cannot control), the adapter grows into a second networking layer.

**What an experienced critic would say:** "You are rebuilding the async layer you already have, on top of someone else's callbacks." We proceed because the official package is the supported surface, the owner asked for it, and the alternative is a fork that drifts further each upstream release. If the adapter is not under about 150 lines, we stop and propose contributing the async API upstream instead.

### 14. Alternatives Considered

**Alternative 1: Keep the fork and rebase it onto upstream 4.1.0.** Preserves async and class models; permanent merge work. Rejected as the default, kept as the fallback.
**Alternative 2: Contribute the async API, `Sendable` conformances, and UIKit guards upstream, then consume the tag.** Cleanest end state; needs the maintainers' agreement and is outward-facing. Pursued only on the owner's say-so (Open Question 1).
**Alternative 3: Local path dependency on a vendored copy.** Avoids the network but recreates the fork.

### 15. Future Directions

- Could contribute upstream: `Sendable` conformances, `#if canImport(UIKit)` guards (unlocks macOS), `async` overloads.
- Could add `macOS` and `visionOS` to the manifest's `platforms` once guards land.
- Could wrap upstream's archive APIs for the Archive Playback milestone (note the 2026-11-02 probe: `/get_show_start/` needs a `stream_time`).

### 16. Open Questions

1. Are you willing to open pull requests to `KEXP/KEXPPower` (Sendable, UIKit guards, async overloads)? It is outward-facing and would also unlock macOS. I will not open any without your explicit go-ahead.
2. `album:` for Apple Music search: upstream lacks it. Do the search in the app (MusicKit or the iTunes Search API directly), or request it upstream?
3. Pin `exact: "4.1.0"` or `from: "4.1.0"`? Recommendation: `from:` once tests cover the adapter.
4. Until the macOS guards land upstream, should the macOS target wait, or use a thin local fork of just the networking and model files for that platform only?

### 17. Documentation Strategy

**Documentation Type:** inline DocC on `KEXPClient` and `PlayItem`; README gets a "Dependencies" section naming the upstream package and version.
**Also updated:** CHANGELOG, master plan, ADR, session summary.
