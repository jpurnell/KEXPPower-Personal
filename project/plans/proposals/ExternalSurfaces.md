# Design Proposal: playing to surfaces other than the phone (CarPlay, AirPlay receivers, wearables)

**Status:** DRAFT 2026-11-17, **nothing approved.** Two changes in this area were built and pushed **before this proposal existed, which the guidelines forbid** (`664c9af` "live on an AirPlay route plays the stream directly" and `7263e45` "a recording start handed to an external receiver falls back to the stream at once"); they were fixes made while reading a device's journal, and §3 treats them as the first step of this design, for the owner to approve, change or reject. Everything else here is unwritten.

**Facts marked (device) were observed on Brawn (iPhone 15 Pro, iOS 27.3, Spinner 3.6.0) on 2026-11-17, from its on-device journal, a screenshot or the owner's video; (repo) were read in this repository; the owner's statements are quoted. Anything not observed is marked *unverified*.** Every device observation below comes from **one receiver**: the owner's home display ("Kitchen"), which shows CarPlay-style views and reports itself to the phone as AirPlay. **No real car, HomePod, Apple TV or wearable has been observed.**

---

## 1. Objective

Make "where the sound goes" a first-class input to how Spinner plays, so that a new surface (a car, a home display, a HomePod, an AR-glasses companion) starts quickly, shows the right state and the right controls, and is stopped only by the listener, **without a fix per device after the first failure.**

The owner's framing (2026-11-17): the home display is *"meant to play indefinitely in the home"*; a phone call must not become a reason to pause the house; and *"this method will apparently extend to wearables, like augmented reality glasses, so I want to get it right now."*

**Master Plan Reference:** `project/master_plan.md` Roadmap (CarPlay, Siri/Shortcuts, Platform experience); `LiveRewind.md` / ADR-010 (the local recording this design constrains); `LiveRecovery.md` (the live-start watch this design feeds).

## 2. Motivation

**Current situation.** (repo) Live plays through a local recording: `LiveRecorder` → `LiveRelay` → `LocalHLSServer` on `127.0.0.1`, and `PlayerController` plays that address (ADR-010), unless the recording cannot start in 15 s. Archive items are built from a public remote URL and never use the recording.

