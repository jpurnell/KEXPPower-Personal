# Design Proposal: Now Playing Widget (small, medium, large) on iPhone, iPad, Mac and Vision Pro

**Status:** APPROVED 2026-11-04, first version built 2026-11-04 (StationKit 0.6.0, adapter 0.4.0, the `Spinner Widget` extension; awaiting a check on a device) (owner: visionOS included, built last; refresh requested every 5 minutes; large size shows about six lines of the DJ comment; design for CarPlay now, verify later)
**Date:** 2026-11-04
**Master Plan Reference:** `PlatformExperience.md` §3e (Widget and App Intents), widened from "small/medium" to three sizes by the owner on 2026-11-04.
**Facts below marked (SDK) were read from the Xcode 27.2 SDK interfaces; anything not confirmed is marked *unverified*.**

---

### 1. Objective

A widget that shows what KEXP is playing, in three sizes, from one code base, on the iPhone and iPad home screen, the Mac desktop, and the Vision Pro, with play/pause on the larger sizes. It should be built so the same widget can appear in CarPlay's dashboard where the system allows it.

| Size | Shows |
|---|---|
| **Small** | Album art, with the title and artist. |
| **Medium** | The now-playing row: art, airtime, title, artist, album, label and release date, and a play/pause button. |
| **Large** | The expanded view: big art, song details, the Spotify and Bandcamp links, the show and host, and the start of the DJ's comment (a widget cannot scroll, so it is cut off), and play/pause. |

### 2. Motivation

**Current situation (verified in this repo):**
- Nothing outside the app can show what is playing. The phone's lock screen and Control Center show it while audio plays; nothing shows it when it does not.
- The pieces a widget needs already exist and are tested: station-agnostic now-playing data (`NowPlayingSnapshot`, StationKit), the KEXP adapter (`StationKitAdapterKEXP`), a bounded artwork loader with an allow-list (`ArtworkLoader`), and the App Group `group.com.JPEnterprises.Spinner`, registered and declared in the iOS app's entitlements.

**Workaround today:** open the app.
**Drawback:** the app is quick to open, but a glanceable "what is this song" needs no app launch at all.

### 3. Proposed Architecture

#### 3a. Where the logic lives
All logic goes in **StationKit** (0.6.0), where it is testable in seconds without a simulator; the widget extension is thin views and wiring.

```
StationKit
  WidgetSnapshot          Codable: station, title, artist, album, label, release date, airtime,
                          artwork URL, DJ comment excerpt, show name and host, links, isPlaying
  NowPlayingStore         protocol; AppGroupNowPlayingStore keeps the last-known snapshot and
                          the playing flag in the App Group's UserDefaults
  WidgetRefreshPolicy     when the next refresh is due, and what to show on failure
  (existing)              ArtworkLoader, NowPlayingSnapshot, MusicLinks, RequestPacer

Spinner Widget (extension, one target)      thin: TimelineProvider, three layouts, intents
App (iOS, Mac)                              writes the store when the track or play state changes,
                                            asks WidgetKit to reload
```

#### 3a-2. Two additive changes the medium and large sizes need
- `Track` gains `labels: [String]` and `releaseDate: String?` (both optional or empty by default, so no adapter breaks), and `Station` gains `currentProgram() async throws -> ProgramInfo?` with a default that returns `nil`. `StationKitAdapterKEXP` 0.4.0 fills all three in from KEXP's plays and shows.

#### 3b. One extension target, three platforms
A single multiplatform widget extension (iOS, iPadOS, macOS, visionOS), embedded in the iOS app target and the Mac target with platform filters, the same way the watch app is embedded today. The home-screen sizes are `systemSmall`, `systemMedium` and `systemLarge` (SDK: iOS 14, macOS 11, visionOS 26).

#### 3c. Data flow
1. The provider starts from the **last-known snapshot in the App Group**, so the widget never shows a blank, and asks KEXP's API (through the adapter) for the latest play.
2. It downloads the artwork with `ArtworkLoader`, scales it to a few hundred pixels (a widget has a small memory budget), and puts the bytes in the entry.
3. It returns an entry labelled with when the song aired, never "live".
4. While the app is running it writes the store and calls `WidgetCenter.reloadAllTimelines()` when the track or the play state changes.

