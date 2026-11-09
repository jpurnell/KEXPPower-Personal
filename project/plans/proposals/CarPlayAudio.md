# Design Proposal: CarPlay Audio app

**Status:** the Archive tab, a way back to live and the song heard in archived shows were built 2026-11-08 (looked at in the CarPlay simulator; not in a car). APPROVED 2026-11-05 and the first pass built (Live tab, Now Playing with an add button via `CPNowPlayingImageButton` so the button can show its state, Archive placeholder; awaiting a look in a CarPlay simulator or car). Earlier: REVISED 2026-11-05 after owner feedback (add to playlist in the car; root screen shows the show and host; an Archive tab like the KEXP website, which is its own proposal: `ArchiveBrowser.md`) (Apple approved the CarPlay Audio entitlement for this app on 2026-11-05; the portal and signing steps are the owner's, listed in §10)
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

#### 3b. Templates (revised on the owner's direction)
Root is a **tab bar** (`CPTabBarTemplate`; SDK: the class exposes `maximumTabCount`), which also settles the earlier open question about a tab bar:
- **Live tab:** a list whose first item is the current show and its host, as the website and the phone show them: "The Midday Show" with "Cheryl Waters" beneath it, refreshed as the show changes (from `NetworkManager.getShow`, the same call the phone's show header uses; a hand-over between shows updates the item). Selecting it starts the stream and pushes the system Now Playing template. A second item shows the song on the air now.
- **Archive tab:** the archive browser (below and in `ArchiveBrowser.md`), reached from the root in one tap.
- **Now Playing:** `CPNowPlayingTemplate.sharedTemplate` (SDK: iOS 14) reads the artwork, title and artist from `MPNowPlayingInfoCenter`; the buttons below it are configured by us (3b-2). `allowsMiniPlayer` exists in this SDK (iOS 27); *whether it applies to a radio app is unverified*.

#### 3b-2. Add to playlist in the car (reversed from the first draft)
My first draft left this out as "tap-heavy"; the owner is right that a driver cannot open the phone and that this is where the feature is most useful. The SDK has a button made for it: `CPNowPlayingAddToLibraryButton` (SDK: a `CPNowPlayingButton` subclass, set with `updateNowPlayingButtons:`). Its handler runs the app's existing `SongSavingModel.save(_:)`, so the car and the phone add to the same "KEXP" playlist, with the same ledger (a song is never added twice).

Two things differ in a car and are decisions, not details:
1. **The "Is this the song?" prompt.** Today a text-search match (no ISRC) asks the listener to confirm. In the car that prompt must be glanceable or absent. Owner agreed 2026-11-05 ("a good safety compromise"). Proposal: an ISRC match adds immediately and the button shows added; a text-search match is **not guessed at**: it is kept as "needs review" and the phone shows it when the driver is parked (a small change to `SongSavingModel`'s state, with tests). If Apple's rules allow a two-button alert template (`CPAlertTemplate`; *unverified*), the prompt could appear there instead; I would build "review later" first because it is safe at speed.
2. **Feedback.** Without looking, the driver needs to know it worked: the button changes state (added / not found), and the system's own confirmation sound or banner is used where the templates allow (*unverified which*). No custom audio over a live stream.

The Mac cannot add to a playlist (MusicKit) and has no CarPlay, so this is the iPhone's feature. It needs the Apple Music permission and subscription the phone already requires; if permission was never granted, the first press in the car cannot show a permission dialog there, so the app asks for it on the phone before the first drive (a setup step I will make visible in Settings).

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
3. I add `com.apple.developer.carplay-audio` to `KEXPPowerExampleSwiftUI (iOS).entitlements` and the CarPlay scene to Info.plist. **Done 2026-11-05:** with the capability enabled on the App ID, the key `com.apple.developer.carplay-audio` was added to the entitlements and a signed device build was made with `-allowProvisioningUpdates`; `codesign` shows the key in the signed app and the embedded profile grants it (`com.apple.developer.carplay-audio => true`), so the key name is confirmed by a working build.
**Testing:** the Xcode CarPlay simulator (a separate window; `I/O → External Displays → CarPlay`), or DeviceHub (Xcode's `DeviceHub.app`), whose CarPlay Simulator menu item is greyed out for a simulator and works for a physical iPhone connected by USB (owner, 2026-11-06), then a real car or a CarPlay head unit, which only you have.
**Internal:** none beyond the existing packages.

### 11. Test Strategy
- **Add in the car (red first):** an ISRC match adds and reports added; a text-search match is held as needs-review and is not added; a repeat press does not add twice; permission missing reports needs-permission without a prompt. These extend `SongSavingModelTests` and need no car.
- **Unit (red first):** the list item's title and subtitle from a snapshot (a song; an airbreak, which reads "Airbreak" as everywhere else; nothing yet, which reads "KEXP"), and that long titles are cut at a limit instead of overflowing (the limit comes from Apple's rules, to be confirmed).
- **Wiring:** the scene delegate sets a root template when the interface controller connects, and removes references when it disconnects — testable with a fake `CPInterfaceController` seam if the types allow; *unverified: CarPlay's classes may not be constructible in a test host, in which case this is checked in the CarPlay simulator and stated as manual*.
- **Not automatable:** the real head unit. Manual, on your car.

### 12. Architecture Decision Review
**New ADR-008:** *CarPlay is a scene of the iPhone app that reads the app's shared player and model; it has no player of its own.* Rejected: a separate CarPlay-only player (two audio sessions, double the stream).

### 13. Adversarial Review
1. **"App Review rejects the screen set."** Mitigated by keeping to Apple's templates and a minimal list; the tab bar is added only if review wants it.
2. **"The car and phone disagree about state."** They share the one player, and the system Now Playing state comes from the one publisher.
3. **"The archive is a whole feature, not a screen."** Correct; it is `ArchiveBrowser.md`, and the CarPlay Archive tab ships after the phone's.
4. **"I cannot test it without a car."** The CarPlay simulator covers the screens; a real head unit is the owner's final check, flagged for the release notes.
5. **"The entitlement and profile are not in place."** The first build step is to confirm the signed build carries the entitlement before writing any UI (the same lesson the App Group taught).

### 14. Alternatives Considered
- **Widgets in CarPlay** (SDK has `WidgetLocation.carPlay`, iOS 26): complementary and separate; a widget cannot start audio reliably in a car and is not an audio app. **Looked into 2026-11-06:**
  - *(SDK, read in the iOS 27.2 interface)* `WidgetLocation.carPlay` is iOS 26 only (unavailable on macOS, watchOS, tvOS, visionOS). `WidgetConfiguration.disfavoredLocations(_:for:)` (iOS 17) lets a widget *decline* a location per family; **this app's widget does not use it, so it is eligible by default.** There is no public way to read the location from inside the widget's view: `isCarPlayDisplay` and a hide-in-CarPlay modifier exist only as exported symbols in the framework's `.tbd`, not in its public interface, so they are not to be used.
  - *(reported by 9to5Mac, 2025-10-30; third-party, not Apple documentation)* any iPhone widget can be added to CarPlay, the app need not be a CarPlay app, and no developer step or entitlement is mentioned. The listener chooses them in **Settings → General → CarPlay → (the car)**; one or two stacks depending on the car's screen, up to five widgets each. A developer-skills page lists `.systemSmall` as the CarPlay family, also third-party.
  - *Checked by the owner 2026-11-06:* the existing Now Playing widget is already offered in CarPlay with no change to the app. *Seen in DeviceHub on Brawn, 2026-11-06 ("Widescreen Instrument Cluster" layout):* a small tile with the cover filling it and the title and artist overlaid at the bottom left; no play control is visible. *Still unrecorded:* whether tapping it does anything, and how other car layouts size it.
  - **Consequence:** nothing needed building. The first step was to look, not to code. If the small layout reads badly in the car, the only public lever is `disfavoredLocations` (opt out) or a layout that is good everywhere.
- **Only the system Now Playing screen:** it appears while audio plays, but an audio app with no root template does not show up in CarPlay to start anything. Rejected.

### 15. Future Directions
Siri "play KEXP" through an App Intent; a station picker if other stations adopt `StationKit`.

### 16. Open Questions
Answered by the owner 2026-11-05: add to playlist is in; root is the show and host plus an Archive link. Still open: the entitlement key and review rules (6, 10); whether a two-button alert is allowed for the unconfirmed-match prompt (3b-2); how deep Apple lets a template stack go, which limits the Archive browse (`ArchiveBrowser.md` §3c); `allowsMiniPlayer`. All need Apple's CarPlay documentation read before code is written, and I will quote what I read.

### 17. Documentation Strategy
README (platform table), CHANGELOG, master plan (move CarPlay from "later" to the roadmap), ADR-008, `PlatformExperience.md` CarPlay note updated.
