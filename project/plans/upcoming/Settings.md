# Design Proposal: Settings on every platform

**Status:** APPROVED 2026-11-08; the open questions were answered by the owner the same day (§16), including "my time zone is right for show times". Follows `LiveRewind.md` §10, which fixed what the screen must hold.
**Date:** 2026-11-08
**Facts marked (repo) were read in this repository on 2026-11-08.**

---

## 1. Objective

Give the listener one place to change the settings that matter on iPhone, iPad and Mac, and make a change take effect
without relaunching the app: the live rewind window, the stream quality, and the time zone that show times are drawn in.

**Master Plan Reference:** Roadmap, live rewind (Phase 1 follow-up); `LiveRewind.md` §8 and §10; Known Problems, the
archive's days are Seattle's while its times are the listener's (`master_plan.md`).

## 2. Motivation

**Current situation:**
- **Stream quality** (160 or 64 kbps) can be chosen only on the Mac, in the Settings window (`SettingsView`, repo). The
  iPhone and iPad have no way to choose it.
- **Rewind window** (Off, 5 or 10 minutes, default 10) is built (`RewindWindow`, repo) and stored under `rewindWindow`,
  but nothing lets the listener change it.
- Both are read **only when the player is first created** (`ResultRetriever.getResults`, repo), so a change would
  apply at the next launch at best.
- **Show times** are drawn in the listener's zone in the archive's rows and player bar and in the live rewind clock
  (`ArchiveTiming.clock(_, zone: .autoupdatingCurrent)`, repo), but in the **station's** zone in CarPlay's show rows
  (`CarPlayContent.archiveShowRow`, repo). Nothing lets a listener choose, and the two disagree with each other.

**Workaround:** none for the phone. The Mac listener can change quality; nobody can change the window or the zone.

**Drawback:** a listener who wants the data saver, no recording, or the station's own clock cannot have it, and the
iPhone's recording of the stream (about 12 MB on disk, and a second download of the stream while it plays) cannot be
turned off.

## 3. Proposed Architecture

**New files**
- `Settings/ListeningSettings.swift`: pure value (quality, window); reads the stored values, says whether a change
  needs the live stream rebuilt, and estimates the window's size on disk.
- `Settings/ShowTimeZone.swift`: enum `mine`, `station`; storage key, label, `zone` (the `TimeZone` to draw in),
  `resolve(stored:)`.
- Tests: `ListeningSettingsTests`, `ShowTimeZoneTests`, additions to `PlayerControllerTests`, `CarPlayContentTests`.

**Modified files**
- `SettingsView.swift`: becomes cross-platform; Listening section (window, quality) and Times section (show times in),
  each picker with its explanatory line.
- `Audio Player/AVPlayer.swift` (`PlayerController`): `reconfigureLive(link:liveShift:)`.
- `Retrievers/ResultRetriever.swift`: `applySettings(_:)`; the stream and time-shift construction in `getResults`
  moves into it, so the first build and a later change share one path.
- `Archive/ArchivePlayerBar.swift`, `Archive/ArchiveView.swift`, `TimeShift/LiveRewindControls.swift`: draw times in
  `ShowTimeZone`'s zone instead of `.autoupdatingCurrent`, reading the stored choice so they redraw when it changes.
- `CarPlay/CarPlayContent.swift`: `archiveShowRow` takes the zone, so the car follows the same choice.
- Live and Archive screens (iOS): a gear button opening the screen as a sheet with Done.

**Placement:** the Mac keeps the Settings scene (Cmd-comma). On iPhone and iPad a gear in the navigation bar of the Live
and Archive screens opens a sheet. A fifth tab or a sidebar row is rejected: settings are not a place the listener goes
to, and the iPhone tab bar already holds four. CarPlay has none; a driver does not change settings.