#### 3d. Refresh, stated honestly
WidgetKit refreshes on a system budget of minutes, not seconds. The widget therefore shows "Last played 3:36 PM". It asks to be refreshed **every 5 minutes** (owner decision 2026-11-04) and updates promptly when the app is running and tells it so. A request is not a guarantee: WidgetKit keeps the budget and, at 5 minutes, may refresh less often than asked (a day of 5-minute refreshes is more than the documented order of magnitude, so some will be skipped). It will not tick live. (The budget figure is the documented order of magnitude, not a guarantee.) The refresh interval is a constant in `WidgetRefreshPolicy`, so it can be tuned after seeing how often the system honours it.

#### 3e. Play/pause
`PlayPauseIntent` conforms to `AudioPlaybackIntent` (SDK: iOS 17, macOS 14, watchOS 10, tvOS 17), so playback can start without opening the app. The widget cannot ask the player whether it is playing, so the app writes a playing flag to the App Group and reloads the widget. If that flag is stale, the button shows the wrong icon until the next reload; this is the main correctness risk.

#### 3f. Add to playlist in the widget — not in the first version
The add button needs MusicKit and Apple Music permission, which have not been proven inside a widget extension, and MusicKit cannot write playlists on the Mac. The widget links to the app instead.

#### 3g. CarPlay (iOS 26 and later)
The SDK has `WidgetLocation.carPlay` (SDK: iOS 26), so the system can place widgets in CarPlay. The plan is to design the small size with large touch targets and no tiny text, and test in the CarPlay simulator. This is **separate from a CarPlay audio app**, which still needs Apple's CarPlay audio entitlement and a template-based UI. Whether a widget in CarPlay needs any entitlement is *unverified*.

#### 3h. HomeView
No mention of HomeView was found in WidgetKit or CarPlay in the SDK. I cannot say whether a widget carries over. *Unverified; no commitment.*

#### 3i. Apple Watch
watchOS uses a different set of sizes (`accessoryCircular`, `accessoryRectangular`, `accessoryInline`, `accessoryCorner`) and a Smart Stack (SDK: watchOS 26). It would be a second, small extension reusing the same StationKit types. **Not in this proposal's first version.**

### 4. API Surface (StationKit 0.6.0, all public and documented)

```swift
public struct WidgetSnapshot: Codable, Sendable, Equatable { ... }
public protocol NowPlayingStore: Sendable {
    func lastSnapshot() async -> WidgetSnapshot?
    func save(_ snapshot: WidgetSnapshot) async
    func isPlaying() async -> Bool
    func setPlaying(_ playing: Bool) async
}
public struct AppGroupNowPlayingStore: NowPlayingStore { init(groupID: String) }
public struct WidgetRefreshPolicy: Sendable { func nextRefresh(after: Date, lastSucceeded: Bool) -> Date }
```

### 5. MCP Schema
Not applicable.

### 6. Constraints & Compliance
- **Swift 6, strict concurrency**; no force unwraps; every public symbol documented; the gate at zero.
- **Privacy:** the widget fetches the public KEXP playlist and artwork from allow-listed hosts only. It sends no identifier of the listener. The App Group stores track text and a flag, nothing personal.
- **Accessibility:** Reduce Transparency respected (solid container background); Dynamic Type; VoiceOver labels on every control; the widget must remain legible in the system's tinted and accented rendering modes (SDK: the rendering-mode environment).
- **Mac sandbox:** the extension needs outgoing network access and the App Group. The Mac app currently has no App Group entitlement, so, like the iOS app, it would be signed with a profile that has no capabilities until it declares one (see §10).

### 7. Source & API Compatibility
Additive. The visionOS widget requires visionOS 26 (SDK), while the app's visionOS minimum is 1.0, so the extension's deployment target is 26 for visionOS and the app stays as it is. *Whether an app with a lower minimum can embed an extension with a higher one on visionOS is unverified and is the first thing to try.*

