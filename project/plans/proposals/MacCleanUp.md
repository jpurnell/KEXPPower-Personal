# Design Proposal: Mac clean-up (keyboard access, add-to-playlist fallback, widget check, loose ends)

**Status:** APPROVED 2026-11-05 (owner: "Open in Music, and absolutely with the UI Test targets"; so §3b is option A and the UI test target is part of this change)
**Date:** 2026-11-05
**Master Plan Reference:** Known Problems ("a row is no longer a keyboard-focusable button"), `PlatformExperience.md` (Mac playlist options), CLAUDE.md (`scripts/bootstrap.sh`).
**Facts marked (verified) were read from this repo; anything not confirmed is marked *unverified*.**

---

### 1. Objective
Close the four known Mac gaps in one pass, in this order: (a) rows reachable and operable from the keyboard, (b) a way to get a song into Apple Music from the Mac, (c) the widget confirmed on the Mac desktop, (d) two loose ends: the missing `scripts/bootstrap.sh` and the stale app copy in Xcode's DerivedData.

### 2. Motivation
- **Keyboard:** the row's tap gesture sits on the finished row (needed to make the whole row clickable; verified in `CombinedView.swift`). A gesture is not a control, so Tab skips a row and Return does nothing. A VoiceOver action stands in, but a keyboard-only user has no way to expand a song. This was a known cost of the click fix and is listed in the master plan.
- **Playlist add:** MusicKit's `MusicLibrary.add`, `createPlaylist` and `edit` are unavailable on macOS (checked in the macOS 27.2 SDK), so the Mac has no add button. The expanded row already has the song title as a button that opens the track in Apple Music (`Extended View.swift`, looked up through the iTunes search in `AppleMusicRetriever`), but only in the expanded state and with no visible affordance.
- **Widget:** the Mac widget is signed and the app writes to the Mac's Team-ID-prefixed group (verified), but nobody has looked at it on the desktop. Possibly an older Xcode-built copy is registered.
- **Loose ends:** `CLAUDE.md` tells a new clone to run `./scripts/bootstrap.sh`, which does not exist (verified: no `scripts/` directory), so the pre-commit hooks silently do not run on a fresh clone. `~/Library/Developer/Xcode/DerivedData` holds two `KEXPPower-*` folders from before the project moved.

### 3. Proposed Design

#### 3a. Keyboard access
Make the row focusable and give it a default action, without touching the click area that took four rounds to fix: `.focusable()` on the row, `.onKeyPress(.return)` and `.onKeyPress(.space)` toggling `small`, and a visible focus ring (the system's, not a custom one). The tap gesture stays where it is. Space is currently the app-wide Play/Pause menu shortcut, so Space on a focused row must not be taken by the row: **Return only**, and the Playback menu keeps Space. *Whether `.focusable()` on a row inside a `LazyVStack` on macOS 14 shows a ring without enabling Full Keyboard Access is unverified; I will try it and say what I see.*

#### 3b. Add to a playlist on the Mac: decision needed
| Option | What it does | Cost |
|---|---|---|
| **A. Open in Music (recommended)** | A visible "Open in Music" button on each song (collapsed and expanded), using the lookup that already exists. Add to a playlist there. | Small; no new entitlement; honest about the platform limit. One tap more than the phone. |
| B. Script the Music app | Add to the "KEXP" playlist by AppleScript. | Needs the sandbox Apple Events entitlement and an Automation permission prompt; App Store review is likely to reject a temporary-exception entitlement. Not recommended. |
| C. Hand off to the phone | Write the song to iCloud (a shared store) and have the phone add it. | Needs CloudKit or iCloud key-value storage and a portal change; a new sync surface to test. Possibly later. |

I recommend **A** now and C only if you find yourself using it.

#### 3c. Widget on the Mac desktop
Not a code change unless the check finds a defect. Steps: build and Run `Spinner Mac` from Xcode so the current extension is registered, add the widget in all three sizes, confirm the song, the art and the play/pause icon follow the app, and read the widget's log lines (`com.JPEnterprises.Spinner.widget`). **This part needs you at the Mac:** I can read logs and window lists but I cannot add a widget to the desktop for you. Defects found become their own commits.

#### 3d. Loose ends
- **`scripts/bootstrap.sh`:** write it as CLAUDE.md describes: set `core.hooksPath` to `.githooks`, check that `swift` and `quality-gate` are on the PATH, idempotent. Then CLAUDE.md and README describe what exists.
- **DerivedData:** list the two stale folders and delete them **only after you say so** (a delete I should not do on my own).

### 4. API Surface
None public. A private `onKeyPress` handler in `CombinedView`, a `MusicLinks`-adjacent button view for 3b, one shell script.

### 5. MCP Schema
Not applicable.

### 6. Constraints & Compliance
Swift 6 strict concurrency, no force unwraps, gate at 0/0 without suppressions. Accessibility: the new button has a label and the row keeps its VoiceOver action. Privacy: the Apple Music lookup already sends artist and title to the iTunes search; Option A adds a second place that does, no new data.

### 7. Source & API Compatibility
Additive. The macOS deployment target stays 14; `onKeyPress` is macOS 14.

### 8. Backend Abstraction
The lookup sits in the app (`AppleMusicRetriever`), not StationKit. If it should serve other stations it moves later; not in this change.

### 9. Resource Budget
Option A adds at most one iTunes search per song the user opens, and caches the result per row view. No polling.

### 10. Dependencies
None new. Portal: none.

### 11. Test Strategy
- **Keyboard:** the toggle logic is a pure state change, tested directly; the focus ring and Return behaviour need a UI test target, which does not exist. Stated plainly: until one exists this is checked by hand, as the click area was. I would rather add the UI test target than keep checking by hand, and propose it as its own item.
- **Open in Music:** a test that the button shows only when a track is found, and that a missing track leaves it hidden.
- **bootstrap.sh:** run it twice in a throwaway clone and check `core.hooksPath`; running it a second time changes nothing.

### 12. Architecture Decision Review
No new ADR.

### 13. Adversarial Review
1. **"Return on a focused row steals Return from the buttons inside it."** The Spotify and Bandcamp links are separate controls with their own focus; the row handles Return only when the row itself is focused. To be checked.
2. **"Option A is not really a playlist add."** Correct: it is a deliberate smaller promise, and the Mac README states the platform limit.
3. **"Deleting DerivedData could remove something you want."** Hence the explicit ask.

### 14. Alternatives Considered
In §3b. For keyboard access, wrapping the row in a `Button` was the first approach and is what broke the click area; rejected for that reason.

### 15. Future Directions
A UI test target (click and keyboard); option C; moving the Apple Music lookup into StationKit.

### 16. Open Questions
Answered 2026-11-05: option A; the UI test target is in this change. Still open: whether a UI test can run from this machine's sandboxed tooling (the Mac runner needs the Accessibility permission); the test target is written either way.

### 17. Documentation Strategy
CHANGELOG, README (Mac row), master plan Known Problems (strike the keyboard item when fixed), CLAUDE.md consistent with the script.