**What the journals show (device).**
- **Live from the home display took 23.8 s to 24.6 s, three times** (20:42, 20:55, 21:10, and again 21:39 after a relaunch). Each time the recording started, the player fetched the playlist twice and **no segment**, with `outputs AirPlay, external true`, and at 18 s the fall-back played the public stream directly. Archive, which uses a public URL, "works without issue."
- **Cause (supported, not isolated):** with external playback the **receiver** fetches the item itself; the recording's address is the phone's own loopback (`127.0.0.1`), which the receiver cannot reach. The phone-side counters fit (playlist fetched, zero segments, zero refused requests, zero item log events). I have not seen the receiver's own requests.
- **After `664c9af`, live from the display reached audio in 4.6 s** (21:44), with a direct start. The 4.6 s, against about 0.5 s on the phone speaker, is the receiver's own startup; its split is *unverified*.
- **The route at the moment live is requested is not always AirPlay**: on the first tap after a relaunch (21:39) the recording started anyway, and the route read AirPlay about a second later. That is why `7263e45` added external playback to the start evidence. Whether the route was actually not yet AirPlay at the decision is a hypothesis from the timing; the code path was not instrumented.
- **The controls change mid-start** (owner's video, 21:3x): the display first shows skip-15 buttons and a time bar (what the recording exposes), then a black frame, then previous/next and pause. That is the swap from the recording to the direct stream at 18 s; it also left the screen black and without art.
- **Switching the phone's speaker to "iPhone Speaker" pauses both devices** (owner). The app follows `StationKit`'s `AudioSessionCoordinator`, which turns an "output device removed" route change into a pause (repo). An attempt to ignore that pause while a receiver plays (`fa289f9`) was withdrawn after the owner observed that Apple News behaves the same: *"I guess we have to accept that limitation"* (`ff1ea3a` keeps only the logging).
- **Title and artwork reach a receiver by a different path than the phone's lock screen** (device, 5:14 pm screenshots): the lock screen showed the art, "Choo-Choo" and the artist, while the display showed none of them and `--:--` times. The phone reads the system's Now Playing info (`MPNowPlayingInfoCenter`); a receiver playing the stream itself reads the **playing item's own metadata** (`externalMetadata`), which the app attached only to the item that existed when a track arrived (repo). Every live start makes a new item, so the display had nothing. `9575285` makes live items carry the current metadata, and the display then showed it (owner: "that's working"). Whether a track change *after* the handover reaches the display is **unverified** (a track changed before the test could be watched).
- **The route label.** The owner's display shows as `AirPlay` to the phone and the lock screen reads "iPhone → Kitchen"; the app's `OutputRoute.carPlay` is only for a `CarAudio` port, which none of the journals above has shown.

**Workaround today.** One patch per failure: a route check (`664c9af`), an evidence rule in the start watch (`7263e45`), a withdrawn pause rule. Each was found after the owner waited. The next surface, with an unknown route type, would play the recording and wait 18 s.

**Drawbacks.** The decision "recording or stream" is made in three places with different information; the controls shown depend on which item happens to be playing; and the default for a route the app does not know is the one that fails.

## 3. Proposed Architecture

**The principle: use the loopback recording only where the phone is positively the source of the sound; everywhere else play the stream anyone can fetch.** Today the default is the opposite, which is why each new surface fails first.

**Three pieces, all small and pure where they can be:**

1. **`PlaybackSource`** — classifies where the sound goes, from the output port types and whether external playback is active: `.phone` (the phone's speaker, wired or Bluetooth headphones, a Bluetooth or CarPlay `CarAudio` output, where the phone renders the audio), `.receiver` (AirPlay or external playback, where the destination fetches and renders it), `.unknown` (any port type not listed, including whatever a wearable reports). **`.unknown` is treated as `.receiver`**: the public stream works from anywhere; the recording works only on the phone.
2. **`LivePlan`** — a pure decision: `LivePlan.choose(source:, recordingAvailable:, rewindWanted:) -> LivePlan` returning `.recording` or `.direct(DirectReason)`, with the reason a code (`receiver`, `unknownRoute`, `recordingUnavailable`, `rewindOff`, `evidenceFallBack`). It replaces the route check in `playLive()` and is the one place the question is answered; the start watch's external-playback rule stays as the second line (the route can change after the decision) and reports the same reason code.
3. **Two publishing paths, one source.** Now Playing state is published to *both* the system (`MPNowPlayingInfoCenter`, for the phone, lock screen and CarPlay) *and* the item (`externalMetadata`, for a receiver that fetches it), from the same snapshot, and **every item the app creates gets the current snapshot at creation** (`liveItem(url:)`, `9575285`). A new surface is checked against both paths.
4. **`PlaybackCapabilities`** — what the listener may do with the current plan (`.recording`: rewind and skip within the window; `.direct`: pause and play only). **Controls are published from the plan decided at the start, not from the item that happens to be playing**, so a start that ends direct shows the direct controls from the beginning instead of flipping at 18 s. Now Playing metadata (title, artwork) is published from what the listener asked for (live or an archive show), so it does not go blank while the player is rebuilt.

**Who may pause what (a table, not code):** the listener's own pause or a remote-control pause always pauses. A system action (an output device removed, an interruption) pauses only because the system does; the app follows it and **records it** (`ff1ea3a`). The app does not try to override the platform. A phone call while a receiver plays is *unverified* (§16).

**When the route changes during playback:** recording → receiver re-plans to `.direct` and switches the item (the listener hears the live edge, not their rewound position); receiver → phone is not switched back automatically (the system pauses it; the next play re-plans). Never switch back and forth on its own.

**Files (proposed):**
- New: `KEXPPower SwiftUI/Audio Player/PlaybackSource.swift` (`PlaybackSource`, `LivePlan`, `DirectReason`, `PlaybackCapabilities`; no AVFoundation, so it is unit-testable), `KEXPPowerAppTests/LivePlanTests.swift`.
- Modified: `AVPlayer.swift` (`playLive()` asks `LivePlan.choose`; capabilities published before the item swap; a route observer re-plans), `LiveStart.swift` (`OutputRoute` gains the port mapping `PlaybackSource` needs; `LiveStart` event gains a `plan`/`reason` code), `Diagnostics/FieldEvent.swift`, the Spinner schema (provisional kind change, see §7), `project/diagnostics/spinner-schema.json`.
- **Module placement:** the app target. `PlaybackSource` could move to `StationKit` once a second app (the watch, a glasses companion) needs it (§15).

## 4. API Surface

```swift
/// Where the sound is rendered.
enum PlaybackSource: Sendable, Equatable {
    case phone      // the phone renders it: speaker, headphones, Bluetooth, CarPlay (CarAudio)
    case receiver   // the destination fetches and renders it: AirPlay / external playback
    case unknown    // a route type not known here; treated as .receiver

    init(portTypes: [String], externalPlayback: Bool)
}

enum DirectReason: String, Sendable, Equatable, CaseIterable, Codable {
    case receiver, unknownRoute, recordingUnavailable, rewindOff, evidenceFallBack
}

enum LivePlan: Sendable, Equatable {
    case recording
    case direct(DirectReason)

    static func choose(source: PlaybackSource, recordingAvailable: Bool, rewindWanted: Bool) -> LivePlan
}

/// What the listener may do under a plan; published before the item is swapped.
struct PlaybackCapabilities: Sendable, Equatable {
    var canRewind: Bool
    var canSkipWithinWindow: Bool
    init(plan: LivePlan)
}
```

`PlayerController` gains `var playbackSource: @MainActor () -> PlaybackSource` (an injectable seam, as `outputRoute` is today) and an `Observation`-visible `capabilities`.

## 5. MCP Schema

N/A for an AI-consumed API: this is app-internal. The one machine-readable surface is the hub event: `liveStart` gains `plan` (`recording` | `direct`) and `reason` (a `DirectReason` code or `none`), both fixed-vocabulary codes (no strings from the system, no route names). Shape, for the provisional path (`hub 0.8.0`, development key):

```json
{ "kind": "liveStart", "fields": { "outcome": "started", "took": "from2to5", "network": "wifi", "route": "airPlay", "plan": "direct", "reason": "receiver" } }
```

## 6. Constraints & Compliance

**Concurrency:** all new types are `Sendable` value types; the route observer is `@MainActor` like `PlayerController`. **Safety:** no force unwraps; every `switch` over `PlaybackSource` is exhaustive; port types are matched against a fixed list and anything else is `.unknown`, never trusted as a name. **Privacy:** the event carries codes only, never a device name ("Kitchen") or port string. **Determinism:** `LivePlan.choose` is pure. **Quality gate:** no suppressions.

## 7. Source & API Compatibility

**Breaking changes:** none to callers; `playLive()` keeps its signature. **Schema:** `liveStart` gains two fields; the hub's registered `spinner` schema is version 5 (the `liveStart` kind is registered), so added fields go through `schema diff` / `schema apply` as an additive change, or the kind is sent provisionally on the development key meanwhile (hub 0.8.0). **Behavior change worth stating:** on an `.unknown` route the app now plays the stream where it used to play the recording; rewind is not offered there.

## 8. Backend Abstraction

N/A — no compute-intensive work.

## 9. Resource Budget

**Data held:** one `PlaybackSource` value, one `LivePlan`, one `PlaybackCapabilities`, and one route-change subscription (a few hundred bytes). **Growth:** none from this feature. The route-change journal line is **new per route change and not rate-limited today**; a route that flaps (a Bluetooth device reconnecting) could write many lines, bounded only by the journal's rotation at 256 KB per file for 14 days (`DiagnosticLog`). **Budget:** at rest and peak, under 100 KB resident added; the proposal adds a coalescing rule (one line per second per reason) so a flapping route cannot fill the journal. **Measured by:** a test that fires 10,000 route changes and asserts the journal stays under one rotation file. **Lifetime:** the app runs for hours in the background; no state accumulates.

## 10. Dependencies

None new. `AVAudioSession` and `AVPlayer` (system), `StationKit`'s `AudioSessionCoordinator` (existing).

## 11. Test Strategy

**Unit (pure, in `LivePlanTests`):** a table over every `PlaybackSource` × `recordingAvailable` × `rewindWanted` giving the plan and reason; a table of port type strings to `PlaybackSource` (including an unlisted string and an empty route, both `.unknown`); `PlaybackCapabilities` for each plan.

**Controller (existing seams, `FakeShift`):** a receiver route plays the stream and never starts the recording; a phone route plays the recording; an unknown route plays the stream; capabilities are published before the item is swapped (the controls never flip); a route change from phone to receiver while playing re-plans to direct exactly once and never back; the listener's pause pauses a receiver; a system pause is followed and recorded.

**Device matrix (manual, recorded in the session summary):** phone speaker; wired and Bluetooth headphones; the Kitchen display (AirPlay, observed); a HomePod and an Apple TV (*unverified*); a real car, or Xcode's CarPlay simulator, for `CarAudio` (*unverified*); a phone call while a receiver plays (*unverified*). Pass criterion for a start: audio in 5 s or less on every surface, no control flip, no blank Now Playing.

## 12. Architecture Decision Review

**ADR-010** (live plays through a local recording) is **amended**: the recording is used only when the phone renders the sound. On approval, a new ADR is recorded in `project/decisions/` stating that, and ADR-010 gets a pointer. The pause-follows-the-system rule (`ff1ea3a`) is recorded as an ADR too, since it reverses an attempt the owner has since withdrawn. No other ADR is touched.

## 13. Adversarial Review

**Against this design.**
1. **It rests on one receiver.** The Kitchen display is the only AirPlay destination observed. A HomePod, an Apple TV or AirPlay 2 speaker may behave differently (for example, AirPlay 2 audio streamed *from the phone* rather than handed off by URL, in which case the phone is the source and the recording would have worked). Playing the stream there is still correct, only without rewind, so the failure is a lost feature, not a broken start. *Mitigation:* the device matrix; the `plan` and `reason` codes in the hub will show which surfaces took which path.
2. **"Unknown plays the stream" trades rewind for safety.** A glasses companion that renders on the phone would lose rewind it could have had. *Mitigation:* an explicit allow-list for `.phone` that grows as surfaces are observed.
3. **The route is not a reliable signal at the moment of decision** (the 21:39 first tap). The start watch's external-playback evidence is the second line, but it costs about a second of silence, and that explanation is a hypothesis. *Mitigation:* instrument the decision (log route and external flag at `playLive()`), then see whether the second line ever fires after the first line has been fixed.
4. **A direct start is still 4.6 s**, against 0.5 s on the phone. This design does not change that; the split between the receiver's startup and the stream's is not measured.
5. **Re-planning mid-playback jumps the listener to the live edge.** A listener rewound 3 minutes, who then switches to AirPlay, loses their place. *Mitigation:* accepted; the alternative is the receiver not playing.
6. **Capabilities published early could disagree with a late fall-back** (a recording start that falls back after the controls were published). *Mitigation:* the plan is decided before the item is created, and a fall-back republishes capabilities once; a test asserts at most one change.
7. **The system pausing both devices on a route change** is outside this design's control; it is documented, not fixed.

**For this design.** Three fixes already needed the same fact (where the sound goes); a fourth, for a wearable, would otherwise be a fifth patch found after a listener waits.

## 14. Alternatives Considered

**A. Serve the recording on the phone's LAN address (not loopback) so a receiver can fetch it.** Advantage: rewind keeps working on a receiver. Disadvantage: the phone becomes a server for the whole listening session (the battery cost the owner rejected: *"a massive drain"*), needs the local-network permission and a reachable network path, and fails when the phone leaves the house. Rejected, and it contradicts the aim that the display be independent of the phone.

**B. Turn off external playback so the phone plays and sends audio over AirPlay.** Considered and **rejected by the owner** on battery and independence grounds.

**C. Always play the stream; drop the recording.** Advantage: one path, no plan. Disadvantage: loses rewind, the cushion and the recorder's reconnect behavior on the phone, which are the point of ADR-010. Rejected.

**D. Keep patching per surface (the status quo).** Advantage: no new types. Disadvantage: each new surface fails for 18 to 24 s before it is noticed; three places already decide the same thing. Rejected.

## 15. Future Directions

- **`PlaybackSource` could move into `StationKit`** when the watch app or a glasses companion needs it.
- **A "Connecting…" state** could be shown by every surface while a start is in flight, once capabilities exist.
- **The hub could report start time by surface** (`route` × `plan`), so the 5 s criterion is measured, not asserted.
- **A receiver-side start-time measurement** might split the 4.6 s into the receiver's and the stream's share.
- **Per-surface defaults** (rewind window, buffer size) might differ once more than one surface is observed.

## 16. Open Questions

1. **Unknown routes play the stream (recording only where the phone is positively the source). Agreed?** This is the one decision that changes the default.
2. **When the route moves from the phone to a receiver mid-playback, switching to the live edge is accepted?**
3. **A real car:** the owner's CarPlay sessions came from the display, not a `CarAudio` route. Can one be tried (or the Xcode CarPlay simulator), before `CarAudio` is allow-listed as `.phone`?
4. **A phone call while a receiver plays:** the owner raised it (*"I'd have to pause playback for the entire house"*). Untested; should it be tested now, on the display?
5. **Black / blank Now Playing during the swap** (owner's video, second CarPlay session): only the stall misclassification was fixed (`4873978`); publishing Now Playing from intent (§3, piece 3) is the proposed fix, not yet verified to cover it.
6. **Event fields:** `plan` and `reason` on `liveStart`, provisionally on the development key, then `schema apply`?

## 17. Documentation Strategy

API docs (DocC on the new types); a short narrative section in `LiveRewind.md` ("which surfaces get the recording"); the ADR (§12); `CHANGELOG.md`; the master plan's Known Problems gains this entry and the Roadmap moves it when built. A device-matrix table goes in the session summary after the first run.

---

## Proposal Review Checklist

- [x] Objective and motivation with observed evidence, one-receiver limit stated
- [x] Architecture, files, module placement
- [x] API surface in Swift; schema addition for the hub event
- [x] Compliance (concurrency, privacy, safety); no breaking change
- [x] Resource budget with a measuring test; a coalescing rule for the journal
- [x] Test strategy including an unverified device matrix
- [x] Adversarial review and alternatives, including the two the owner rejected
- [ ] Owner approval of §16 questions 1 to 6
