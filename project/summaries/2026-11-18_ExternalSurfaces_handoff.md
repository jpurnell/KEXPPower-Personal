# Session Summary: ExternalSurfaces (live playback to the Kitchen display, CarPlay, AirPlay receivers) and handoff

| Date | Phase | Status |
| :--- | :--- | :--- |
| 2026-11-17 to 2026-11-18 | Live-playback reliability and external surfaces (proposal `project/plans/proposals/ExternalSurfaces.md`, ADR-011) | COMPLETED for what was asked; items below are open and unverified |

## 1. Core Objective

Make live KEXP play reliably to surfaces other than the phone: the owner's Kitchen home display (an AirPlay receiver that presents CarPlay views), HomePods, a real car, and later wearables, which the owner expects to use the same method (*"so I want to get it right now"*).

## 2. Design Decisions

- **The recording is for the phone only** (ADR-011, amends ADR-010). A receiver cannot reach the phone's `127.0.0.1` recording, so on a receiver or an unknown route live plays the stream itself. Rejected: serving the recording over the LAN (the owner: the display is *"meant to play indefinitely in the home"*; it would drain the phone and not be independent of it). *"Unknown plays the stream is the right fallback."* *"Live edge is right"* when the sound moves to a receiver mid-play.
- **Pause follows the system** (switching a receiver to "iPhone Speaker" pauses both devices; Apple News does the same). An ignore-pause rule was built (`fa289f9`) and withdrawn; the logging stayed.
- **A direct item is made fresh, with the track's metadata on it**, because the display did not show metadata edited into the launch item.
- **A lost live item is put back without a press**, capped at three tries without audio between.
- Process note: `664c9af` and `7263e45` were built before the proposal existed, against the project's design-first rule; the proposal says so. The remaining slices were built after "let's build".

## 3. Work Completed

Commits (all pushed; `swiftui_example` equals origin at `cf52d1f`): `0693128` restart after a long outage (play puts the item back), `4873978` server counts misses / returning to live is settling, `e151e3b` start environment journaled, `664c9af` AirPlay plays the stream, `7263e45` handoff fallback, `fa289f9` (withdrawn rule), `ff1ea3a` session actions and route changes journaled, `d155fc5` the proposal, `9575285` live item carries metadata and artwork outcome journaled, `156845c` both Now Playing paths from one snapshot, `89eeaa4` unknown plays the stream, `fbf4b1d` `PlaybackSource` / `LivePlan` / `PlaybackCapabilities` / route re-plan / start phases, `65f872f` fresh direct item with metadata, `80de9e6` FaceTime Audio verified, `cf52d1f` lost item put back.