### 8. Backend Abstraction
Nothing KEXP-specific is in the widget logic: it consumes `NowPlaying` from any `Station`. Only the extension's wiring names KEXP.

### 9. Resource Budget
- One snapshot (a few KB) plus one scaled image (under about 150 KB) held at a time; the extension is killed if it exceeds its memory limit.
- One request to KEXP and one to the artwork host per refresh; about 4 to 6 refreshes an hour at most.

### 10. Dependencies
**Internal:** StationKit 0.6.0, StationKitAdapterKEXP, KEXPPowerKit.
**Portal (owner):** App Groups is **done** for `com.JPEnterprises.Spinner` (iOS, visionOS: `group.com.JPEnterprises.Spinner`). **The Mac uses a different, Team-ID-prefixed group** (`BNDA9Y6YV9.com.JPEnterprises.Spinner`), which needs no portal registration: with automatic signing the Mac builds were signed with a wildcard profile that does not authorize a `group.` identifier, and the system then refused the app's writes (found by running it, 2026-11-04). The extension's own App ID (`com.JPEnterprises.Spinner.widget`) needs the App Groups capability too; Xcode registers it on first build with `-allowProvisioningUpdates`, and I will confirm. The Mac app needs the App Group entitlement declared in `Spinner Mac.entitlements`.
**External:** none new.

### 11. Test Strategy (test first, in StationKit)
- **Snapshot:** built from `NowPlaying` for a track, an airbreak, nothing; blank fields; long titles; round-trip through `Codable`.
- **Store:** survives a new instance over the same defaults; corrupt data reads as empty; the flag defaults to not playing.
- **Refresh policy:** next refresh after success and after failure; never sooner than the minimum; failure keeps the last-known snapshot.
- **Extension:** layout checked in Xcode previews at each size, in light, dark and tinted modes, and on the Mac desktop, the iPhone, and the Vision Pro. Previews are not automated tests; this is stated rather than hidden.

### 12. Architecture Decision Review
**New ADR-007:** *Widget logic lives in StationKit; the extension is views and wiring.* Extends ADR-006 (station-agnostic code in StationKit).

### 13. Adversarial Review
1. **"The widget will look stale."** It will be up to about 15 minutes behind unless the app is running. The label says "Last played", never "live". That is the platform's limit, not a defect to hide.
2. **"The play/pause icon can be wrong."** Yes, if the app was killed while playing. Mitigation: the app clears the flag on termination where it can, and the widget treats a flag older than a few minutes as not playing.
3. **"The extension will exceed its memory."** Mitigation: scale artwork before it reaches the entry, one image at a time.
4. **"MusicKit in a widget might not work."** Which is why the add button is not in the first version.
5. **"The Mac signing problem again."** Addressed up front: declare the group in the Mac entitlements before writing the extension.

### 14. Alternatives Considered
- **Separate extensions per platform:** triples the wiring for no gain. Rejected.
- **Live Activity / Dynamic Island** for the current track: iPhone only, a different feature. Kept in Future Directions.
- **A Control Center control** (play/pause) on iOS 18 and later: complementary, small, and a good follow-up. Not in this proposal.
- **Putting the logic in the extension:** it could not be unit-tested without a simulator host. Rejected.

### 15. Future Directions
Watch Smart Stack and complications; a Control Center control; the add button once MusicKit is proven in an extension; configuration to choose the stream quality.

### 16. Open Questions
All four are answered (2026-11-04): visionOS yes, built last; refresh requested every 5 minutes; about six lines of the DJ comment on the large size; design for CarPlay now and verify later.

Still open: whether an app with a lower visionOS minimum can embed an extension that needs visionOS 26 (try first), and whether a widget in CarPlay needs an entitlement.

### 17. Documentation Strategy
DocC on the StationKit types; README gains a Widget section and the platform matrix gains a widget column; CHANGELOG entries in StationKit and the app; the master plan's status updated.
