# Design Proposal: Control Center play/pause control (iPhone, and the Mac menu bar and Apple Watch where the SDK allows)

**Status:** APPROVED 2026-11-05 (owner: "build the control proposal and skip visionOS for now"; the SDK does not allow controls on visionOS in any case, see §3c)
**Date:** 2026-11-05
**Master Plan Reference:** `NowPlayingWidget.md` §14 ("A Control Center control… a good follow-up") and §15.
**Facts marked (SDK) were read from the Xcode 27.2 SDK interfaces; anything not confirmed is marked *unverified*.**

---

### 1. Objective
One control, "KEXP", that plays or pauses the stream from Control Center, the lock screen's control slots and the Action button, without opening the app, and shows the real playing state.

### 2. Motivation
**Current situation (verified in this repo):**
- Play/pause already exists as an `AudioPlaybackIntent` (`PlayPauseIntent`) that runs in the app process and starts the player (`AppModelRegistry.togglePlayback`). The widget uses it.
- The playing state already reaches an App Group store (`nowPlayingStore.playing`, with a heartbeat) the moment the player changes.
- Lock-screen and Control Center show Now Playing only while audio is active; nothing starts KEXP from there.

**Drawback:** starting KEXP means finding the app or a widget. A control is one swipe and one tap from anywhere, and can sit on the Action button.

### 3. Proposed Architecture
#### 3a. A toggle control in the existing widget extension
`ControlWidgetToggle` (SDK: iOS 18, macOS 26, watchOS 26; unavailable on visionOS and tvOS) inside a `StaticControlConfiguration`, added to `SpinnerWidgetBundle` beside the Now Playing widget. The toggle's value is "playing"; its action is `PlayPauseIntent`'s existing logic (a `SetValueIntent` variant if the toggle requires one, sharing `AppModelRegistry.togglePlayback`). *Whether a control may reuse an `AudioPlaybackIntent` directly, or needs a separate `SetValueIntent` that forwards to it, is unverified: try the direct form first.*

#### 3b. State
A control's value comes from a `ControlValueProvider` that reads the same `NowPlayingStore` (`isPlaying()`, which already treats a flag older than 120 s as not playing). The app asks the system to refresh it when the state changes, with `ControlCenter.shared.reloadControls(ofKind:)` (SDK: iOS 18), next to the `WidgetCenter` reload `WidgetPublisher` already makes. This is the same publish-on-change path that fixed the widget's lagging icon; no new polling.

#### 3c. Platforms
- **iPhone / iPad:** Control Center, lock screen, Action button.
- **Mac (macOS 26):** the SDK lists controls on macOS 26, which would put it in the menu bar; this app's Mac deployment target is 14, so the control needs `@available` and the Mac behaviour is *unverified until tried on a macOS 26 machine*.
- **Apple Watch (watchOS 26):** the SDK lists controls there too; it belongs with the watch widget extension, not this one, and waits on it.
- **Vision Pro: not possible today.** The owner's view (2026-11-05) is that it should have controls and there is no good reason it should not. The reason is Apple's: `@available(visionOS, unavailable)` is on `StaticControlConfiguration`, `ControlWidgetToggle` and `ControlWidgetButton`, and I read that in the visionOS SDK's own WidgetKit interface (not only the iOS one), so a control target cannot be built for visionOS in this SDK. Vision Pro keeps the Now Playing widget, which has a play/pause button (visionOS 26). When a later SDK removes the restriction, adding visionOS here is a platform filter and an `@available` change, and I will check each SDK release for it.

#### 3d. Limits stated plainly
A control cannot show artwork or the song title; it shows a symbol, a label ("KEXP") and a value ("Playing"/"Paused"). A control that shows the wrong state until reloaded has the same cause as the widget's earlier lag, so the same remedy applies: reload on change, and an expected state stands for a few seconds after the tap.

### 4. API Surface
Internal: one `ControlWidget`, one value provider, and a one-line reload in `WidgetPublisher`'s play-state path. No public API.

### 5. MCP Schema
Not applicable.

### 6. Constraints & Compliance
Swift 6 strict concurrency; no force unwraps; gate at 0/0. Privacy: the control reads a boolean from the group. Accessibility: the control's label and value are read by VoiceOver by default; both are written out explicitly ("KEXP, playing").

### 7. Source & API Compatibility
Additive. The extension's iOS deployment target is 17; the control is `@available(iOS 18, macOS 26, *)`, so iOS 17 devices simply do not see it.

### 8. Backend Abstraction
Reads station-agnostic state from the store; "KEXP" comes from the station name constant the widget already has.

### 9. Resource Budget
Nothing new at rest. A reload per play-state change, as the widget already does.

### 10. Dependencies
None new. Same App Group and App ID capabilities as the widget.

### 11. Test Strategy
- **Unit:** the value provider returns playing/paused from a fake store, including the stale-flag case (a flag older than the limit reads as paused); the reload is requested on a play-state change and not on a repeat (the publisher's existing test shape, with the reload closure extended to controls).
- **Not automatable:** that Control Center shows and toggles the control. This is a manual check on Brawn, stated as such; the add step ("Add a Control") is yours.

### 12. Architecture Decision Review
No new ADR; it applies ADR-007 (logic lives in shared code, the extension is thin).

### 13. Adversarial Review
1. **"It shows the wrong state."** Possible when the app is killed while playing; the 120-second staleness rule bounds it.
2. **"A tap cannot start audio from the control."** If `AudioPlaybackIntent` is not allowed there, the control opens the app instead; found by trying.
3. **"iOS 17 users get nothing."** Correct, and stated.

### 14. Alternatives Considered
A Live Activity (iPhone only, a different feature); widening the widget to the lock screen (`accessory` families on iOS) is complementary and could be a later, small addition.

### 15. Future Directions
Controls on the watch and Mac menu bar; a "sleep timer" control; opening the app to the playlist as a second control.

### 16. Open Questions
Direct `AudioPlaybackIntent` reuse (3a), Mac behaviour on macOS 26 (3c).

### 17. Documentation Strategy
README (platform table), CHANGELOG, master plan (strike the item), `NowPlayingWidget.md` §14 links here.
