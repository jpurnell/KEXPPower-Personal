# Design Proposal: Apple Watch widget (Smart Stack and watch-face complications)

**Status:** APPROVED 2026-11-05, built 2026-11-05 (StationKit 0.7.0; the plain `group.com.JPEnterprises.Spinner` worked on the watch App IDs and Xcode registered them itself; awaiting a check on a watch) (owner: "1 approved"; order: Mac clean-up, then this, then Control Center)
**Date:** 2026-11-05
**Master Plan Reference:** `NowPlayingWidget.md` §3i and §15 ("Watch Smart Stack and complications"), deferred from the first widget.
**Facts marked (SDK) were read from the Xcode 27.2 SDK interfaces; anything not confirmed is marked *unverified*.**

---

### 1. Objective
A watch widget that shows what KEXP is playing and starts or pauses the stream, in the Smart Stack and on watch faces, built from the same `StationKit` types as the iPhone and Mac widget.

| Family | Shows |
|---|---|
| `accessoryRectangular` (Smart Stack, most faces) | song title and artist, the time it aired, a play/pause button |
| `accessoryCircular` | a play/pause button over the KEXP mark |
| `accessoryInline` | "Title – Artist" on one line |
| `accessoryCorner` | the play/pause icon, with the title curved along the bezel |

### 2. Motivation
**Current situation (verified in this repo):**
- `Spinner Watch` is a standalone watch app that plays the stream and tracks the playing state (`WatchPlayer`: `isPlaying`, `isBuffering`, title, artist) but nothing outside the app can show it.
- The iPhone and Mac widget publish through `WidgetPublisher` and an App Group store; the watch app does not publish at all.

**Workaround today:** open the watch app, which takes 35–40 seconds to reach the stream on a cold network (master plan). A glance at the watch face for the song, and one tap for audio, are most of the value of a watch widget.

### 3. Proposed Architecture
#### 3a. One more extension, shared types
A new target `Spinner Watch Widget` (watchOS widget extension) embedded in `Spinner Watch`. It reuses `WidgetSnapshot`, `NowPlayingStore`/`AppGroupNowPlayingStore`, and `WidgetRefreshPolicy` from `StationKit` unchanged, and the watch-specific views are new. The accessory families exist on watchOS (SDK: `accessoryCorner`, `accessoryCircular`, `accessoryRectangular`, `accessoryInline` in the watchOS WidgetKit interface).

#### 3b. App Group
The watch app and its extension need their own App Group: `group.com.JPEnterprises.Spinner` is the iOS one, and a watch app's group is separate from the phone's unless declared on both. **Portal step for you:** register (or reuse) the group for the `.watchkitapp` and `.watchkitapp.widget` App IDs. I expect the same wildcard-profile trap the iPhone hit (a group is refused unless the entitlement forces an explicit profile), so the entitlements file must declare it. **Answered:** the plain `group.` identifier works on the watch: both watch App IDs were registered by Xcode with `-allowProvisioningUpdates` and the group is in the signed apps and profiles. A read-back from a running watch is still to do.

#### 3c. Publishing from the watch app
`WatchPlayer` calls a publisher when the track, show or playing state changes: the same shape as the iPhone's `WidgetPublisher`, which needs to move from the app target into something the watch can share (the cleanest place is `StationKit`, since it has no iPhone-specific code; its reload step takes a closure, so the watch passes `WidgetCenter` while tests pass a recorder). That move is a StationKit minor version, with tests; the iPhone app switches to it in the same change. This also answers the lesson of the play-state bug: publish the moment the player changes, not on a poll, and let an expected state stand for a few seconds after a tap.

#### 3d. Play/pause
`PlayPauseIntent` is an `AudioPlaybackIntent` (SDK: watchOS 10), so a tap can start audio without opening the app. *Unverified on a watch: that it starts the stream from a cold watch, given the 35–40 s connect time. If it cannot, the button opens the app instead and says "Connecting…".*

#### 3e. Refresh, stated honestly
A watch widget has a smaller refresh budget than the phone's, and a complication can be minutes behind. It says "Last played", never "live", as the iPhone widget does. The app reloads it on change while the app runs.

### 4. API Surface
StationKit gains a public `NowPlayingPublisher`-style type (name to settle at implementation) moved from the app, all documented. The extension is internal views and a provider.

### 5. MCP Schema
Not applicable.

### 6. Constraints & Compliance
Swift 6 strict concurrency; no force unwraps; gate at 0/0. Privacy: only track text and a flag in the group; no listener identifier. Accessibility: every control labelled; text honours Dynamic Type within each family's limits; accented rendering keeps art out (accessory families are monochrome, so no artwork).

### 7. Source & API Compatibility
Additive. The watch app's deployment target is watchOS 10; accessory families need nothing higher. The iPhone widget's behaviour must not change (existing tests stay green).

### 8. Backend Abstraction
The views read `WidgetSnapshot`, which is station-agnostic. Only the provider names KEXP.

### 9. Resource Budget
One snapshot (a few KB). No artwork (monochrome families), so no memory pressure. One request to KEXP per refresh; the watch's refresh budget is stricter, so the policy interval may need to be longer than 5 minutes (*unverified: tune after watching how often the system honours it*).

### 10. Dependencies
**Internal:** StationKit (new minor), StationKitAdapterKEXP, KEXPPowerKit.
**Portal (owner):** App Groups on the two watch App IDs, as in 3b. Xcode registers the extension's own App ID on first build with `-allowProvisioningUpdates`.

### 11. Test Strategy (test first, in StationKit)
- **Publisher:** saves a snapshot only on content change; always refreshes the heartbeat; reloads on content or play-state change and not otherwise; an expected play state stands for its window (the same cases `WidgetPublisherTests` and `PlayStateExpectationTests` cover now, moved with the code).
- **Views:** rendered layout checks at each family size with `ImageRenderer`, as the iPhone widget has; text that fits at the largest Dynamic Type the family allows.
- **On a watch:** a manual check, stated as such: complication shows the song, tap starts audio, the icon follows the player.

### 12. Architecture Decision Review
ADR-007 (widget logic in StationKit) extended: the publisher moves there too.

### 13. Adversarial Review
1. **"A complication is minutes stale."** True, and labelled "Last played". Not a defect to hide.
2. **"The tap cannot start audio from cold."** Possible (3d); the fallback opens the app.
3. **"Moving the publisher breaks the iPhone widget."** The existing 96 app tests plus the moved StationKit tests guard it; the iPhone change ships with the move.
4. **"The group is refused on the watch."** Found the same way as on the Mac: write and read back from a signed build before building views on top.

### 14. Alternatives Considered
- **Share the iPhone's group with the watch via the phone:** the watch app is standalone and plays without the phone; rejected.
- **Complication only (no Smart Stack):** the same extension serves both; no saving.
- **WidgetKit controls on the watch** (SDK: watchOS 26): the Control Center proposal covers them.

### 15. Future Directions
Controls on the watch (watchOS 26); a configurable stream quality; the add button once MusicKit is proven in an extension.

### 16. Open Questions
Group identifier style on the watch (3b); whether `AudioPlaybackIntent` can start a cold stream (3d); the watch's real refresh rate (9). All three are answered by trying on the watch, which I cannot do without you.

### 17. Documentation Strategy
README (watch widget row), CHANGELOG (app and StationKit), master plan (strike the watch-widget item), `NowPlayingWidget.md` §3i links here.