**Applying a change**
- *Window and quality:* applied when the screen is dismissed (Done, or the Mac window closing), and only if something
  changed; applying on each tap would restart the stream under the listener's thumb. If live is playing or paused on
  live, the live source is rebuilt (the time-shift stops, its window is emptied, the new address and window are used,
  the play state is kept). If an archived show is playing nothing is interrupted: the new values are used when the
  listener returns to live, which already re-resolves the live source (`returnToLive`, repo). If nothing is playing, the
  next play uses them. The screen says so: "Changing these restarts the live stream."
- *Show times in:* applied immediately. Nothing restarts; the views that draw times redraw.

## 4. API Surface

```swift
struct ListeningSettings: Equatable, Sendable {
    var quality: StreamQuality
    var window: RewindWindow

    static func current(defaults: UserDefaults = .standard) -> ListeningSettings
    /// Whether going from `old` to `new` means the live stream must be rebuilt.
    static func restartsLive(from old: ListeningSettings, to new: ListeningSettings) -> Bool
    /// Bytes the window holds at a quality, for the line under the picker; zero for Off.
    static func approximateBytes(window: RewindWindow, quality: StreamQuality) -> Int
}

enum ShowTimeZone: String, CaseIterable, Identifiable, Sendable {
    case mine, station
    static let storageKey = "showTimeZone"
    var label: String { get }            // "My time zone", "Seattle (the station's)"
    var zone: TimeZone { get }           // .autoupdatingCurrent, ArchiveTiming.stationTimeZone
    static func resolve(stored: String?) -> ShowTimeZone   // .mine when nothing valid
}

extension PlayerController {
    /// Replaces the live stream's address and time-shift and starts live over, keeping the play state.
    func reconfigureLive(link: URL, liveShift: (any LiveShifting)?) async
}
```

The default for show times is **my time zone**: it is what the app does today everywhere but CarPlay.

## 5. MCP Schema

N/A. This is an app's settings screen; it exposes no public API, library surface or tool. Nothing here is added to
`KEXPPowerKit`, `StationKit` or the adapter.

## 6. Constraints & Compliance

