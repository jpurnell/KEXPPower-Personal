# Design Proposal: Stay behind live (the cushion), Phase 3 of live rewind

**Status:** APPROVED 2026-11-09, **Part A and "Cushion now" only; Part B (slow drift) is dropped** (owner: "we do Part A, skip part B"). The owner asked for the scope and lift ("What's the lift on live rewind phase 3?") and then for it to be written up; §16 records the answers. This is Phase 3 of `LiveRewind.md` §4, left optional there.
**Date:** 2026-11-09
**Facts marked (repo) were read in this repository on 2026-11-09. Anything not checked on a device is marked *unverified*.**

**A correction to what I told the owner on 2026-11-09.** I recommended building the cushion by playing slightly slow
(about 0.9x). That arithmetic is wrong for the goal: at 0.9x the listener falls behind by 6 seconds a minute, so a
five-minute cushion takes about 50 minutes to build, and a 0.95x rate takes about 100. §3 redesigns around that.

---

## 1. Objective

Let the listener keep the live stream a few minutes behind on purpose, so that when the signal is lost (a subway tunnel)
the music keeps playing from what the app already holds, and returning to "live" means returning to that cushion rather
than to the newest audio.

## 2. Motivation

**Today (repo):**
- Live plays through a recording of up to ten minutes (`RewindWindow`: Off, 5, 10; `LiveWindow` holds the arithmetic;
  `PlayerController` seeks within it: `skipLive`, `rewindLive`, `scrubLive`, `catchUpToLive`).
- Phase 0 showed the mechanism works: with the player five minutes behind, music played through two minutes of airplane
  mode (`LiveRewind.md`, `CHANGELOG.md`).
- The cushion only exists if the listener is already behind: at the live edge, a lost signal stops the music within
  seconds. Today the listener makes the cushion by tapping back five minutes before the tunnel. That **replays** five
  minutes of music they have just heard, because they were live a moment ago.
- The bolt goes to the newest audio (`catchUpToLive`), which throws the cushion away.

**The constraint that shapes the design:** you cannot be N minutes behind live without either having waited N minutes
(playing nothing, or playing slower), or replaying audio. There is no third way; the stream does not arrive faster than
real time. So a "cushion" is built from time, and the design is about where that time comes from.

## 3. Proposed Architecture

Two parts, so the cheap and certain part ships first.

**Part A: hold the cushion once there is one (small, certain).** A setting, "Stay behind live" (Off, 2 minutes,
5 minutes; default Off). While live plays through the recording:
- The bolt and skip-forward stop at the *cushion point* (live minus the cushion) when the listener is further behind,
  instead of going to the newest audio. If the listener is already at or nearer than the cushion point, they are
  "at their cushion" and the bolt does nothing more than say so.
- A second control, "Go fully live", reaches the newest audio (long-press on the bolt on iOS, a menu item on the Mac, a
  second row in CarPlay). It gives up the cushion on purpose.
- The "behind live" clock reads relative to live as it does now; at the cushion it reads `-5:00`, and the label says
  "Cushion" instead of a bare minus.
- `LiveWindow` gains the cushion as a parameter. Everything is arithmetic on values that already exist, so it is tested
  as `LiveWindow` is.

A listener builds the cushion today by pausing or rewinding, and Part A makes it stick.

**Part B: build the cushion without replaying (the part with risk).** The recorder holds audio as it arrives, so the
only honest ways to get behind are:
1. **Start behind.** Begin playing from audio already held. The recording starts when the first play starts
   (`LiveShifting.start()` in `playLive()`), so at the first play there is **nothing** to start behind. Not possible for
   the first listen; possible after a pause or a restart of live inside one session.
2. **Play slightly slow until the cushion is reached** (0.92x to 0.95x, pitch-corrected by `AVPlayer`'s
   `audioTimePitchAlgorithm`), then return to 1.0x. At 0.95x a five-minute cushion takes about 100 minutes; at 0.92x,
   about 62. Whether a listener can hear 8 percent slower is *unverified*; music at that rate with pitch correction is
   noticeable to some.
3. **Pause-and-resume habits:** every pause adds its length to the cushion automatically (resuming at the paused moment
   is how pause works today, `LiveRewind.md`). Nothing to build; Part A keeps what a pause builds.
4. **Pre-roll:** start the recorder earlier than the first play (at launch, or when the phone connects to Wi-Fi). The
   app is not running before launch and iOS suspends it within seconds in the background, so it helps only while the app
   is open. Rejected as the main mechanism, kept as a note in §15.