- Tests added across `PlayerControllerTests`, `LiveStartWatchTests`, `LiveStartRunnerTests`, `LiveTimeShiftTests`, new `LivePlanTests`. Count: 534 at the 2026-11-14 handoff, **643 passing** now.
- New file: `KEXPPower SwiftUI/Diagnostics/PlaybackSource.swift` (cloned into the pbxproj for 3 app targets and 2 test targets; new files must be added the same way).
- Docs: ADR-011, ADR-010 pointer, `ExternalSurfaces.md` (status, as-built, §12, Q4), `LiveRewind.md` §10, master plan (What's Working, Known Problems, Last Updated), `project/capability_map.md` (new area; still partial), CHANGELOG (Unreleased).

## 4. Mandatory Quality Gate

Run before each commit; last run at `cf52d1f`: **PASSED, 51 of 51 checkers, 0 errors, 0 warnings**, 1 acknowledged `// Justification:` (concurrency, pre-existing), 0 suppressed. The gate skips `build`, `test` and `doc-*` (no `Package.swift`); the app's tests were run with `xcodebuild test` on the "iPad Air 13-inch (M4)" simulator: 643 pass. Complexity notes (informational, not findings) include `playLive` at 18 and `LiveStartRunner.run` at 25 against a threshold of 15.

## 5. Project State Updates

- No `project/checklists/CURRENT_*.md` exists (none active), so none was updated.
- `project/master_plan.md`: updated. `project/capability_map.md`: updated (a new area; the map remains partial, as it says).
- Release housekeeping NOT done, because nothing was released: no tag; the 3.6.0 reconciliation noted in the 2026-11-14 handoff is still outstanding.

## 6. Next Session Handover

### Immediate starting point

Nothing is in flight. If continuing this area, start with **measurement, not code**: collect about twenty live starts per surface (the display, a HomePod, the phone) from the journal's `live start: phases item ready at …, playing at …, audio at …` lines, then decide on tuning (`automaticallyWaitsToMinimizeStalling`, `preferredForwardBufferDuration = 300` on the direct item, preconnect). Baseline so far: display 4.6, 4.8 and 6.2 s (3 starts); item ready and playing at 0.5 s every time, so the rest is the receiver's.

### How to read the device journal (not written down elsewhere)

`xcrun devicectl device copy from --device 00008130-000E385E10C1401C --domain-type appDataContainer --domain-identifier com.JPEnterprises.Spinner --source "Library/Application Support/Diagnostics/journal" --destination <dir>/j`, then read the newest `spinner-*.jsonl` (JSON lines, `time` is epoch seconds, `fields.message`). `spinner-log.txt` beside it is stale (November 9). Collapse the `artwork: loaded` lines (one every ~5.5 s). Install: build with `-destination "id=00008130-000E385E10C1401C" -allowProvisioningUpdates`, `devicectl device install app`, then `process launch` (the phone must be unlocked to launch).

### Pending, unverified, and decisions needed

- [ ] **Why the live item disappears.** At 08:15 on 2026-11-18 the display went silent for 82 s (the item was nil). It is now put back on its own; when it next happens, read the `the live item went away (it was status N, error …)` line. The cause is **unknown**.
- [ ] **A song change after the display took over.** Not seen since the handover; the airbreak showed the program's title and art. Check the display when the next track changes.
- [ ] **A real car** (`CarAudio` is treated as the phone and has never been tried in a car) and **Xcode's CarPlay simulator** as an alternative.
- [ ] **A cellular call and a declined call** while the display plays (an answered FaceTime Audio call did not interrupt it).
- [ ] **Other receivers** (Apple TV, AirPlay 2 speakers) behave unknown; the owner reports a HomePod, alone and with the display, worked.
- [ ] **Owner decision:** add `plan`, `reason` and `surface` to the `liveStart` hub event. This is a hub schema change (`schema diff/apply`, SwiftDiagnosticsHub 0.8.0 on Chromedome; `liveStart` is registered at spinner schema v5). **Do not apply it without the owner's explicit yes.** A provisional send on the dev key is possible first.
- [ ] **`apiFailed` events on Brawn** are unexplained (an `apiFailed queued` line appears in the journal); pull the details from the hub if wanted.
- [ ] The artwork is re-set on the playing item about every 5.5 s even when unchanged. Harmless so far; if the display ever flickers, that is the first suspect.
- [ ] **Springer** (iPad) has an older build (the restart fix only).
- [ ] Release housekeeping before tagging 3.6.0 (CHANGELOG link references, README, which unreleased items are in 3.5.1; see the 2026-11-14 handoff). `.swift-version` is untracked and not mine; left alone.

### Context loss warning

- Do not "fix" the display pausing when switched to "iPhone Speaker": it is the system's behavior (ADR-011), and the withdrawn `fa289f9` shows the attempt.
- `routeDidChange` only re-plans while `liveSource == .shifted`; a player already on the direct stream stays on it when the route changes to the phone (no rewind until live is restarted). That is as designed, not a bug found.
- The queue player reports an empty state more than once for one loss; `liveItemWentAway` ignores calls while a put-back is already in flight, which a test depends on.
- Fact-checking: several earlier statements in the proposal are marked (device), (repo) or *unverified*; keep that discipline, and do not reword an unverified hypothesis as fact.

## Addendum, 2026-11-18 night: the hub side (hub 0.8.1)

- **Hub 0.8.1 is live on Chromedome** (tag 0.8.1, `main` `3c0c590`). It fixes the read API reporting the schema version the hub started with (Spinner read 5 after v7 was applied; ingest was never affected). `ReadSurface` now asks the registry when read. Spinner reads 7 on the hub. The fix is proved by tests over a real socket; **live, a fresh start cannot show a reload**, so the next `schema apply` + `SIGHUP` is the proof. The hub's `README` has a "What reloads" table: the apps file reloads, `hub.json` needs a restart.
- Still unproven on the hub: a real `liveStart` carrying `plan`, `reason`, `surface`, and any `playbackStall` or `streamOutage`. They need a live start from the display on Brawn (a cold launch also tests the 23 s re-plan fix; look for `live plan: direct (receiver), the route changed while the recording started` in the journal).
- Development-channel events raise no hub alert by design, so nothing will tell the owner when these arrive. A command-line sender exists: `swiftpush-hub send` (SwiftPushHub; `--credentials --channel --severity --title --body --collapse-key --resolves`). An earlier version of this note said none existed; that was wrong, from searching only the hub repo. A bare unsigned copy is probably refused on the LAN by Local Network privacy (unverified), so a host job wants a signed bundle. The better route is two proposals: hub watches (alert on a matching event, in the hub) and DeepLinks (`SwiftPush/project/plans/proposals/DeepLinks.md`, to take precedence), neither built.

## Addendum, 2026-11-19: links into the app (DeepLinks)

- Alerts can now carry a link that opens a place in an app: SwiftPush 1.0.0-beta.3 (`PushNotification.link`), the push hub 1.2.0 (per-channel `linkSchemes`,
  `swiftpush-hub send --link`; **not deployed**; deploying also brings 1.1.1 and swift-oauth beta.11's one-way schema migration, so copy `oauth.db` first), the Inbox
  (`LinkRouter`, its own scheme list; on the branch `feat/channel-sync`, not installed), and Spinner's URL structure (`SpinnerLink`, `AppNavigation`).
- Spinner links: `spinner://live`, `archive`, `archive/2026-11-18`, `settings`, and on a debug install `probe/archive`, `probe/live`. A notification's link is read with
  `SpinnerLink(notificationURL:)` and never acts (`spinner://live/play` is refused there).
- **Owner steps that remain:** install the Inbox and this build on Brawn and tap a link (cold and warm); deploy the hub; define a show-level link (needs the archive's
  show identifier); then the hub's "watches" so the Spinner `liveStart` and stall alerts exist. Until Spinner takes direct push (owner direction), Spinner links go through the Inbox.

## Metrics

| Metric | Before | After |
| :--- | :--- | :--- |
| App tests (iOS simulator) | 534 (2026-11-14) | 660 (2026-11-19) |
| Display live start | ~24 s, stuttering | 4.3 to 6.2 s |
| Display title and art | none | shown (confirmed 2026-11-17) |

**AI Model Used:** Claude Sonnet 5.5 (this segment; earlier in the session, the previous model)