**Concurrency:** `ListeningSettings` and `ShowTimeZone` are value types and `Sendable`. `reconfigureLive` is
`@MainActor` on the existing controller, and the work is one isolated async method (no `Task` closure touching actor
state, per the gate's concurrency auditor).
**Safety:** no force unwraps; an unreadable stored value resolves to the default; `approximateBytes` has no division
by zero (it multiplies a duration by a bitrate and divides by a constant eight).
**Persistence:** `UserDefaults` through `@AppStorage`, with the keys that already exist (`streamQuality`,
`rewindWindow`) plus `showTimeZone`, so nothing stored today is lost.
**Platform:** the screen is one SwiftUI view on iOS, iPadOS and macOS; the Mac keeps its window.
**Accessibility:** each picker's explanation is in the control's accessibility hint, and the gear has a label
("Settings").

## 7. Source & API Compatibility

**Breaking changes:** none. `ArchiveTiming.clock`'s callers keep passing a zone; they pass a different one.
`CarPlayContent.archiveShowRow` gains a parameter (internal API, one caller and its test).
**Behaviour change to flag:** CarPlay's archive times move from the station's zone to the listener's by default, to
match the phone. It is chosen by the setting and is the more consistent of the two.
**Incremental adoption:** yes; each of the three settings is independent, and the steps in §17 land separately.

## 8. Backend Abstraction

N/A. Nothing compute-intensive.

## 9. Resource Budget

**Data read:** the stored settings (three small strings) and, for the estimate, nothing more.
**Held vs streamed:** nothing new is held. The time-shift's recording is the only data of size here: 160 kbps is about
20 KB a second, so a 10-minute window is about **12 MB** on disk and 5 minutes about 6 MB; at 64 kbps, 5 MB and 2.4 MB.
**Growth:** bounded by the window setting (maximum 10 minutes) and does not grow with listening time; the recorder
drops the oldest segment at the cap.
**Budget:** at most about 12 MB on disk and a few MB in memory for the window (peak), and none at rest when the
window is Off.
**Measured by:** `approximateBytes` is tested against the known rates; the on-disk size of the time-shift folder after a
10-minute listen is read on a device before release (it was about the size above in the Phase 0 runs, `LiveRewind.md`).
**Lifetime:** the app can run for days. A settings change must leave no more behind than a normal stop: `reconfigureLive`
stops the old time-shift (which already clears its folder) before the new one starts, and a test asserts the old one
was stopped.

## 10. Dependencies

**Internal:** `StreamQuality`, `RewindWindow`, `LiveTimeShift`/`LiveShifting`, `PlayerController`, `ResultRetriever`,
`ArchiveTiming`, `ArchivePlayerBar`, `ArchiveView`, `LiveRewindControls`, `CarPlayContent`.
**External:** none.

## 11. Test Strategy

**Test categories**
- *Golden path:* each stored value resolves to its case; `current(defaults:)` reads both settings from a throwaway
  `UserDefaults` suite.
- *Edge cases:* nothing stored, an unknown stored string, and an empty one, each giving the default (ten minutes,
  standard quality, my time zone); Off giving zero bytes.
- *Restart rule:* unchanged → no restart; window changed → restart; quality changed → restart; both → restart.
- *Player:* `reconfigureLive` swaps in the new link and time-shift, stops the old time-shift, keeps a paused player
  paused, leaves an archived show playing, and takes effect on `returnToLive`.
- *Retriever:* `applySettings` builds a time-shift only when the window is not Off, and uses the chosen quality's
  stream.
- *Times:* `ShowTimeZone.zone` is the station's zone for `station` and the current zone for `mine`; `archiveShowRow`
  formats the same start time differently under the two (7:00 AM Seattle is 10:00 AM in a UTC-5 zone).

**Reference truth:** bitrate arithmetic from the stream's own rates (160 kbps = 20,000 bytes/s; 64 kbps = 8,000
bytes/s), and the zone offsets of `America/Los_Angeles` and a fixed-offset test zone.

**Validation trace**
- 10 minutes at 160 kbps → 600 s × 20,000 B/s = 12,000,000 bytes (about 12 MB).
- 5 minutes at 64 kbps → 300 s × 8,000 B/s = 2,400,000 bytes.
- Off at any quality → 0.
- 7:00 AM `America/Los_Angeles` on 2026-11-06 (PST, UTC-8) = 15:00 UTC; under `mine` in a UTC+0 zone the row reads
  "3:00 PM"; under `station` it reads "7:00 AM".

The sheet, the gear, the Mac window and the audible restart are checked on the devices, since none is reachable by an
automated test.

## 12. Architecture Decision Review

**ADR Check:**
- [x] Reviewed `project/decisions/` (ADR-001, 002, 003, 006, 009) for related decisions.
- [x] Supersedes an existing ADR? No.
- [x] Amends an existing ADR? No. ADR-003 (one writer for Now Playing) is unaffected: settings do not publish Now Playing.
- [ ] New ADR required? **Not for this change.** The local server and buffer decision still needs its own ADR, now that
  Phase 0 proved it (`LiveRewind.md` §9); that is separate from settings.

## 13. Adversarial Review

**Strongest case for a different approach:** apply window and quality changes the next time the listener presses play,
and never interrupt anything. It is simpler (no `reconfigureLive`), and the cost is only that a setting can seem to do
nothing for a while. A thoughtful reviewer would add that the app is often never quit, so "next launch" is never.

**Where this design is most likely wrong:**
- It assumes the live source can be rebuilt without leaving the player in a state `returnToLive` does not expect. That
  path was written for returning from an archive, and has been used one way only; the player tests are where this is
  checked, and the device is where it is proved.
- It assumes a listener will find the settings through a gear on two screens. If it turns out nobody does, the sheet
  could be reached from the Live bar too.
