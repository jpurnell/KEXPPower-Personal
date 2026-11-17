# Design Proposal: live playback that starts and keeps playing through a lost connection

**Status:** PART 1 CHANGES APPROVED 2026-11-17 by the owner (§16, "What would change in Part 1": "I think these changes to Part 1 are smart, and we should make them"). **Parts 2 and 3: direction set, not yet approved as a whole** (measure first, then act; a "Reconnecting…" state is wanted; return to the recording is probably yes; the cycle cap is to be measured too; the cushion is measured through buffered-ahead, not the setting; no exposure data; the hub schema waits for 0.7.0). Part 3's build is held for the hub's `schema apply`; Part 1's changes that need no new wire code are built first (see §16). Part 1 (§3) is already built and committed locally as `df8ae1d`, **before this proposal existed, which the guidelines forbid for a feature of this size** (several components, and a process that stays running while the app is open). This document is the proposal it should have had. It asks the owner to approve, change or reject Part 1 as built, and to approve Parts 2 and 3 before any code for them. Nothing in Parts 2 and 3 is written.

**Facts marked (repo) were read in this repository on 2026-11-17; (log) come from the two diagnostic reports the owner sent from Brawn (`diagnostic-report.json`, generated 2026-11-16T20:10Z, and `diagnostic-report 8.json`, 2026-11-17T13:15Z; times below are UTC); (device) were observed on a device. Anything not observed is marked *unverified*.** No behaviour of `AVPlayer` in this document has been observed in a stall; every statement about it is *unverified* until Part 2's first slice has run on a device.

---

## 1. Objective

When the signal goes, whether before the listener presses play or while they are listening, the app should keep trying to play live and should resume by itself when a connection is viable, without the listener watching their cell signal and knowing when to press play. Where it cannot, it should say why, in the hub, so the next change rests on observation.

**Master Plan Reference:** `project/master_plan.md`, Roadmap Phase 1, "Playback hardening", and Phase 3, "Live rewind" (`LiveRewind.md`, ADR-010); and the owner's report of 2026-11-17: *"If a user is driving and the signal goes out, they shouldn't have to monitor the cell connection and know when to press play."* The master plan's Known Problems gets an entry when this is approved (§17).

## 2. Motivation

**Current situation.** (repo) Live plays through a local recording: `LiveRecorder` reads KEXP's Icecast stream, `LiveRelay` cuts and keeps up to 10 minutes, `LocalHLSServer` serves it on `127.0.0.1`, and `PlayerController` plays that address (ADR-010). If the recording cannot start in 15 s (`LiveTimeShift.start`), the app plays the direct stream. The recorder reconnects forever with a 1, 2, 4, 8, 10 s backoff (`ReconnectBackoff`, `LiveRecorder.swift`).

**What the owner's logs show.**
- **Starts that do not begin (log).** On Nov 16 the local stream was "ready" and the player's item stayed `unknown` (status 0) with the clock at zero: the start requested at 22:46:46 gave audio only after **19.2 s**; 22:50:50 no audio for the 21 s the log runs; 20:06:01 **18.6 s**; 20:04:44 no audio in the 31 s before an archive show was chosen; 22:25:10 **no audio in 41.9 s and the watch gave up**. Playing an archive show, then returning to live, got it going, as the owner described. Before Part 1, nothing rebuilt the item or tried again.
- **Signal loss while listening (log).** The recorder logs `The network connection was lost` and `The request timed out` mid-session (20:10:29, 20:13:15, 22:18:54, 22:27:57 and others) and reconnects; once with `The Internet connection appears to be offline` five times in 14 s (22:27:58 to 22:28:12). Several attempts show gaps of minutes to hours between "connecting" and the next line (for example attempt 7 at 20:19:36, its failure logged at 20:47:15; attempt 11 at 05:29:05 with nothing until the 13:11 relaunch); whether those are the app being suspended or hung requests is *unverified*.
- **The report cannot say what the player did through a drop, because the journal does not record it (repo, log).** `PlayerController.timeControlStatusChanged` writes the player's status to the system `Logger`, not to `DiagnosticLog`: **0 of the 1,161 entries in `diagnostic-report 8.json` are status lines.** So whether the player kept playing through the recorder failures at 20:10:29 and 20:13:15 (it holds up to 10 minutes of recording, but the owner's cushion is **off**, so it sits within seconds of the live edge), stalled and recovered by itself, or was suspended, is **unknown**. This is the first thing Part 3 fixes: it is a gap in what we record, not a finding about AVPlayer.

**Workaround today.** The listener presses play again, or plays an archive show and returns to live. A cushion (Settings, 2 or 5 minutes) bridges a dead zone shorter than itself, **if the listener was already behind live before the signal went** (`LiveRewind.md` §2b); the owner's is off.

**Drawbacks.** In a car, pressing play means looking at the screen; a cushion adds a delay the owner does not use; and the app gave no signal to the hub, so none of this was visible until the owner described it.

## 3. Proposed Architecture

Three parts, each with its own approval: **Part 1** a live-start watch (built); **Part 2** recovery from a stall or failure while playing (new); **Part 3** observation (the events and logs that tell us whether Parts 1 and 2 work).