Part B is therefore the slow drift of item 2, opt-in ("Build the cushion gradually"), a separate toggle, off by
default, and **proposed only as an experiment to be judged by ear on a device** (§16).

## 4. API Surface

```swift
// TimeShift/Cushion.swift (new, pure, tested)
enum Cushion: String, CaseIterable, Identifiable, Sendable {
    case off, twoMinutes = "2", fiveMinutes = "5"
    static let storageKey = "cushion"
    var duration: TimeInterval? { get }
    /// The stored choice; Off when nothing valid is stored.
    static func resolve(stored: String?) -> Cushion
    /// The cushion in force for a window: never more than half of it, so there is always room to rewind further.
    func effective(forWindow window: TimeInterval?) -> TimeInterval?
}

// LiveWindow (existing, gains)
extension LiveWindow {
    /// Where "back to live" lands for a cushion: the newest audio minus the cushion, or `.live` with none or when
    /// already nearer than it.
    func target(catchingUpWithCushion cushion: TimeInterval?) -> Target
    /// Whether the listener is at their cushion, give or take `liveSlack`.
    func isAtCushion(_ cushion: TimeInterval?) -> Bool
}

// PlayerController (existing, gains)
func catchUpToCushion() async        // what the bolt does when a cushion is set
func goFullyLive() async             // the newest audio, ignoring the cushion
var cushion: TimeInterval? { get }   // the effective cushion for the window in force
```

Part B (only if approved): `PlayerController.buildCushion()` sets `player.rate` and
`audioTimePitchAlgorithm = .timeDomain`, watched by the existing lag watcher (`watchLag`), and returns to `1.0` when
`behindLive >= cushion`.

## 5. MCP Schema

N/A.

## 6. Constraints & Compliance

**Concurrency:** values are `Sendable`; the new `PlayerController` methods are `@MainActor` on the existing controller,
each one isolated async method (as `reconfigureLive`).
**Safety:** no force unwraps; a window of `nil` (Off) or a non-finite value gives no cushion; a cushion never exceeds
half of the window, and with a five-minute window a five-minute setting reads as two and a half (`effective`).
**Persistence:** `UserDefaults` through `@AppStorage`, key `cushion`; `Settings` gains one row in the Listening section
(shown only when the window is not Off).
**Accessibility:** the bolt's label changes with the setting ("Back to your cushion" / "Catch up to live"); "Go fully
live" has its own label and hint.

## 7. Source & API Compatibility

**Breaking changes:** none; with the setting Off (the default) every path behaves as today. The bolt's behavior changes
only for a listener who turned the setting on.
**Lock screen and CarPlay:** their skip-forward and scrub go through `skipLive` and `seekLive`, which Part A routes
through the same clamp, so they stop at the cushion too; the system's "go to live" command, if exposed, maps to
`goFullyLive`. *Whether the lock screen has a live button on this path is unverified.*

## 8. Backend Abstraction

N/A.

## 9. Resource Budget

No new storage or network: the window is the one already kept (10 minutes is about 12 MB at 160 kbps). A cushion lowers
the time that remains for rewinding further, which `effective` bounds. Part B uses a changed playback rate and the
lag watcher already running every two seconds.

## 10. Dependencies

None added. `AVFoundation` (`AVPlayer.rate`, `audioTimePitchAlgorithm`) for Part B only.

## 11. Test Strategy

Red first:
- **`CushionTests`:** `resolve` for stored values, an unknown value and nothing; `effective(forWindow:)` for Off,
  2/5 minutes in 5- and 10-minute windows, `nil`, `.nan`, zero and negative windows.
- **`LiveWindowTests` additions:** `target(catchingUpWithCushion:)` from far behind, at the cushion, nearer than it,
  with no cushion, and with an empty window; `isAtCushion` at the edges and `liveSlack`; skip forward clamps at the
  cushion and `goFullyLive` does not.
- **`PlayerControllerTests` additions:** the bolt lands at the cushion; `goFullyLive` lands at the end; with the setting
  Off nothing changes; reconfiguring the window re-clamps the cushion.
- **Part B:** the rate logic as a pure function (`rate(behind:cushion:)`: slow while below the cushion, 1.0 at it,
  1.0 when no cushion), tested; the audible result and the pitch quality are **device checks**.
- **Device:** hold a cushion across a real dead zone (airplane mode, then the subway); the bolt and "Go fully live" on
  the phone, the lock screen and in the car.