- Changing the default for CarPlay's archive times from station to listener's zone is a decision made here by
  consistency, not asked of anyone who uses it in a car.

**What an experienced critic would say:** "Three settings is too few to justify a screen, a sheet, a settings value
type and a rebuild path." We proceed because one of the three (the window) cannot be reached any other way, it is the
setting the live rewind feature depends on, and the Mac already has the screen; the value type is small and is what
keeps the restart rule testable.

## 14. Alternatives Considered

**Alternative 1: apply each tap immediately.** Advantage: nothing to dismiss. Disadvantage: a restart of the stream per
tap while the listener is choosing. Rejected.

**Alternative 2: apply only at the next play or launch.** Advantage: no rebuild path. Disadvantage: a setting that
silently waits is worse than one that says it restarts the stream. Rejected (the owner chose "restarting live if
needed").

**Alternative 3: a Settings tab or sidebar row.** Advantage: discoverable. Disadvantage: the iPhone tab bar already holds
four, and settings are not a place the listener goes to. Rejected (the owner chose the gear).

**Alternative 4: a settings model with change observation** instead of `@AppStorage`. Advantage: one observable object.
Disadvantage: more machinery for three values; `@AppStorage` plus one pure comparison is enough.

## 15. Future Directions

- **Stay behind live:** a setting that holds the playhead a few minutes behind live on purpose (Phase 3 of
  `LiveRewind.md`) could live in the same Listening section.
- **Download over Wi-Fi only** for the time-shift might be offered if listeners on cellular ask.
- **A Settings entry on CarPlay's phone-side prompt** could point a driver to the phone when a setting matters; it is
  not needed now.
- **The Watch** has its own player and none of these settings; it could be given quality later.

## 16. Open Questions

Answered by the owner on 2026-11-08:
1. *Entry on iPhone and iPad:* a gear on the Live and Archive screens. **Yes.**
2. *Applying a change:* when the screen is dismissed, restarting live if needed. **Yes.**
3. *"Show times in":* **in this change**, not as a follow-up.

4. *Default for show times:* "my time zone", with no first-launch prompt. **Yes.**

Nothing is open.

## 17. Documentation Strategy

**Documentation Type:** API Docs Only. The three APIs are small and have no theory behind them; no narrative article.

**Complexity Threshold Check:**
- Does it combine 3+ APIs? No.
- Does explanation require 50+ lines? No.
- Does it need theory/background context? No.

**Reconciled on approval:** this file's status; the master plan's Roadmap and Known Problems (the time-zone entry
moves from "known problem" to "a setting"); `LiveRewind.md` §10 (point here); the README's "not built yet" list;
CHANGELOG at each step.

**Order of work (each step: tests first, gate clean, path-scoped commit)**
1. `ListeningSettings` and `ShowTimeZone`, with their tests.
2. `PlayerController.reconfigureLive` and `ResultRetriever.applySettings`, with tests; `getResults` moves onto it.
3. Times drawn in `ShowTimeZone`'s zone in the archive, the live clock and CarPlay, with tests.
4. `SettingsView` cross-platform, and the gear and sheet on iOS.
5. Device check on Brawn and Springer, and the Mac window; the car for the archive times.

## Proposal Review Checklist

- [x] Module placement follows the existing structure (a `Settings/` folder beside `Archive/` and `TimeShift/`)
- [x] Concurrency is Swift 6 compliant
- [x] No forbidden patterns proposed
- [x] Source compatibility assessed; one internal signature changes
- [x] Adoption path documented
- [x] Future directions listed without commitments
- [x] At least one alternative with pros and cons
- [x] MCP: N/A, stated
- [x] Resource budget given as numbers, peak and at rest
- [x] Test strategy with reference truth and validation trace
- [x] ADR check done
- [x] Adversarial review answered
- [x] Open questions in §16 resolved
