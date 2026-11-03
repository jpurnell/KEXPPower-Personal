# Design Proposal: Extract the KEXPPower Fork into Its Own Repository

**Status:** Extraction COMPLETE 2026-11-02 (see ADR-002). App-side cutover still open.
**Date:** 2026-11-02
**Amends:** ADR-001 (keeps the fork, but as its own repo rather than an in-app framework target).

---

### 1. Objective

Move the library out of this app repo into a clean, separately managed Swift package repository (a sibling directory), with the 4.1.0 upstream features the owner wants ported, UIKit removed, Swift 6 enabled, and a real unit-test target developed test-first. The app then consumes it as a package dependency.

**Master Plan Reference:** Roadmap Phase 1.

### 2. Motivation

**Current situation (verified in this clone):**
- The library is an Xcode framework target plus podspec inside the app repo, alongside a legacy UIKit example app (`KEXPPowerExample`: `AppDelegate`, `ViewController`, storyboard), dead `Tests iOS` / `Tests macOS` targets, and the app itself.
- `git remote -v`: `origin` is `https://github.com/KEXP/KEXPPower` (the **official** repo) and `origin1` is `git@github.com:jpurnell/KEXPPower-Personal.git`. A stray `git push origin` from this clone would target KEXP's repository.
- 112 commits touch `KEXPPower/` or `KEXPPowerTests/`, back to 2019, mostly by the original KEXP authors.
- The library's only UIKit code is `Helpers/UIImageView+Loading.swift`; `fromURLSting` has **no callers** anywhere in the repo.
- The fork lacks `Show.programImageURI` and uses a 13-day archive lookback; upstream 4.1.0 has the former and uses 14.
- The fork's `ArchiveManager` async conversion is commented out; the owner has deferred archive loading to the iOS 27.2 follow-up.

**Workaround today:** none; everything lives in one repo and one Xcode project.
**Drawback:** the library cannot be versioned, tested, or released on its own, and the shared repo invites mistakes (pushing to the wrong remote, 8 modified files mixed with scaffolding).

### 3. Proposed Architecture

**New repository** at `../<NAME>/` (Open Question 1), created by history-preserving extraction (Open Question 2):

```
Package.swift              swift-tools-version 6.0, Swift 6 language mode
Sources/KEXPPower/         ← KEXPPower/ (Archive, Helpers, Models, Networking, Public API)
Tests/KEXPPowerTests/      ← KEXPPowerTests/ + Samples/ as bundle resources
LICENSE                    MIT, original KEXP copyright retained
README.md, CHANGELOG.md
CLAUDE.md, .claude/, project/, .quality-gate.yml, .githooks/   (guidelines scaffold)
```

**Platforms:** iOS 17, macOS 14, visionOS 1. No tvOS or watchOS.

**Removed from the library:**
- `UIImageView+Loading.swift` — dead code; the app's `AsyncImage` / `ArtworkLoader` cover image loading in SwiftUI. This is the whole UIKit migration for the library.
- `KEXPPower.h`, `Info.plist`, the podspec, and `Documentation/Publishing KEXPPower` (CocoaPods-era).

**Ported:** `Show.programImageURI` / `programImageURL` (matches upstream 4.1.0 names and JSON key `program_image_uri`); archive lookback 14 days, via a single named constant instead of two literal `-13`s.

**Not touched:** archive *loading* (the commented-out `ArchiveManager` flow) — deferred to the iOS 27.2 follow-up. The lookback constant is still aligned now.

**App-side (this repo) after the library is ready:**
- Add the package as a dependency (local path while developing, then URL with a version).
- Delete the `KEXPPower` and `KEXPPowerTests` targets, `KEXPPower/`, `KEXPPowerTests/`, `KEXPPower.podspec`, the UIKit `KEXPPowerExample` target and folder, and the dead UI test targets.
- Migrate `updateNotificationView.swift` off `import UIKit` where a SwiftUI/Foundation alternative exists (artwork stays `UIImage`-based on iOS until Proposal 1's `ArtworkLoader` lands; macOS needs `NSImage`).

### 4. API Surface

```swift
// Show additions (Models/KEXP/ShowResult.swift)
public struct Show {
    public let programImageURI: String?
    public var programImageURL: URL? { programImageURI.flatMap(URL.init(string:)) }
}

// Archive (single source of truth for the window)
extension ArchiveManager {
    static let archiveLookbackDays = 14
}
```

**Swift 6 consequence (corrected 2026-11-02):** an earlier draft claimed Swift 6 mode would reject the fork's non-`Sendable` `Play` class. That was wrong for the library: it type-checks cleanly in Swift 6 (verified with `swiftc -typecheck -swift-version 6`; Foundation's formatters are `Sendable` and `Play` never crosses an isolation boundary inside the package). Swift 6 mode is enabled in the package. The `Play` class still matters for **consumers**, where it crosses actors, and it has real bugs found while writing characterization tests: `playType` is a `let` with a default so Codable never decodes it (every airbreak reports `.trackplay`), missing fields get invented placeholders (`artist` = "Artist", `labels` = ["label 1"]), `airtime` force-unwraps `airdate`, and `PlayResult.plays` defaults to a fixture. Converting to a `Sendable` struct with an app-side `PlayItem` therefore remains the recommendation, now justified by correctness and consumer isolation rather than by the library compile.

### 5. MCP Schema

N/A — a client library for an HTTP API, not a tool surface for AI models.

### 6. Constraints & Compliance