## 12. Architecture Decision Review

**ADR Check:**
- [x] Reviewed `project/decisions/` (ADR-003, 009, 010).
- [x] Supersedes an existing ADR? No.
- [x] Amends an existing ADR? No; ADR-010's consequences ("a cushion for a dead zone") are what this builds on.
- [x] New ADR required? **No.**

## 13. Adversarial Review

**Strongest case for a different approach:** do not build this. The listener can already pause, rewind and bolt, and
Part A only changes where the bolt lands; the cushion itself still has to be built by hand, and Part B's slow drift
takes an hour. A reviewer would say the feature promises a subway cushion and delivers a bolt that stops short.

**Where this design is most likely wrong:**
- Part A may confuse: a bolt that does not reach live. "Go fully live" is the mitigation, and the setting is off by
  default.
- Part B's slow-play may be unacceptable by ear, and one hour to build five minutes is not what the owner pictured when
  asking for "a 5-10 minute cache". If so, the honest result is that the app cannot create a cushion from nothing, and
  the first-listen cushion is a paused start.
- The cushion fights the rewind: a five-minute cushion in a ten-minute window leaves five to rewind, which `effective`
  and the half-window cap keep from reaching zero.

**What an experienced critic would say:** "The real answer to the subway is to start the recorder before you need it,
and you can't." Agreed; §15 lists what could change that.

## 14. Alternatives Considered

**Alternative 1: seek back by the cushion when the setting is turned on.** Advantage: instant. Disadvantage: replays
audio the listener just heard; this is what the rewind button does already. Rejected as the setting's behavior; the
button stays.

**Alternative 2: begin playback delayed by the cushion** (silence, then music). Advantage: exact. Disadvantage: minutes
of nothing at the start of every listen. Rejected.

**Alternative 3: only Part A** (no slow-play). Advantage: certain, small, nothing audible to judge. Disadvantage: the
cushion is built only by pausing or rewinding. **This is the smallest version worth shipping, and the one recommended
first.**

**Alternative 4: a "Cushion now" button** that seeks back by the cushion in one tap, labelled as a replay ("Replays 5
minutes so a tunnel won't stop the music"). Advantage: honest and immediate, a subway user's real need ("I'm about to go
underground"). Disadvantage: a replay. *Recommended alongside Part A; it is the rewind button with a name that says why.*

## 15. Future Directions

- **Start the recorder at launch or on Wi-Fi** so the window is already full at the first play.
- **Ask KEXP about a live HLS stream** with its own window (`LiveRewind.md` §8.3), which would make the cushion native.
- **A cushion on Apple Watch.** Out of scope.
- **Smarter drift:** pause the drift during talk and speed back up on music. Needs the playlist; *unverified*.

## 16. Open Questions

Answered by the owner on 2026-11-09: (1) Part A plus "Cushion now"; Part B skipped. (2) 2 and 5 minutes, with the 10-minute window the default: "the right options and defaults". (3) Default Off. (4) Part B's rate: moot. Nothing is open. Original questions follow, as asked.

1. **Scope.** Part A plus "Cushion now" first, Part B (slow drift) as a separate decision after it is heard on a
   device? *Recommendation:* yes.
2. **Choices.** 2 and 5 minutes, with the 10-minute window the default? *Recommendation:* yes.
3. **Default.** Off. *Recommendation:* Off; the owner's phrase was "a setting".
4. **Part B rate.** If built: 0.95x (100 minutes to five) or 0.92x (about an hour)? *Recommendation:* decide by ear.

## 17. Documentation Strategy

**Documentation Type:** API Docs Only.

**Reconciled on approval and on shipping:** `LiveRewind.md` §4 (Phase 3 status); the master plan Roadmap; `Settings.md`
(the new row); the README; CHANGELOG at each step.

**Order of work (each step: tests first, gate clean, path-scoped commit)**
1. `Cushion` and the `LiveWindow` additions, with tests.
2. `PlayerController`: `catchUpToCushion`, `goFullyLive`, the clamped skip and scrub; the bolt, lock screen and CarPlay
   routed through them, with tests.
3. The Settings row and the labels ("Back to your cushion", "Cushion now", "Go fully live").
4. Device check on Brawn: across a dead zone, on the lock screen, in the car.
5. ~~Part B~~ dropped by the owner, 2026-11-09. Everything about Part B above is kept as the reasoning recorded at the time.