### Part 1: the live-start watch (as built, `df8ae1d`; for review)

- `LiveStartWatch` (pure): from seconds elapsed, whether the clock is moving and **evidence from the local server and the item** (`LiveStartEvidence`), returns one step at a time and each only once: **8 s** rebuild the player's item *if the player never asked the server for the playlist or got no segment* (a failed item is rebuilt at once; one being given segments is not rebuilt), **18 s** play the direct stream, **45 s** give up. **Revised 2026-11-17 after the owner approved the changes in §16** (the first build rebuilt by the clock alone).
- `LiveStartRunner` runs the watch every 0.5 s (bounded at 120 looks) through a `LiveStartHost` seam, so the sequence is tested with a scripted host; `PlayerController` supplies a host over the player. It writes the player's state and the server's counts (`ServedCounts`, from `LocalHLSServer`) to the journal every two seconds.
- `PlayerController.measureLiveStart` builds the runner; `rebuildLiveItem` serves the recording again at a new address (`LiveShifting.reserve()`, `LocalHLSServer` restart) or reuses the direct link; `playLiveDirectly` drops the recording and plays the stream.
- `NetworkRecovery` (pure) and `NetworkPathObserver` (one `NWPathMonitor`): a start that **gave up** is tried again once when the path goes from unusable to usable, if the listener has not paused or chosen an archive show.
- `liveStart` event (`LiveStart.swift`, schema 5): outcome, duration bucket, network kind, output route; all codes.

**Thresholds are guesses from three observed starts** (log: 18.6 s, 19.2 s and one that never began). They are named constants (`LiveStartWatch.rebuildAfter`, `fallBackAfter`, `giveUpAfter`) so they can move. **A rebuild at 8 s could make a start that would have succeeded at 19 s slower, not faster** (§13).

### Part 2: recovery while playing (new)

**2a. A stall policy (pure).** `StallRecovery` takes what the controller can observe and returns what to do, one action at a time:
- *Inputs:* the player's `timeControlStatus` and `reasonForWaitingToPlay`; the current item's `status` and error (domain and code only); seconds in the stall; the `NetworkKind` and whether it just went from `none` to usable; whether the listener has deliberately paused; actions already taken in this outage; seconds since the last one.
- *Actions:* `wait` (the path is `none`: do nothing but arm), `nudge` (call `play()`; the system may already be resuming), `rebuildItem` (serve the recording again, or reuse the direct link), `restartLive` (stop and start the recording and the item: the existing `recoverLive` path), `giveUp(until: path change)`.
- *Bounds:* after a path change to usable, `nudge` at once, `rebuildItem` after 8 s of no progress, `restartLive` after 18 s; then at most one more cycle every 30 s while the path stays usable; **at most 10 cycles per outage**, after which it waits for the next path change only. No action while the path is `none`.
- *Deliberate pause:* the controller marks a pause **the listener caused** (remote command, button) apart from one the system caused (interruption, route loss). A listener's pause cancels recovery and clears the outage; a system pause is resumed by `AudioSessionCoordinator` as it is today and is not this feature's business.

