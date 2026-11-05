# Design Proposal: CarPlay Audio app

**Status:** PROPOSED 2026-11-05 (Apple approved the CarPlay Audio entitlement for this app on 2026-11-05; the portal and signing steps are the owner's, listed in §10)
**Date:** 2026-11-05
**Master Plan Reference:** "CarPlay (requires an Apple audio-app entitlement; confirm eligibility first)" — eligibility is now confirmed. `PlatformExperience.md` (CarPlay note).
**Facts marked (SDK) were read from the Xcode 27.2 SDK headers; anything not confirmed is marked *unverified*. Apple's CarPlay audio-app rules (template choices, what is allowed on screen) are from my knowledge of the CarPlay App Programming Guide, not read in this session, and are marked *unverified* where a decision depends on them.**

---

### 1. Objective
KEXP in the car: a CarPlay screen that starts the live stream and shows what is playing, on the iPhone app, using the system's CarPlay templates, with playback controls through the car's own buttons and steering wheel.

### 2. Motivation
**Current situation (verified in this repo):**
- The iPhone app already plays the stream with background audio, an `AVAudioSession` set up by `AudioSessionCoordinator`, and the Now Playing state and remote commands (play, pause, toggle) through `LegacyNowPlayingPublisher`. These are what CarPlay's Now Playing screen reads.
- There is no CarPlay scene, no CarPlay entitlement in the entitlements file, and no CarPlay UI.

**Workaround today:** Bluetooth or USB audio from the phone, with the stream started on the phone before driving.
**Drawback:** the phone's screen is the only way to start or change anything, which is the thing CarPlay exists to avoid.

### 3. Proposed Architecture
#### 3a. A CarPlay scene beside the app's scene
The iPhone target gains a scene configuration for the CarPlay role and a `CPTemplateApplicationSceneDelegate` (SDK: CarPlay framework, iOS 14; `CPTemplateApplicationScene.h`). The delegate receives the interface controller when the car connects and sets the root template. It shares the app's one player and model (the `AppModelRegistry.model` the widget intents already use), so the car and the phone are the same session.

#### 3b. Templates
A deliberately small screen set, because a driver should not be browsing:
- **Root:** a list template with one item, "KEXP 90.3 FM — Live" (subtitle: the song on now, updated as it changes). Selecting it starts the stream and pushes the system Now Playing template.
- **Now Playing:** `CPNowPlayingTemplate.sharedTemplate` (SDK: iOS 14). It shows the artwork, title and artist from `MPNowPlayingInfoCenter` and the play/pause control, with no code of ours beyond configuring it. `allowsMiniPlayer` exists in this SDK (iOS 27); *whether it applies to a radio app is unverified*.
- **Second tab, "Recently played" (read-only list of the last songs):** optional and last; a `CPTabBarTemplate` (SDK: `maximumTabCount` is given by the class) would host Live and Recent. *Unverified: whether Apple's review expects a tab bar or lets a single list stand as the root; I will build the single list first and add the tab only if needed.*

No add-to-playlist in the car: it is a tap-heavy action and playlist writes are the phone's job.

#### 3c. Data and refresh
The now-playing text on the list item and the Now Playing screen come from the same `ResultRetriever` the phone uses, so a track change updates both. The 5-second poll is already running while the app is.

#### 3d. Audio
No change to the session category (playback). The stream URL, quality choice (160 kbps standard) and interruption handling stay as they are; a CarPlay connection is one more route to the same player.

### 4. API Surface
Internal to the iPhone target: `CarPlaySceneDelegate`, and a small pure type that turns a snapshot into the list item's text so it can be unit-tested. No public API.

### 5. MCP Schema
Not applicable.

### 6. Constraints & Compliance
Swift 6 strict concurrency (the CarPlay delegate callbacks are main-thread Objective-C, so the delegate is `@MainActor`); no force unwraps; gate at 0/0. **Apple's rules for CarPlay audio apps** (*unverified, to be read from the CarPlay App Programming Guide before building*): templates only, no custom drawing, limits on list length and text, and no features that need the driver to read long text. Privacy: nothing new is collected; the network requests are the ones the phone already makes. Accessibility: the system templates handle VoiceOver and Siri on the car's side; our strings are short and complete.

### 7. Source & API Compatibility
Additive. The iPhone target's deployment target stays iOS 17 (CarPlay audio is iOS 14+). The Mac, watch and widget targets do not include CarPlay code.

### 8. Backend Abstraction
The list item reads a `NowPlayingSnapshot`, which is station-agnostic; the title string ("KEXP 90.3 FM — Live") comes from the station's name, not a literal in the scene.

### 9. Resource Budget
No extra network traffic and no extra process: the scene runs in the app. The phone's polling and the stream are what they are today.

### 10. Dependencies
**Portal and signing (owner):**
1. Confirm the approved CarPlay Audio entitlement on the account, then add the **CarPlay Audio App** capability to the `com.JPEnterprises.Spinner` App ID in the Developer portal.
2. Regenerate the provisioning profile (Xcode does this with `-allowProvisioningUpdates` once the capability is on the App ID); a profile cannot grant a capability the App ID lacks.
3. I add `com.apple.developer.carplay-audio` to `KEXPPowerExampleSwiftUI (iOS).entitlements` and the CarPlay scene to Info.plist. *The entitlement key name is from my knowledge, not read in this session; I will check it against the approval email's instructions and Xcode's capability UI.*
**Testing:** the Xcode CarPlay simulator (a separate window; `I/O → External Displays → CarPlay`), then a real car or a CarPlay head unit, which only you have.
**Internal:** none beyond the existing packages.

### 11. Test Strategy
- **Unit (red first):** the list item's title and subtitle from a snapshot (a song; an airbreak, which reads "Airbreak" as everywhere else; nothing yet, which reads "KEXP"), and that long titles are cut at a limit instead of overflowing (the limit comes from Apple's rules, to be confirmed).
- **Wiring:** the scene delegate sets a root template when the interface controller connects, and removes references when it disconnects — testable with a fake `CPInterfaceController` seam if the types allow; *unverified: CarPlay's classes may not be constructible in a test host, in which case this is checked in the CarPlay simulator and stated as manual*.
- **Not automatable:** the real head unit. Manual, on your car.