- **Concurrency:** Swift 6 mode; models `Sendable`; `KEXPPower` configuration keeps its `@MainActor` isolation or becomes an actor.
- **Safety:** remove `URL(string: "")!` (it traps) by throwing or returning optional; no `try!`; no implicitly unwrapped `selectedBitRate`.
- **Licensing:** MIT license and copyright notices preserved; history preserved so attribution to the original authors survives.
- **Remotes:** the new repo has exactly one remote, named `origin`, pointing at a repo the owner controls.
- **Quality gate:** 0 errors / 0 warnings in the new repo.

### 7. Source & API Compatibility

**Breaking changes:** removal of `UIImageView.fromURL` / `fromURLSting` (no callers); possibly `Play` becoming a struct (Open Question 3). Adding `programImageURI` to `Show` is additive, but the custom `init(from:)` must decode it with `decodeIfPresent`, so older payloads still decode.
**Incremental adoption:** the app switches in one commit once the package builds and passes tests; until then the in-repo framework still builds.
**Type-checking risk:** none.

### 8. Backend Abstraction

N/A.

### 9. Resource Budget

**Data read:** pages from `/v2/plays` and `/v2/shows` (68,065 shows today, growing by roughly 8–10 a day).
**Held vs streamed:** the library holds only what a caller asks for; no cache, no history.
**Growth:** none inside the library; callers choose page sizes.
**Budget:** 0 MB at rest inside the library; 5 MB peak for a 200-play page. The fork's default `getPlay(limit: 2000)` is reduced to 50 so the default call is bounded.
**Measured by:** a test that decodes a 200-play sample and asserts a default call builds `limit=50`.
**Lifetime:** the library is stateless; a long-running app cannot make it grow.

### 10. Dependencies

**Internal:** none. **External:** none (Foundation, OSLog, SystemConfiguration for `Reachability`).
**Tooling:** `git filter-repo` for history-preserving extraction (to verify it is installed; otherwise `git subtree split`).

### 11. Test Strategy (TDD, Swift Testing)

**Process:** Red → Green → Refactor, one commit per green state, in the new repo.
**Order:**
1. Port the six existing XCTest parse tests to Swift Testing against the same `Samples/*.json` (characterization: they must pass before anything changes).
2. **Red:** `Show` decodes `program_image_uri` (sample lacks it → add a fixture including it); a payload without it still decodes with `nil`.
3. **Red:** `ArchiveManager.archiveLookbackDays == 14`, and the start-date computation for a fixed reference date returns date − 14 days (inject the clock/calendar to keep it deterministic).
4. **Red:** default `getPlay` request carries `limit=50` (request-building test through a stub `URLProtocol`).
5. Swift 6 mode: compile clean with strict concurrency.

**Reference Truth:** upstream 4.1.0 field names (`programImageURI`, key `program_image_uri`) and the live API response (the `/v2/shows/?limit=1` response observed 2026-11-02 includes `program_image_uri`).

**Validation Trace (REQUIRED):**
- Input: live show 68216 ("Drive Time"), `program_image_uri` =
  `https://www.kexp.org/media/filer_public/d5/4b/d54bb066-bf8a-413b-beea-4819cb148654/drivetime-800x800.jpg`
- Expected: `show.programImageURL?.absoluteString` equals that string; `show.programImageURI` for a payload without the key is `nil`.
- Lookback: reference date 2026-11-02 → window starts 2026-10-19 (14 days earlier).

### 12. Architecture Decision Review

- Amends ADR-001: **yes** — the fork stays, but in its own repo.
- **New ADR required? Yes (ADR-002).** *The library lives in its own repository.*

### 13. Adversarial Review

**Strongest case for a different approach:** a local Swift package inside the app repo (`Packages/KEXPPower`) gives the same clean structure, tests, and Swift 6 with one repo, one commit history, and no cross-repo coordination. The "messy" part is the leftover legacy and scaffolding, which cleanup alone fixes.

**Where this design is most likely wrong:** it assumes the library will be developed independently of the app. In practice most library changes will be driven by app features, so every feature becomes a two-repo change with version bumps.

**What an experienced critic would say:** "One consumer doesn't justify a repo." We proceed because the owner asked for a separate, cleanly managed repo; a local path dependency during development removes most of the friction, and the repo can be tagged only when the API settles.

### 14. Alternatives Considered

**Alternative 1: Local package in this repo.** Lowest overhead; rejected by the owner's request but kept as the fallback.
**Alternative 2: Push the fork to `jpurnell/KEXPPower-Personal` (existing `origin1`).** Reuses a repo, but mixes the app's history with the library's.
**Alternative 3: Extract without history.** Simplest and loses 112 commits of attribution; rejected unless filter-repo is unavailable.

### 15. Future Directions

- Could finish the async `ArchiveManager` in the iOS 27.2 follow-up.
- Could replace `Reachability` (`SystemConfiguration`) with `NWPathMonitor`.
- Could publish DocC for the package.
- Could contribute selected changes upstream, if the owner ever chooses to (not planned; ADR-001).

### 16. Open Questions

1. Name of the new repo/directory (e.g. `KEXPPower-Swift`)? The module name stays `KEXPPower`.
2. Preserve history (recommended) or start fresh?
3. Convert `Play` / `PlayResult` to `Sendable` structs and add an app-side `PlayItem`, as Swift 6 requires? Recommendation: yes.
4. Create a GitHub remote now (private to start, public later) or keep it local until the first release? Creating a remote is outward-facing, so it waits on your say-so.
5. Should the stale `origin` (official KEXP repo) be removed from this app repo's remotes? Recommendation: yes, once the library is out, so nothing here can push to it.

### 17. Documentation Strategy

**Documentation Type:** DocC catalog in the new repo; README with install and usage; CHANGELOG starting at the extraction.
**Also updated:** this repo's master plan, ADR-002, session summaries in both repos.