**2b. Observing the player (`PlayerController`).** Observe `timeControlStatus` (already), `AVPlayerItem.status`, and the notifications `AVPlayerItemPlaybackStalled`, `AVPlayerItemFailedToPlayToEndTime` and `AVPlayerItemNewErrorLogEntry` (names to be checked against Apple's documentation at implementation; not confirmed here), feeding `StallRecovery`. One stall record per outage: start, end, reason codes, actions taken, outcome.

**2c. The recorder reacts to the path.** `NetworkPathObserver` lets `LiveRecorder` end a backoff wait or a hung request as soon as the path goes from unusable to usable, instead of waiting out up to 10 s or the 15 s idle timeout. (The recorder already retries; this shortens the gap and is the smallest change.)

**2d. Starting with no coverage.** If `LiveTimeShift.start()` gives no audio in 15 s the direct stream is played (as now); with no path it will not play either, so Part 1's give-up and network retry apply. Part 2 makes that retry also apply when the *direct* item later fails.

**2e (optional, owner's choice, Q1): an automatic cushion.** When the path is cellular or the recorder has failed recently, hold the player a small distance behind live (the `Cushion` machinery exists) so a short gap is not heard. This trades latency for continuity and changes what "live" means to the listener; it is **not** in the recommended scope.

### Part 3: observation (BUILT 2026-11-17: the observation layer; see "As built")

**First real dead-zone stall, Brawn untethered, 2026-11-17 (journal + hub; one observation, not a result).** The stream connection dropped at 20:03:37; reconnects failed offline from 20:03:38 to 20:03:53; the player kept playing on already-recorded audio until 20:03:54 (about 17 s with the cushion off), then stalled (reason networkLost, ahead none, network none); the network returned at 20:04:04, the recorder's first bytes took 6.7 s after it reconnected, audio moved at 20:04:11, and the stall ended at 20:04:12 as resumed, 15 to 40 s bucket (about 18 s). The event reached the hub as a provisional `playbackStall`. **Two lessons.** (1) The audible gap (18 s) is the outage (33 s) minus the audio the player already had (17 s). `playbackStall` measures the audible part, so **outages the buffer absorbs are never reported, and a dataset of stalls alone is biased against exactly the question the cushion analysis asks** (what fraction of outages would a 2 or 5 minute cushion bridge). The connection outage itself has to be observed at the recorder, whether or not it was heard: when the connection was lost, how long until bytes returned, and how much audio the player still had at the loss. Proposed as a `streamOutage` event (§16 Q11). (2) After the network returned, most of the wait was the first bytes arriving (6.7 s), not the retry timer; a path-aware retry (2c) would not have saved much here, which is a data point against over-building 2c. Also heard, not yet verified: the station's pre-roll ID replays when the recorder reconnects (a new connection starts with it and it is recorded into what the player plays).

**As built (2026-11-17).** `PlaybackStall.swift` (the types, `StallObserver`, `OutageMarker`), `StallRunner.swift` (watches one stall second by second), the `playbackStall` event and schema version 6 in `project/diagnostics/spinner-schema.json`, and the wiring in `PlayerController` (every `timeControlStatus` change with its waiting reason, item status and network in the journal; a runner started when the player waits after having played; the listener's pause told from a stall; archive starts and seeks not counted as stalls; a stall still open when the app stops written to a marker and reported at the next launch as `unfinished`). It observes only: it changes nothing the player does, and `cycles` is 0 until Part 2. 51 new tests; the controller's wiring is verified on a device, not by unit tests (§11). **Deviations, recorded:** (1) the stall's duration uses a new `OutageDuration` with edges at 120 and 300 s, and the live start keeps its own `StartDuration`, because the hub's registered schema 5 does not know the new codes and would refuse every `liveStart` over 40 seconds; the finer start buckets still wait for schema 6; (2) a stall must outlast one second (sampled every second, one sample of waiting cannot be told from a chunk boundary), so reported stalls begin at about two seconds; (3) **the hub does not register `playbackStall` yet: it is tried provisionally** (a Debug build's development key, the app's `provisional` policy on the hub), so its shape can still change; once it has settled, schema 6 is applied with `schema apply` and the kind is promoted; (4) severity by outcome: resumed and listenerPaused info, rebuilt, restarted and unfinished warning, gaveUp error.


- **Events (schema 6):** `playbackStall`: `reason` (a code: `networkLost`, `bufferEmpty`, `itemFailed`, `localServer`, `unknown`), `took` (buckets with edges at 120 s and 300 s, the cushion lengths), `ahead` (audio buffered ahead of the playhead when the stall began, bucketed), `network`, `route`, `outcome` (`resumed`, `rebuilt`, `restarted`, `gaveUp`, `listenerPaused`, `unfinished`), `cycles` (an int 0 to 50: the cap is measured, so changing it must not need a schema change). All codes or a bounded int; no names, no addresses.
- **Measuring the cushion, with statistics the hub can stand behind (owner's question, 2026-11-17).** The question the data must answer is: *what fraction of real outages would a 2-minute or a 5-minute cushion have bridged?* That is the survival function of outage length, `P(outage > c)`, read at c = 120 s and 300 s. Three design points follow.
  - **Duration buckets with edges at the cushion lengths.** `took` gets `from40to120`, `from120to300` and `over300` (replacing the coarse `over40`/`over120` of the first draft), so 120 s and 300 s are bucket edges. Additive for `liveStart` too.
  - **What the app can and cannot say about the cushion.** The cushion *setting* is a setting, and the privacy line is "health, not behavior" (no show, song, station or setting travels). So the event does **not** carry the setting. It carries `ahead`, **how much audio was buffered ahead of the playhead when the stall began** (`none`, `under30`, `from30to120`, `from120to300`, `over300`), a fact about playback health. That is the quantity that decides whether an outage was audible, and it answers the cushion question without recording a preference (Q9).
  - **Unfinished outages are censored data, not missing data.** An outage that ends because the app is killed or suspended has no end event, and leaving it out biases every estimate toward short outages. The app writes an *open-outage marker* (as `RunMarker` does for runs); at the next launch it reports that outage once with outcome `unfinished` and the longest duration it observed. The hub treats `unfinished` as right-censored.
  - **Hub side (separate change, in the hub repository).** The analysis the hub already does uses BusinessMath for every statistic (Wilson intervals, a Poisson tail; `Analysis.md` §3.0, "statistics come from BusinessMath, and only from there"). The cushion analysis is the same kind of work: a **Kaplan–Meier estimate of outage length with a confidence band**, and from it the share bridged by 120 s and by 300 s with an interval. BusinessMath has `KaplanMeier`, `SurvivalCurve`, `quantile` and `empiricalCDF` in its source tree (seen by file listing in the hub's checkout; **their signatures and whether they handle censoring and give intervals are not verified here**, and any missing piece is added to BusinessMath, not to the hub). It needs its own hub proposal; this one only fixes what the app must send.
  - **What the data will not support yet.** Today the owner's phone is the only sender, so *n* is a handful, and the hub's small-cell rule (under 5) suppresses it by design. Senders are **opted-in** listeners, so any estimate describes opted-in listeners, not all of them. A *rate* (stalls per listening hour) needs an exposure denominator, which is listening time, which is behavior (Q10). The conditional answer ("given a stall, how long?") needs no denominator and is what this measures.
- **Local log:** **every `timeControlStatus` change with its waiting reason and the item's status, which the journal does not record today (§2)**, and each action and outcome, as fixed phrases in the on-device journal (category `Player`). Status changes are bounded by coalescing repeats; actions by the 10-cycle cap, so a long outage cannot flood it.
- Registration: the hub must know schema 6 before a build that sends it ships; with the hub's `SchemaEvolution` 0.7.0 that is `schema apply`; until then it is the manual edit and restart.

**New files:**
- `KEXPPower SwiftUI/Diagnostics/StallRecovery.swift` (pure policy and its types)
- `KEXPPower SwiftUI/Audio Player/PlayerStallObserver.swift` (the AVFoundation observation, kept out of `AVPlayer.swift`, which is 649+ lines)
- `KEXPPowerAppTests/StallRecoveryTests.swift`, `PlayerStallObserverTests.swift`
- `project/decisions/ADR-011-live-recovery.md`

**Modified files:** `AVPlayer.swift` (feeds the observer and policy; marks listener pauses), `LiveRecorder.swift` (path-aware wait), `FieldEvent.swift`, `LiveStart.swift` (shared bucket types), `project/diagnostics/spinner-schema.json` (version 6), `FieldEventTests.swift`.

**Module placement:** the iOS app target and, because `FieldEvent` and `LiveStart` are shared, the Mac and TV targets (`LiveStart.swift` already compiles on all three, checked 2026-11-17). Pure policies carry no AVFoundation import. The watch app has its own player (`WatchPlayer.swift`) and is **out of scope**.

## 4. API Surface

```swift
/// What to do about a stall, from what can be observed. Pure: no clock, no AVFoundation.
struct StallRecovery: Sendable {
    enum Action: Sendable, Equatable { case wait, nudge, rebuildItem, restartLive, giveUp }
    struct Observation: Sendable, Equatable {
        var network: NetworkKind
        var networkJustReturned: Bool
        var secondsInStall: TimeInterval
        var itemFailed: Bool
        var listenerPaused: Bool
        var secondsSinceLastAction: TimeInterval
    }
    static let rebuildAfter: TimeInterval = 8, restartAfter: TimeInterval = 18, cycleInterval: TimeInterval = 30
    static let maximumCycles = 10
    mutating func observe(_ observation: Observation) -> Action
    var cyclesUsed: Int { get }
    var outcome: StallOutcome { get }   // resumed / rebuilt / restarted / gaveUp / listenerPaused
}

enum StallReason: String, Sendable, CaseIterable { case networkLost, bufferEmpty, itemFailed, localServer, unknown }
enum StallOutcome: String, Sendable, CaseIterable { case resumed, rebuilt, restarted, gaveUp, listenerPaused, unfinished }

struct PlaybackStall: Sendable, Equatable { let reason: StallReason, took: StartDuration, ahead: AheadBucket, network: NetworkKind, route: OutputRoute, outcome: StallOutcome, cycles: Int }
enum AheadBucket: String, Sendable, CaseIterable { case none, under30, from30to120, from120to300, over300 }
// FieldEvent gains: case playbackStall(PlaybackStall)

/// The recorder's wait ends early when the path returns.
protocol PathSource: Sendable { func updates() -> AsyncStream<NetworkKind> }   // NetworkPathObserver conforms; tests give a fake
```

## 5. MCP Schema

**N/A for an app screen or player.** The app has no MCP surface. The machine-readable contract is the **wire schema** the hub validates (`project/diagnostics/spinner-schema.json`, as for every event). Version 6 adds:

**REQUIRED STRUCTURE (the kind, as the schema file holds it):**
```json
{
  "name": "playbackStall",
  "channels": ["development", "testFlight", "appStore"],
  "fields": [
    { "name": "reason",  "isRequired": true, "type": { "type": "code", "allowed": ["networkLost", "bufferEmpty", "itemFailed", "localServer", "unknown"] } },
    { "name": "took",    "isRequired": true, "type": { "type": "code", "allowed": ["under2", "from2to5", "from5to15", "from15to40", "from40to120", "from120to300", "over300"] } },
    { "name": "ahead",   "isRequired": true, "type": { "type": "code", "allowed": ["none", "under30", "from30to120", "from120to300", "over300"] } },
    { "name": "network", "isRequired": true, "type": { "type": "code", "allowed": ["none", "wifi", "cellular", "wired", "other"] } },
    { "name": "route",   "isRequired": true, "type": { "type": "code", "allowed": ["carPlay", "airPlay", "bluetooth", "headphones", "speaker", "other"] } },
    { "name": "outcome", "isRequired": true, "type": { "type": "code", "allowed": ["resumed", "rebuilt", "restarted", "gaveUp", "listenerPaused", "unfinished"] } },
    { "name": "cycles",  "isRequired": true, "type": { "type": "int", "min": 0, "max": 50 } }
  ]
}
```
**Parameter types:** `code` is one of the listed tokens; `cycles` is an integer 0 to 50. No dates (the event's time is the envelope's, ISO 8601, as for every kind). No free text from any channel. **The new `took` edges (`from40to120`, `from120to300`, `over300`) replace `over40` in `liveStart` too**: `over40` stays valid for old builds, so the change is additive (codes added, none removed), which the hub's `schema apply` accepts.

## 6. Constraints & Compliance

- **Concurrency:** `StallRecovery`, `PlaybackStall` and the enums are Sendable value types; the observer and controller stay `@MainActor`; the one new task (the path loop) is awaited through an isolated method, not a `Task` that touches actor state (the gate flagged that pattern on 2026-11-17 and it was fixed that way).
- **Bounded:** every loop has a bound and a cancellation check (the gate flagged `while true` on 2026-11-17); at most 10 cycles per outage, one cycle per 30 s, so a tunnel is not a retry storm and a flat battery is not the cost of a dead zone. The thresholds are named constants (`no_hardcoded_constants.md`).
- **Safety:** no force unwraps, `try!` or `as!`; no division without a guard; `AVPlayerItem` errors reduced to domain and code before they leave the observer.
- **Privacy:** every event field is a code or a bounded int; no names, no addresses, no device names (`OutputRoute` maps a port type to a kind and an unknown one to `other`, tested). Opt-in consent gates sending as for every event.
- **Listener intent:** a pause the listener makes is never overridden; an archive show is never replaced by a live retry.

## 7. Source & API Compatibility

**Breaking changes:** none outside the app. `LiveShifting` gained `reserve()` in Part 1 (internal protocol; its one test double was updated). `FieldEvent` gains a case (exhaustive switches in the app and tests updated). The wire schema change is additive (§5).
**Incremental adoption:** Part 3's observation can ship before Part 2's recovery: observe first, then act.
**Type-checking risk:** none; no overload of an existing function with the same labels.

## 8. Backend Abstraction

N/A: not compute-intensive.

## 9. Resource Budget

**Data held:** one `NWPathMonitor` and its latest `NetworkKind` (a few hundred bytes); one observation task and one path task; a `StallRecovery` value (about 100 bytes); one stall record per outage. The recording window is unchanged: up to 10 minutes, about **12 MB on disk at 160 kbps** (ADR-010, measured then), cleared at app start and stop.
**Growth:** none from this feature. The on-device journal (`DiagnosticLog`) rotates at 256 KB per file and keeps 14 days; the cap of 10 cycles bounds a stall to about 30 lines, so a pathological day of dead zones adds well under 100 KB.
**Budget:** at rest **no more than 1 MB resident added** to the app; peak the same (no buffers). Recording window as ADR-010.
**Measured by:** a test that runs 1,000 simulated outages through `StallRecovery` and asserts the journal stays under 256 KB; `footprint` of the app on Brawn before and after a Network Link Conditioner session of 30 minutes of cycling signal, recorded in the session summary.
**Lifetime:** the app plays for hours in the background. No state accumulates across outages; the outage record is cleared when audio moves for 10 s.

## 10. Dependencies

**Internal:** `PlayerController`, `AudioSessionCoordinator`, `LiveRecorder`, `LiveRelay`, `LocalHLSServer`, `LiveTimeShift`, `NetworkPathObserver` and the `LiveStart.swift` types, `FieldDiagnostics`, `DiagnosticLog`, `Cushion`.
**External:** none new (AVFoundation and Network are system frameworks already used). **Hub:** schema 6 must be registered before a sending build ships (`SwiftDiagnosticsHub` `SchemaEvolution.md`, 0.7.0, or by hand).

## 11. Test Strategy

**Test categories:**
- **Golden path (pure):** the traces below through `LiveStartWatch` and `StallRecovery`.
- **Edge:** a stall that ends at once; the path returning at the same instant the item fails; a coarse observation that skips a threshold (the later step is still taken, once); ten cycles then `giveUp`; time going backwards or `NaN` (treated as zero).
- **Invalid / hostile:** a listener's pause mid-cycle cancels everything; a stall while an archive show plays does nothing; `reserve()` returning `nil`; the path flapping 100 times in a second causes at most one `nudge`.
- **Determinism:** the policy has no clock; tests pass seconds in.
- **Seam for the player:** a narrow protocol over the parts of `AVQueuePlayer` the controller uses (current item, status, `play`, `currentTime`, replacing items) so a fake can simulate a stall without audio; `PathSource` as above. **A stall cannot be simulated with a real `AVPlayer` in a unit test, so the controller's wiring is verified on a device (below), not claimed from unit tests.**
- **Device matrix (Brawn, then a car):** airplane mode on before pressing play; on mid-play with cushion off; on mid-play with a 5-minute cushion; Network Link Conditioner "100% loss" for 30 s, 2 min and 10 min; CarPlay simulator and a real head unit; screen locked throughout. Each run's journal and hub events are kept.

**Reference truth:** the owner's two diagnostic reports (real device logs, 2026-11-10 to 2026-11-17), the playlist generator in `LiveBuffer.playlist()` (a live playlist with no end marker and discontinuity tags, repo), and Apple's documentation for the `AVPlayer` and `AVPlayerItem` properties and notifications named in §3, **to be read at implementation; not read for this proposal**. Expected values are derived from those logs and from the constants, not recalled.

**Validation Trace (REQUIRED):**
- **Part 1, from the log.** Request at 22:25:10, clock never moves. `LiveStartWatch`: at 22:25:18 (8 s) → `rebuild`; at 22:25:28 (18 s) → `fallBackDirect`; at 22:25:55 (45 s) → `giveUp`, outcome `gaveUp`. (The log's 40 s cut-off gave up at 22:25:51.) Whether the rebuild or direct stream *would have started* is **unknown**: it is what the device matrix measures.
- **Part 1, from the log.** Request at 22:46:46, audio moves at 19.2 s. With the watch: 8 s → `rebuild`, 18 s → `fallBackDirect`; the start that succeeded unaided at 19.2 s is **changed by the recovery**, and may now take longer. This is the risk in §13.
- **Part 2.** Playing; path `wifi` → `none` at t=0, stall begins; `StallRecovery` returns `wait` at every observation until t=37 s when the path becomes `cellular` (`networkJustReturned`) → `nudge`; at t=45 s (8 s later, still no progress) → `rebuildItem`; at t=55 s (18 s after return) → `restartLive`; at t=85 s → cycle 2 `nudge`. `cyclesUsed == 1` after the first full cycle; after 10 cycles `giveUp`. If audio moves at t=39 s: outcome `resumed`, `took` bucket `from15to40`, `cycles` 0.
- **Event.** `PlaybackStall(reason: .networkLost, took: .from15to40, ahead: .none, network: .cellular, route: .carPlay, outcome: .resumed, cycles: 0)` encodes to exactly the seven fields in §5 and passes the schema validator on all three channels.

## 12. Architecture Decision Review

**ADR Check:**
- [x] Reviewed `project/decisions/`: ADR-001 (keep the fork), 002 (library in its own repo), 003 (single Now Playing publisher), 006 (StationKit and adapters), 009 (archive on StationKit), **010 (live rewind by local recording)**.
- [ ] Supersedes an existing ADR? **No.**
- [x] **Amends ADR-010? Yes, in one respect.** ADR-010: "Live is always played through this [the recording]… any failure to start the recorder or server plays the direct stream as before." This proposal lets the app **drop to the direct stream mid-recovery** (Part 1 at 18 s; Part 2 `restartLive`), and asks whether it should **return** to the recording when the connection is stable again (Q3). ADR-010's text does not say what happens after a fallback; today the fallback lasts until live is restarted.
- [x] New ADR required: **ADR-011**, drafted below.

**New ADR Draft:**
- Title: Live recovery is driven by observed playback state and the network path, with bounded retries.
- Category: architecture / reliability.
- Key decision: the app decides to rebuild, restart or fall back from what the player and the path report, in pure policies with named constants; it never overrides a listener's pause or an archive show; retries are capped per outage; each outage is reported as one typed event.

## 13. Adversarial Review

**Strongest case for a different approach:** *use the cushion, not recovery code.* The owner's own design for a dead zone (`LiveRewind.md` §2b) is to stay behind live: with a 5-minute cushion the player never stalls for a tunnel, with no timers, no policy, and nothing for the app to get wrong; ADR-010 recorded it playing through two minutes of airplane mode. A reviewer would say recovery logic around `AVPlayer` is complex, device-dependent and hard to test, and that the cushion is the proven answer. **Why that is not enough:** a cushion cannot be built once the signal has gone, it cannot help a *start* with no coverage (the log's 41.9 s case), it adds a delay the owner does not use (their cushion is off), and it hides a stuck player rather than fixing one. It is a good complement (2e, Q1), not a replacement for either.

**Where this design is most likely wrong:**
- *AVPlayer's own behaviour is unobserved, and the journal could not have shown it (§2).* The design assumes a stall ends in `waitingToPlayAtSpecifiedRate` and resumes when audio returns, and that a live playlist whose last segment stops advancing eventually *fails* the item rather than waiting forever. **Neither is confirmed.** If AVPlayer already recovers by itself in most cases, Part 2 adds only risk; if it fails the item with a code we have not seen, the policy needs that code. This is why Part 3 (observe) ships and runs **before** Part 2 acts.
- *The thresholds were fitted to three logs.* 8, 18 and 45 s could be too eager (the 19.2 s start above would be disturbed) or too slow. They are constants for that reason; the device matrix and the hub's `liveStart` buckets decide them.
- *Background execution.* Retries run only while the app is alive. Whether a stalled-but-wanted player keeps the app running in the car, and whether `NWPathMonitor` delivers while the app is suspended, is *unverified*; if not, recovery cannot run in the background and the design must lean on the system resuming playback.
- *A rebuild fights the system.* Replacing the item restarts HLS loading; done during a stall AVPlayer would have recovered from, it could make things worse.

**What an experienced critic would say:** "You are stacking timers on a player that already retries internally, and you tuned them on three logs." **Why we proceed anyway, narrowed:** observation first (Part 3 before Part 2's actions), recovery behind named constants, a hard cap on retries, and device runs before anything is called fixed; Part 1 as built is offered for the owner to keep, revise or revert.

## 14. Alternatives Considered

**1. Do nothing in the app; rely on the cushion.** *(The strongest; see §13.)* Advantage: no code. Disadvantage: does not help a start without coverage or a listener without a cushion. Not preferred alone.

**2. `URLSession.waitsForConnectivity = true` in the recorder** (the system waits for a path, then proceeds). Advantage: a one-line change that removes the recorder's blind retries. Disadvantage: it gives no visibility, does not touch the *player's* item (the direct stream, or a stalled local one), and its wait semantics under a 15 s idle timeout are *unverified*. Could be combined with 2c; not a substitute for Part 2.

**3. An automatic cushion by connection quality (2e).** Advantage: the listener never hears a short gap. Disadvantage: changes what "live" means, costs latency, and decides for the listener. Kept as an open question, not the recommendation.

**4. Ask KEXP for an HLS live stream with its own window.** Open in ADR-010 and out of our hands; would remove the local recorder and most of this.

**5. Show a "Reconnecting…" state and leave recovery to the listener.** Advantage: honest, small. Disadvantage: it is the problem the owner described (a car, a screen to look at). Could be added to Part 2 (Q5).

**6. Stop retrying after a fixed time.** Rejected as the only bound: a listener who comes out of a tunnel after 20 minutes should still get audio. The cap is on cycles per outage and per time, and a path change resets it.

## 15. Future Directions

- **An automatic cushion** might be offered when the path is cellular or recently unreliable.
- **A visible "Reconnecting…" state** in the player bar, the lock screen and CarPlay's Now Playing might show a stall instead of a paused button.
- **Return to the recording** after a direct fallback might happen when the connection has been stable for a while.
- **The watch app** might adopt the same policy (it needs 35 to 40 s on a cold network today, per the master plan).
- **A shared policy package** might hold `StallRecovery` and `LiveStartWatch` for other stations built on StationKit.

## 16. Open Questions

**Answered by the owner 2026-11-17** (the owner's numbering ran one behind this list from item 4; the mapping below is my reading and Q4 and Q6 are to be confirmed):

1. **Cushion: measure it.** The owner asked whether the cushion should be recorded so that decisions are statistically backed, and noted this is a prime place to show the hub's BusinessMath integration. **Decided: yes, measure; the design is in §3 Part 3** (buckets with edges at 120 s and 300 s, a buffered-ahead field, censoring, a Kaplan–Meier analysis on the hub). Whether recording the *setting* itself is acceptable is Q9. No automatic cushion is built; the data decides whether to propose one.
2. **Thresholds: measure.** The owner: "measurement is our friend." **Decided:** the 8, 18 and 45 s and 8, 18 and 30 s values are starting points, tuned from the device matrix and from `liveStart` and `playbackStall` buckets, not from three logs.
3. **Return to the recording after a direct fallback: "probably, yes."** **Decided in principle** (amends ADR-010 as §12 says); the rule for *when* (for example, the path has been usable for a set time) is part of Part 2's design and is measured like the rest.
4. **Cycle cap: measure it too.** The owner: "I meant to measure the cycle cap as well." **Decided:** the cap (10 cycles, one per 30 s) is a starting value, not a rule. The event's `cycles` field is widened to 0 to 50 so a different cap needs no schema change, and the hub's analysis reads how many cycles outages actually needed. My earlier reading of the owner's "reassuring" reply as being about the cap was wrong; it was about item 5.
5. **A "Reconnecting…" state: yes** ("reconnecting was meant to be the reassuring item"). **Decided in principle.** It is a UI change and needs a state matrix (`ui_testing.md`) and its own small section before it is built: *playing*, *reconnecting (no network)*, *reconnecting (network back, recovering)* and *could not reconnect*, and in each the button, the lock screen and CarPlay Now Playing must be defined.
6. **Part 1 as built: the changes below are approved** ("smart, and we should make them"). Built 2026-11-17 in the order given, with one deferral stated under the list.
7. **Order: observe first.** **Decided.** Part 3 ships and runs before Part 2 acts. Part 1's actions (already built) are not part of this decision: see "What would change in Part 1".
8. **Hub schema: wait for 0.7.0.** **Decided.** No schema is registered by hand. Part 3's build is held until the hub has `schema apply`, or ships with the event refused and dropped by the hub, which is **not** acceptable; so it waits.

**New, from the owner's questions:**

9. **DECIDED 2026-11-17: use buffered-ahead; the setting is not recorded** ("if we can get it from buffered ahead, let's use that"). *The question was:* may the event carry the cushion *setting* (off, 2 or 5 minutes)? The privacy line has been "health, not behavior": no setting travels. The design above avoids the question by sending buffered-ahead, which is playback health. Recording the setting would be a small, coarse exception that would let the hub compare people who chose a cushion with those who did not. (Recommended: do not; the buffered-ahead field answers the cushion question.)
10. **DECIDED 2026-11-17: the recommendation; no listening-time data, conditional analysis only.** *The question was:* exposure. A rate ("stalls per listening hour") needs listening time, which is usage, a line the owner has held ("health, not behavior"; usage analytics deliberately not added). The conditional analysis does not need it. May a coarse per-day live-listening bucket be added to `dailyMetrics`, as an opt-in tier, or is the conditional analysis enough? (Recommended: enough, for now.)

11. **A recorder-level `streamOutage` event** (found by the first real stall, Part 3 above): when the recorder loses the stream, how long until bytes return (`OutageDuration` buckets), how much audio the player had at the loss (`AheadBucket`), the network, and whether it was `covered` (the player never stalled) or `stalled`. It makes outages the buffer absorbed visible, which the stall event cannot. Open: build it, and tried provisionally first like the stall? (Recommended: yes, provisionally.)
12. **The station pre-roll on reconnect:** confirm from a journal that it replays, and decide whether to detect and skip it. Not designed.

### What would change in Part 1 (answer to the owner's question)

Part 1 is built and committed locally (`df8ae1d`), untested on a device. Changes I would propose, none made:
- **Decide the rebuild from evidence, not only a clock.** Today it rebuilds at 8 s whatever is happening. The local server can count the requests it has served: *zero requests* means the player never reached it (the listener may be dead or unreachable: rebuild, or restart the server); *a playlist request but no segment* means something else. That one counter would tell the three explanations of the Nov 16 stalls apart and costs a few lines. Until it has data, the rebuild could disturb a start that would have succeeded (the 19.2 s start in §11).
- **Record the evidence at every tick of the watch** in the journal and in the event: the item's status, whether the player has fetched the playlist, and the server's request count (codes and a small int).
- **Use the finer duration buckets** (§3 Part 3) so starts and stalls are measured on one scale.
- **Stop sending two events for one give-up.** `watchLiveStart` sends `rewindUnavailable(.gaveUpWatching)` and a `liveStart` with `gaveUp`. The first is older and the hub's dashboards read it; the second says more. Keep both until the dashboard reads `liveStart`, then drop the first? (Owner's call.)
- **Put the wiring under a seam** so a fake player can drive the watch in a test; today only the pure policy is tested and the controller is verified only by hand.
**Deferred, with the reason:** the finer duration buckets and the evidence *in the event* both need new wire codes, which the hub does not accept until schema 6 (hub 0.7.0, which is first). Sending them now would have the hub refuse and drop the event. So the **journal** carries the evidence now and the **event** carries it with schema 6, in the same build as Part 3. The evidence-based rebuild and the test seam need no wire change and are built now.

- **Optionally gate the actions behind a flag** while measuring, so the first runs on a device observe rather than act. This is the one change that contradicts "Part 1 is built to fix a failure we saw", so I recommend **not** doing it: the logs show a start stuck for 41.9 s with no recovery; the recovery can only help that case, and the buckets will show whether it disturbs the 19 s case.

## 17. Documentation Strategy

**Documentation Type:** Narrative Article Required.

**Complexity Threshold Check:**
- Does it combine 3+ APIs? **Yes** (the watch, the stall policy, the path observer, the recorder, the player).
- Does explanation require 50+ lines? **Yes** (the states, the bounds and why they are what they are).
- Does it need theory/background context? **Yes** (what a cushion can and cannot do; why recovery cannot recover missed audio).

**Article:** `project/docs/technical/LiveRecoveryGuide.md` (matches no Swift symbol). Also: DocC comments on every new type; ADR-011; the master plan's Known Problems entry and Current Status; the capability map; `CHANGELOG.md`; and a note in `LiveRewind.md` §2b pointing here. **Missing audio is never recovered**, and the article says so in its first paragraph.

---

## Proposal Review Checklist

### Architecture
- [x] Module placement follows the project structure (pure policy in `Diagnostics/`, AVFoundation in `Audio Player/`)
- [x] API design follows naming conventions
- [x] Concurrency model is Swift 6 compliant (Sendable values, `@MainActor` controller, no actor state touched from a `Task`)
- [x] Generic constraints: N/A
- [x] No forbidden patterns (no force unwraps, bounded loops, capped retries)
- [x] Usage examples: the app has none; the proposal's traces serve (§11)

### Compatibility & Evolution
- [x] Source compatibility assessed (§7)
- [x] Adoption path documented (observe first)
- [x] Future directions without commitments
- [x] Alternatives with a fair assessment: six, including the strongest (the cushion)

### MCP Readiness
- [x] N/A stated; the wire schema is the machine-readable contract (§5), with a REQUIRED STRUCTURE example, all parameter types, enums exhaustive, no dates

### Backend Abstraction
- [x] N/A (§8)

### Resource Budget
- [x] Data and growth named
- [x] Held versus streamed stated
- [x] Budget as numbers (1 MB added; window as ADR-010's 12 MB)
- [x] Measurement identified (journal test, `footprint` on Brawn)
- [x] No budget above a few hundred megabytes

### Testing & Dependencies
- [x] Test strategy covers golden path, edge, invalid, determinism, and says what unit tests cannot show (a real stall)
- [x] Reference truth identified: the owner's logs, the playlist generator, Apple's documentation **to be read at implementation (not read here)**
- [x] Dependencies acceptable (none new; hub schema 6 is a dependency)
- [x] Open questions resolved or deferred explicitly: all ten answered by the owner 2026-11-17 (Q5's UI state and Q3's return-to-recording rule each need a short section before they are built)

### Adversarial Review
- [x] Counter-design articulated (§13 and Alternative 1)
- [x] Failure modes named (AVPlayer behaviour unobserved; thresholds fitted to three logs; background execution; a rebuild fighting the system)
- [x] Critic's objection captured in one sentence, with the response