### 12. Architecture Decision Review
**New ADR-008:** *CarPlay is a scene of the iPhone app that reads the app's shared player and model; it has no player of its own.* Rejected: a separate CarPlay-only player (two audio sessions, double the stream).

### 13. Adversarial Review
1. **"App Review rejects the screen set."** Mitigated by keeping to Apple's templates and a minimal list; the tab bar is added only if review wants it.
2. **"The car and phone disagree about state."** They share the one player, and the system Now Playing state comes from the one publisher.
3. **"I cannot test it without a car."** The CarPlay simulator covers the screens; a real head unit is the owner's final check, flagged for the release notes.
4. **"The entitlement and profile are not in place."** The first build step is to confirm the signed build carries the entitlement before writing any UI (the same lesson the App Group taught).

### 14. Alternatives Considered
- **Widgets in CarPlay** (SDK has `WidgetLocation.carPlay`, iOS 26): complementary and separate; the now-playing widget could appear in CarPlay without this work, but a widget cannot start audio reliably in a car and is not an audio app. *Unverified whether a widget in CarPlay needs an entitlement.*
- **Only the system Now Playing screen:** it appears while audio plays, but an audio app with no root template does not show up in CarPlay to start anything. Rejected.

### 15. Future Directions
The archive (shows by date) as a second list once the archive exists; Siri "play KEXP" through an App Intent; a station picker if other stations adopt `StationKit`.

### 16. Open Questions
Root template choice and tab bar (3b); the entitlement key and review rules (6, 10); `allowsMiniPlayer` (3b). The first three need the Apple documentation read before code is written, and I will quote what I read.

### 17. Documentation Strategy
README (platform table), CHANGELOG, master plan (move CarPlay from "later" to the roadmap), ADR-008, `PlatformExperience.md` CarPlay note updated.
