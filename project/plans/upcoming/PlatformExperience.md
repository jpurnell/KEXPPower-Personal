# Design Proposal: Navigation Shell, Mac Playback and Layout, Apple Music Playlists, Widget and App Intents

**Status:** APPROVED 2026-11-03 (Phase 0 starts first) — revised 2026-11-03 (separate per-platform targets; generic StationKit repo; ISRC-based song matching; tvOS/watchOS kept ready) — awaiting approval
**Date:** 2026-11-02
**Delivery:** four phases, each independently shippable and each gated by its own tests. Phase D (archive) is design-only until the library's async `ArchiveManager` exists (iOS 27.2 follow-up).
**Not in scope:** the iOS 27 `NowPlaying` framework (on hold). The `NowPlayingPublishing` seam (ADR-003) keeps it a later, small change.

---

### 1. Objective

Turn the app from one live-playlist screen into a small multi-platform product:

- **A navigation shell** (Live / Archive / Playlists / Settings) that every later feature hangs from.
- **Mac playback and a Mac-native layout.** Today the Mac build shows the playlist but cannot play audio.
- **Apple Music playlists:** add the playing track to a dedicated "KEXP" playlist.
- **A widget and App Intents:** "what's playing", play/pause, and add-to-playlist from Siri, Shortcuts, the widget and Control Center.
- **Archive browsing** (design now, build after the library work).

**Master Plan Reference:** Roadmap Phase 2 (Apple Music, archive, links) and Phase 3 (macOS, visionOS).

### 2. Motivation

**Current situation (verified in this repo):**
- One screen (`ContentView`), no navigation. The archive feature has nowhere to live.
- `PlayerController` is `#if os(iOS) || os(visionOS)` only, so macOS has no playback. It also uses `AVAudioSession`, which does not exist on macOS.
- `ResultRetriever` owns both data polling and the player, so a widget or an intent cannot reuse either.
- Apple Music support is read-only: a search link (`getAppleMusicLink`) and a title button that opens it.
- The README lists "add songs directly to a dedicated KEXP Apple Music playlist" as the app's reason to exist.

**Workaround today:** none; the Mac build is a preview-quality port of the iPhone layout.
**Drawback:** the headline feature (save the music you hear) does not exist, and nothing outside the app can ask "what is playing?".

### 3. Proposed Architecture

#### 3a. Layering (the key move)
Split what the app *knows* from what it *shows*, so the app, widget and intents share one source of truth:

```
KEXPPower (library)      plays/shows over the network
   │
LiveActivityService      ← new: fetch current play + show; no UI, no player. Used by app, widget, intents.
   │
PlaybackController       ← PlayerController generalised: iOS/visionOS/macOS; owns AVPlayer + NowPlayingPublishing
PlaylistService          ← new: MusicKit find/create/add; behind a protocol for tests
   │
SwiftUI shell            ← NavigationSplitView / TabView, per platform
```

#### 3a-2. Targets and the generic package (owner decisions 2026-11-03)

**Separate app targets per platform, one shared generic package in its own repository.**

```
KEXPPowerKit (repo, exists)   KEXP's HTTP API only: plays, shows, stream URLs. Knows nothing about playback or UI.
        ▲
StationKitAdapterKEXP  (new repo)       THE ADAPTER. Maps KEXPPowerKit's Play/Show onto StationKit's protocols. No UI, no playback.
        ▲                     Depends on KEXPPowerKit + StationKit.
        │
StationKit   (new repo)       NOT station-specific. Defines `Station` and `Track`, and everything that works from them:
   ▲                          playback glue, Now Playing, audio session, artwork, link-outs, song matching, playlist saving.
   │
   ├── KEXPPower (iOS app)           depends on StationKit + StationKitAdapterKEXP
   ├── KEXPPower Vision (visionOS)   own target (owner decision); spatial layout
   ├── KEXPPower Mac (macOS)         sidebar, menus, Settings, window management
   ├── KEXPWidget (extension)        iOS, macOS, visionOS, watchOS; links StationKit, never the player
   ├── tvOS app    ── "ready", not built in this proposal
   └── watchOS app ── "ready", not built in this proposal
```

**What is generic (moves to StationKit) and what stays:**

| Piece | Today | Generic? | Change needed to extract |
|-------|-------|----------|--------------------------|
| `NowPlayingSnapshot`, `NowPlayingPublishing`, `LegacyNowPlayingPublisher` | app | Yes | none; they already take plain strings |
| `AudioSessionCoordinator` | app (iOS) | Yes | keep behind `#if`; macOS gets a no-op |
| `ArtworkLoader` | app | Yes, **but** hard-codes `kexp.org` / `archive.org` | allowed domains become an init parameter; return a platform-neutral image (macOS has no `UIImage`) |
| `MusicLinks` (Spotify/Bandcamp searches, comment links) | app | Yes | none |
| `SongResolver`, `PlaylistService` (MBID → ISRC → MusicKit) | proposed | Yes | built in StationKit from the start |
| `PlaybackController` | app | Mostly | inject the stream URL and metadata source instead of reading `ResultRetriever` |
| `LiveActivityService` (fetch current play) | proposed | **No** | stays in the KEXP app, as an adapter from `KEXPPowerKit` to a StationKit `NowPlayingSource` protocol |
| `Play`, `Show`, stream bitrates, KEXP branding | library/app | **No** | stay in `KEXPPowerKit` and the app |

**The rule that keeps it generic:** StationKit never imports `KEXPPower` (or any station's API). It defines the seam every station plugs into:

```swift
public protocol Station: Sendable {
    var id: String { get }
    var name: String { get }
    var streams: [StreamOption] { get }                       // e.g. 64 / 160 kbps, or HLS
    func nowPlaying() async throws -> Track?                  // nil during an airbreak / talk segment
    func recentTracks(limit: Int) async throws -> [Track]
}
public protocol ShowProviding: Station { func currentShow() async throws -> ShowInfo }      // optional capability
public protocol ArchiveProviding: Station { /* days, shows, stream-at-time */ }            // optional capability

public struct Track: Sendable, Hashable, Identifiable {
    // title, artist, album, artworkURL, airDate; optional musicBrainzRecordingID, isrc
}
```

`StationKitAdapterKEXP` is the only code that knows both worlds: it wraps `KEXPPowerKit`'s `NetworkManager` and maps `Play` → `Track`, `Show` → `ShowInfo`, and bitrates → `StreamOption`. Station capabilities are separate protocols, so a station with no archive simply does not conform to `ArchiveProviding` and the app hides that section. **A second station needs one adapter package and no changes to StationKit or the apps' logic.**

**Naming (owner decision 2026-11-03):** adapter packages are named `StationKitAdapter<STATION>` with no hyphen (this one is `StationKitAdapterKEXP`), so the repository, package and module names are identical and cannot be confused or collide, and more stations can be added over time.

**Ecosystem intent: could other public radio stations use this? (owner direction 2026-11-03)**
KEXP is a well-funded public station; many public stations lack the resources to build a good app. If the only thing that differs between stations is the endpoint, a shared app plus a small per-station adapter could raise the baseline for all of them. That is a worthwhile goal, and it argues for **scale-readiness in the architecture now**, even though no ecosystem tooling should be built yet.

*What I checked (2026-11-03), to test "only the endpoints change". KEXP, WFUV, All Classical Portland and WBUR all appear on, or stream from, StreamGuys (testimonials: https://www.streamguys.com/about-us/testimonials/; KEXP's stream host is `kexp.streamguys1.com`):*

| Station | Now-playing source | Shape |
|---------|--------------------|-------|
| **KEXP** | HTTP API `/v2/plays` | rich JSON: song, artist, album, art, comment, MusicBrainz IDs, show |
| **WFUV** | `wfuv.org/sites/default/files/player/playlist/now_playing.json` | `{"live": {artist, title, album, art{large,medium,small}, cut_id, duration, event_type, message, purchase_url, timestamp}}`; `event_type` is `GENERICMSG` when no song is on; timestamp is `MMDDYYYY-HHMMSS` **with no time zone** |
| **All Classical Portland** | `daisy.allclassical.org/json/now_play3.json` | **classical metadata**: `composer`, `title` (the work), `conductor`, `ensemble`, `soloist`, `catalog`, `label`, `duration`, `end` (epoch), plus the host |
| **WBUR** | no live track feed found | `api.wbur.org` exposes programs/channels/audio; "now playing" is a program or segment, not a song (I looked at the homepage only; absence of a feed is not proven) |
| **WPRB** (Princeton) | playlists at `playlists.wprb.com`, branded and styled as **Spinitron** (page assets are named `spinitron-*`) | a hosted playlist system used by many college/community stations; its API details are **not yet verified** (I believe it needs a per-station API key; confirm) |
| **WHUR** (Howard) | player at `player.whur.com` streams **HLS** from `source.streamon.fm` | a different hosting stack again (HLS, not Icecast); metadata route not yet found |
| **WXYC** (UNC) | stream from `audio-mp3.ibiblio.org` (Icecast, `icy-metaint: 16000`) | in-stream title stayed **empty for 40 seconds**: inconclusive (a title may only be sent on change, or WXYC may use another source) |
| **KEXP, WFUV, WXYC streams** | in-stream (ICY) metadata | see below |

*In-stream (ICY) metadata, corrected.* I first reported KEXP's stream metadata as "not a drop-in" after reading only the first 8 KB, where `StreamTitle` was empty and the block was a pre-roll ad marker. Watching for 45 seconds shows the opposite: **after the pre-roll block, the title arrives within seconds** on both KEXP (`StreamTitle='Thao - Sick of the Times'` at +1.8 s) and WFUV (`StreamTitle='New Constellations - Dandelion (Live at WFUV)'` at +7.1 s, then an empty title again at +31 s during a non-music event). Both streams use the same ad-marker convention (`adw_ad='true'`, `insertionType='preroll'`), which looks like a StreamGuys-wide feature. So ICY is a viable zero-adapter source if the parser (a) **ignores ad blocks without clearing the last known title**, (b) **treats an empty `StreamTitle` as "no track"**, and (c) accepts that the data is a single `Artist - Title` string (splitting on ` - ` is lossy for artists whose names contain a hyphen) with **no album or artwork**, which must be enriched separately.

*How a multi-station directory does it (Streema, 2026-11-03).* Streema lists 71,000+ stations in 200 countries and is the nearest existing example of "one app, many stations". From its public pages (I did not crawl its player, which its `robots.txt` disallows, and I cannot see its internals), its approach is **not API adapters**. It standardizes on the lowest common denominator: **a stream URL plus a listing the broadcaster maintains** ("your art, your tags, your stream URL, you decide"), submitted through a form. It offers no developer API that I could find, and its pages do not describe song titles. I infer, **without proof**, that any track title it shows comes from in-stream metadata. The lesson is not their code but their data model: a *registry of stations*, each described by a small record, with the player needing nothing station-specific beyond a stream URL.

*Applied here:* that is exactly our tier 2 (stream-metadata station) plus a **station registry** (a public JSON file of station records: id, name, stream URLs and kind (Icecast/HLS), time zone, branding, and an optional adapter id such as `spinitron` or `streamguys-icy`). Stations contribute a record by pull request, which costs a station no hosting, no server and no developer, which suits the goal of helping under-resourced stations. A rich adapter is then an *upgrade* for stations that want an archive, schedule or credits, not a prerequisite for being in the app.

*Spinitron API v2 (read from its OpenAPI spec, 2026-11-03).* Base `https://spinitron.com/api`; resources `/spins`, `/playlists`, `/shows`, `/personas`; page size 20 (max 200); JSON. Facts that shape the design:
- **Keys belong to each station.** "Your API key is in the Spinitron web app… Admin → Automation & API." A shared app cannot use Spinitron for a station unless that station hands over its key.
- **The same key appears to authorize writing.** The spec has `POST /spins` ("Log a Spin") under the same bearer scheme; I could not confirm whether keys can be scoped read-only. **A key must never ship inside an app binary or sit in a public registry file**, because a leaked key could let anyone log spins into a station's playlist.
- **Spinitron asks integrators to cache** ("Do not query the API on every page request you serve"). Hundreds of clients polling every few seconds is the wrong shape; a small cached relay is the right one.
- **There are public widgets with no key** (`widgets.spinitron.com/widget/now-playing-v2?station=<name>`), but they are HTML/iframes; I found no documented public JSON endpoint, and scraping HTML would be fragile.
- **A spin is richer than a pop track, in the way we need:** `artist`, `song`, `release`, `image`, `start`/`end`/`duration`/`timezone`, plus `classical`, `composer`, `work`, `conductor`, `performers`, `ensemble`, `catalog-number`, and standard identifiers **`isrc`, `upc`, `iswc`**. That confirms the credits-based `Track`, and means a Spinitron station can feed song matching directly from its ISRC with no MusicBrainz lookup.

*What this means for a Spinitron adapter:* it is real and high-leverage (the mapping to `Track` is almost one-to-one), but it needs **a per-station relay**: a tiny service (for example a serverless function) holding the station's key as a secret, caching for 10–30 seconds, and exposing a read-only JSON feed. StationKit would define that feed as a **StationKit Now Playing JSON** format and ship relay templates (Spinitron first). The registry record then points at the relay's URL, never at a key. Any station with its own developer can emit the same JSON directly, so this is also how the declarative tier (3) works: "fetch this URL, decode StationKit Now Playing JSON". TuneIn is a different case (below).

*TuneIn (read 2026-11-03): a sink, not a source.* TuneIn's documented "AIR" API is **push-only**: a station's automation sends `title`, `artist`, `album` and a `commercial` flag to `air.radiotime.com/Playing.ashx` with a `partnerId`/`partnerKey` that TuneIn issues on request (tuneinonair@tunein.com). TuneIn documents **no way for a third party to read** now-playing data, and I could not read its terms of use (the policy site is a JavaScript page that returned no text), so I am **not** treating TuneIn as a data source and I am not relying on any undocumented directory endpoint. This does not change the shape of the design; it confirms three things:
- **The real upstream is the station's playout/automation system** (Spinitron, a vendor product, or the station's own API), which is what TuneIn itself is fed from. We read that layer, not TuneIn.
- **`NowPlaying` needs a "not a song" state**: TuneIn's `commercial=true` flag is the same idea as WFUV's `GENERICMSG` and WBUR's program-level "now playing".
- Small stations already depend on vendors to wire their automation to services like TuneIn, so a relay template that a vendor or volunteer can set up is a familiar model for them.

*What this evidence says about the design:*
1. **`Track` must not be "title / artist / album".** All Classical's feed has composer, work, conductor, ensemble and soloist, and no "artist". `Track` should carry an ordered list of **credits** (`role` + `name`) and compute a display line from them. Pop stations fill one performer credit; classical fills several.
2. **"Now playing" is not always a track.** WFUV reports a generic message between songs, and WBUR is a news/talk station. So `Station.nowPlaying()` returns a `NowPlaying` value that is a track, a program/segment, or nothing, not `Track?`.
3. **Time zones are the adapter's job.** WFUV's timestamp has none. `StationConfiguration` carries the station's time zone, and adapters use it.
4. **Artwork is often missing or a placeholder** (WFUV returns a stock image; ICY has none). Artwork needs a resolution chain (station art → MusicBrainz Cover Art Archive via release ID → catalog), and `ArtworkLoader`'s allow-list must cover each station's image hosts via configuration.
5. **A StreamGuys stream-metadata parser is a reusable component** shared by every StreamGuys station, with or without an API.
6. **A registry plus tiers beats per-station code for most stations.** Most small stations need only a stream URL and, at most, ICY. `StationConfiguration` is therefore also the *registry record*, so the same type describes a built-in station, a registry entry and a white-label app.
7. **One adapter can serve many stations when they share a platform.** WPRB (and, if the pattern holds, many others) uses Spinitron. A single `spinitron` adapter, configured per station, could cover all of them, which is the highest-leverage adapter after KEXP's. It depends on Spinitron's API terms and per-station keys, so it needs verification before it is promised.
8. **`StreamOption` must cover both Icecast/Shoutcast and HLS** (WHUR streams HLS), and metadata then comes from ICY or from HLS timed metadata respectively.
9. **Cover the genuine generic part with real fixtures:** four adapters' worth of recorded samples (KEXP, WFUV, All Classical, ICY) are enough to test whether `Station`/`NowPlaying`/`Track` are right *before* any code is written, which is cheaper than finding out from the second adapter.

*Adapter tiers (StationKit would grow into these as evidence arrives, not before):*
1. **Code adapter** (`StationKitAdapter<STATION>`): a station with a rich API and features like an archive. KEXP is this.
2. **Stream-metadata station** (in StationKit): a station with only a stream URL gets `Artist - Title` from ICY or HLS timed metadata, with the StreamGuys ad-marker handling above. KEXP and WFUV both provide it, so it can be tested against two real stations.
3. **Declarative adapter** (a JSON manifest mapping a station's endpoint and fields to `Track`): the literal "only the endpoint changes" case, for stations without developers. Build it only after two code adapters show what really repeats.

*Decision on `StreamingRadioKit`:* **not a separate package.** The generic layer you describe is the `Station` protocol plus these tiers inside StationKit; a third package would restate it. This also keeps `KEXPPowerKit` as exactly what it should be: one station's client that can grow on its own.

*Owner decisions (2026-11-03): the registry-with-tiers model is adopted; KEXP remains the priority, and other stations' fixtures serve as samples and minimal test adapters, not as scope that delays KEXP. The code is MIT-licensed, so reuse and redistribution are already permitted.*

*Cheap rules to follow now so the ecosystem door stays open:*
1. No KEXP identifiers, colors, URLs or strings in StationKit or in the shared app-shell code.
2. Branding, stream list, accent color, and station identity live in one injected `StationConfiguration` value, supplied by the app target. That makes a white-label app a configuration change, not a fork.
3. Station capabilities are separate protocols (already designed), so a small station with no archive or schedule still gets a complete app.
4. Adapters ship with recorded API samples and tests, so another station's developer can contribute one and CI proves it works.
5. `Track` carries credits (role + name), not just artist/album; `NowPlaying` can be a program or nothing.
6. The station's time zone and image hosts are configuration, never assumptions inside shared code.

*What this does not decide, and I cannot:* offering this to other stations is an organizational decision with real costs: it involves KEXP's permission and branding, support for other stations' apps, App Store accounts and review per station, licensing (the code is private today), and who maintains adapters when a station changes its API. Those belong to a conversation with KEXP, not to this proposal.

**Bundle ID (owner decision 2026-11-03):** the iOS, visionOS and macOS apps share one bundle ID, so they are one App Store Connect app with universal purchase; each platform is still its own target with its own entitlements, Info.plist and sandbox settings. The widget extension has its own ID, prefixed by the app's. (The ID is **`com.JPEnterprises.Spinner`** (owner decision 2026-11-03; it replaces `com.JPEnterprises.KEXPPowerExampleSwiftUI`, and the unit-test bundle is `com.JPEnterprises.Spinner.Tests`).)

**Platform readiness (tvOS and watchOS "ready"):**
- StationKit declares iOS 17, macOS 14, visionOS 1, tvOS 17 and watchOS 10 from day one, and CI builds all of them, so a platform that does not compile is caught immediately instead of at the moment a target is added.
- Verified in the 27.2 SDKs: `MediaPlayer`, `AVFoundation`, `MusicKit`, `AppIntents` and `NowPlaying` exist on iOS, tvOS, watchOS and visionOS; `WidgetKit` exists on watchOS and visionOS but **not tvOS**; `CarPlay` is iOS only. Per-API availability inside those frameworks (for example `MPNowPlayingInfoCenter` on watchOS) is checked when each target is built, not assumed.
- No `UIKit` in StationKit's public API (macOS lacks it), so images cross the boundary as `CGImage`/`Data` with a thin SwiftUI `Image` helper.

**CarPlay (iOS target, later, not built here):** CarPlay audio apps are driven by `CPNowPlayingTemplate`, which reads the same `MPNowPlayingInfoCenter` state our `NowPlayingPublishing` already feeds, plus list templates for browsing. So most of what CarPlay needs is a by-product of StationKit's publisher, not a separate UI. It still requires Apple's CarPlay audio entitlement. *On Apple HomeView (apple.com/apple-homeview, read 2026-11-03):* a 7-inch smart-home display (A18, "HomeView software 27.2"), available November 13. Apple says it "supports compatible third-party audio and video apps from your iPhone" and lets you "start content on iPhone and continue on HomeView". The page names no developer tools, CarPlay support, or radio apps, and does not say how third-party apps appear. **So I am not designing a HomeView target.** What we already do is the plausible route in: publish complete Now Playing metadata (artwork, title, credits) and support AirPlay routing (an `AVRoutePickerView` control on the player). The iOS 27 `HomeExtensions` framework is for home *accessory* manufacturers (`HMAccessory` setup and help content) and is unrelated to audio apps.*

**Why separate targets and a separate repo:** per-platform shells, entitlements and menus diverge, and StationKit's tests run with `swift test` in seconds, without a simulator host (today's hosted tests take about 35 seconds).
**Cost, stated honestly:** a second consumer does not exist yet. The mitigation is the dependency rule above and an adapter seam, so StationKit stays honest rather than becoming "the KEXP app in a package".

**Phase 0 (before Phase A):**
1. Create the `StationKit` and `StationKitAdapterKEXP` repositories (private to start; guidelines scaffold; Swift 6; the five platforms).
2. Move the already-generic, already-tested pieces with their tests (`NowPlayingSnapshot`, publisher, `AudioSessionCoordinator`, `ArtworkLoader` with injectable domains, `MusicLinks`); make the public surface explicit.
3. Write `StationKitAdapterKEXP` (test-first, against recorded API samples) so the app asks a `Station` for its now-playing track instead of calling `KEXPPowerKit` directly. The app consumes StationKit and StationKitAdapterKEXP by tagged URL, as it does KEXPPowerKit.
4. Split the single multiplatform target into iOS, visionOS and macOS app targets. *Status 2026-11-04: macOS is split out as `Spinner Mac` (shared sources, own entitlements); visionOS still shares the iOS target.*

#### 3b. Navigation shell
- **macOS and iPad (regular width):** `NavigationSplitView` with a sidebar: Live, Archive, Playlists. Detail pane per selection.
- **iPhone (compact):** `TabView` with the same three destinations, Settings in a sheet.
- One `AppSection` enum drives both; selection is the only shared state. Archive is present but shows "coming soon" until Phase D.

#### 3c. Mac playback and layout (in the separate Mac target)
- `PlayerController` becomes `PlaybackController`. Platform differences are isolated behind small protocols, not `#if` through the file:
  - `AudioSessionCoordinator` stays iOS/visionOS; macOS gets a no-op that satisfies the same protocol (macOS has no `AVAudioSession`).
  - Now Playing publishing via `LegacyNowPlayingPublisher` is unchanged (`MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` exist on macOS), so media keys and Control Center work on the Mac.
- Layout: a resizable window (minimum about 420×560), a "Now Playing" hero with large artwork, the playlist as a `List` with selection, keyboard shortcuts (Space play/pause, ⌘L jump to Live), and a **Playback** menu (Play/Pause, Stream Quality).
- Optional **menu bar extra** (compact now-playing + play/pause). Listed as an open question, not a commitment.

#### 3d. Apple Music playlists (MusicKit)
- `PlaylistService` (protocol) with a MusicKit implementation:
  - `authorize()` via `MusicAuthorization.request()`.
  - `ensureKEXPPlaylist()`: find the user's playlist by stored ID, else by name, else `MusicLibrary.shared.createPlaylist(name:)`. The ID is stored in `UserDefaults`.
  - `add(play:)`: resolve the play to a catalog `Song`, then `MusicLibrary.shared.add(song, to: playlist)`.
- **Resolving the song uses identifiers, not guesses.** KEXP's API already gives each trackplay a MusicBrainz *recording ID* (`recording_id`; 38 of the last 40 trackplays carry one). The pipeline:
  1. `Play.recordingID` → **MusicBrainz** `recording/<id>?inc=isrcs` → one or more ISRCs (checked live: R.E.M. "Blue" → `USWB11004206`, `USWB11400926`; Ceremony "Other Hells" → `US2642664602`).
  2. ISRC → **MusicKit** `MusicCatalogResourceRequest<Song>(matching: \.isrc, equalTo:)` (type-checks against the macOS SDK; iOS 16+/macOS 14+). Try each ISRC and take the song available in the user's storefront.
  3. **If that resolves, add immediately** (with an undo): an ISRC identifies the recording.
  4. **If it does not** (no recording ID, no ISRC, not in the user's catalog), fall back to text search (the existing iTunes lookup) and **ask the user to confirm** the matched title/artist/album before adding.
- **Why not an audio-matching service (the AcoustID/Chromaprint approach in `concordance`)?** Fingerprinting needs audio in hand and returns a MusicBrainz recording ID, which KEXP already supplies. The identification step is done for us; an audio service would add a third party, captured audio and latency to arrive where we start. It stays a last-resort fallback for plays with no MBID (Future Directions).
- **Library change (additive, KEXPPowerKit 4.1.0):** the 2024 model trim dropped `track_id`, `recording_id`, `release_id` and `release_group_id`; `Play` regains them as optional fields, test-first.
- **MusicBrainz etiquette:** needs a descriptive `User-Agent` and about one request per second; results are cached by recording ID; `musicbrainz.org` joins the host allow-list.
- States the UI must show: not authorized, matching, added, already in playlist, no match, failed.
- Platform support verified in the SDK: `MusicLibrary`, `createPlaylist`, `add(_:to:)` and `MusicAuthorization.request()` are available on iOS 16+, macOS 14+ and visionOS 1+.

#### 3e. Widget and App Intents
- **Shared data:** a `LiveActivityService` that fetches the latest play (`limit=1`) and show. The widget and intents call it directly; they do not depend on the player.
- **Widget (WidgetKit):** small/medium "Now Playing" — artwork thumbnail, song, artist, show name. WidgetKit refreshes on the system's budget (on the order of minutes, not seconds), so the widget shows "last played at 3:42 PM", never "live". Interactive buttons (play/pause, add to playlist) are `Button(intent:)`.
- **Control Center control** (`ControlWidgetButton`, iOS 18+, not visionOS/tvOS) for play/pause, behind `#available`.
- **App Intents** (all in a framework-neutral file set shared by app and widget):
  - `WhatsPlayingIntent` — returns "Song by Artist on KEXP" as a spoken/shown result; runs without opening the app.
  - `PlayKEXPIntent` / `PauseKEXPIntent` — conform to `AudioPlaybackIntent` (verified: iOS 17+, macOS 14+) so playback can start in the background.
  - `AddNowPlayingToKEXPPlaylistIntent` — uses `PlaylistService`.
  - `AppShortcutsProvider` with spoken phrases ("What's playing on KEXP", "Play KEXP").
- **Targets and capabilities:** a widget extension target; an App Group so the widget can show the last-known play instantly from shared storage; MusicKit enabled on the App ID and `NSAppleMusicUsageDescription` in Info.plist. **These need action in the Apple Developer portal — flagged early, as the process requires.**

#### 3f. Archive (design only; build after the library work)
- **Prerequisite (library):** finish the async `ArchiveManager` (parked for 27.2). The shell provides the destination; this phase fills it.
- **View:** the 14-day window as a day picker (`ArchiveWindow.days()`), a list of shows for the chosen day (grouped by show/host/genre as the existing models do), a show detail with a start-time picker, and playback from a chosen offset (`getArchiveStreamURL(timestamp:)`).
- Archive playback reuses `PlaybackController` with a finite-duration item; Now Playing for archive reports elapsed time (the snapshot already carries `isLive`).

**New/changed files (indicative):**
`App/AppSection.swift`, `App/RootView.swift`, `Services/LiveActivityService.swift`, `Services/PlaylistService.swift`, `Services/MusicKitPlaylistService.swift`, `Audio Player/PlaybackController.swift` (renamed), `Mac/…Layout views`, `Intents/*.swift`, `KEXPWidget/` (new target), `Archive/ArchiveView.swift` (Phase D).

### 4. API Surface

```swift
enum AppSection: String, CaseIterable, Identifiable { case live, archive, playlists }

protocol LiveActivityProviding: Sendable {
    func currentPlay() async throws -> Play
    func currentShow() async throws -> Show
}

protocol PlaylistServing: Sendable {
    func authorize() async -> PlaylistAuthorization          // .authorized / .denied / .restricted / .notDetermined
    func match(_ play: Play) async throws -> PlaylistMatch?  // what we'd add, for confirmation
    func add(_ match: PlaylistMatch) async throws -> PlaylistAddResult   // .added / .alreadyInPlaylist
}

struct PlaylistMatch: Equatable, Sendable { let songID: String; let title: String; let artist: String; let album: String }

struct WhatsPlayingIntent: AppIntent { /* returns a String result */ }
struct PlayKEXPIntent: AudioPlaybackIntent { }
```

### 5. MCP Schema

N/A — application code. (App Intents are the machine-readable surface for this product: they expose "what's playing" and playback control to Siri and Shortcuts, which is this app's equivalent of the MCP-readiness rule.)

### 6. Constraints & Compliance

- **Concurrency:** Swift 6. Services are actors or `Sendable` structs; `PlaybackController` stays `@MainActor`. Intents hop to the main actor only to touch playback.
- **Safety:** no force unwraps or `try!`; MusicKit and network failures map to typed results, never crashes.
- **Privacy:** playlist adds happen only on an explicit user action (button or intent); the privacy manifest gains the MusicKit/UserDefaults declarations; widget storage holds only the last play's public metadata.
- **Hosts:** artwork and API calls stay behind the existing allow-lists (`ArtworkLoader`, `Router`).
- **Quality gate:** 0 errors / 0 warnings; no new exclusions.

### 7. Source & API Compatibility

**Breaking changes:** none to the library. Within the app, `PlayerController` is renamed `PlaybackController`; its call sites are few (`ResultRetriever`, `PlayerView`, `VideoPlayer`).
**Incremental adoption:** yes, phase by phase. The shell can ship before Mac playback; the playlist feature before the widget.
**Deployment targets:** unchanged (iOS 17, macOS 14). Control Center control behind `#available(iOS 18, *)`.

### 8. Backend Abstraction

N/A.

### 9. Resource Budget

**Data read:**
- Widget refresh: 1 play (`limit=1`, about 1 KB JSON) and 1 thumbnail (the 250 px `thumbnail_uri`, tens of KB) per refresh, at most a few times an hour.
- Live view: 50 plays per refresh every 5 seconds (existing).
- Archive day list: one 14-day window of shows, roughly 170–200 shows (one request at `limit=200`).
**Held vs streamed:** the widget holds one decoded thumbnail. The app keeps at most the 50 latest plays. The "already added" set is capped at 1,000 play IDs.
**MusicBrainz:** at most one lookup per added song, cached by recording ID; cache capped at 500 entries (a few hundred bytes each).
**Growth:** none with uptime; each cap is fixed.
**Budget:** widget extension 10 MB peak (WidgetKit's limit is tighter than the app's; the number is a target to be measured); app artwork cache stays 4 MB; added-IDs set under 50 KB.
**Measured by:** a test that feeds 5,000 plays to the playlist store and asserts the added-ID cap; the widget's memory measured on device with Instruments before release.
**Lifetime:** the app can run for days; the widget runs in short bursts. Neither accumulates.

### 10. Dependencies

**Internal:** `KEXPPower` 4.1.0 (adds MusicBrainz IDs to `Play`), `ArtworkLoader`, `NowPlayingPublishing`, `AudioSessionCoordinator`, `MusicLinks`.
**External (non-Apple):** MusicBrainz web service (public IDs only are sent; descriptive `User-Agent`, about 1 request/second, cached).
**External (Apple):** MusicKit, WidgetKit, AppIntents (all present in the 27.2 SDKs on iOS and macOS; checked).
**Library work needed:** async `ArchiveManager` (Phase D only).
**Portal (user action, and each new target needs its own):** the paid Apple Developer Program team (the project already uses team `BNDA9Y6YV9`); one explicit App ID for the app across iOS, visionOS and macOS (a single bundle ID, so universal purchase) plus one for the widget extension (an extension's bundle ID is prefixed by its app's), each with the **MusicKit** service where it adds to playlists; and one **App Group** (for example `group.com.JPEnterprises.KEXP`) shared by the app and widget. With automatic signing, Xcode can register these from Signing & Capabilities.

### 11. Test Strategy

**Order inside each phase:** failing tests first, then implementation, then the device check.
**Test categories:**
- **Shell:** `AppSection` ↔ selection mapping; a pure `NavigationModel` (what is shown for each size class) tested without a view.
- **LiveActivityService:** decodes a recorded `/v2/plays/?limit=1` response; failure → typed error.
- **SongResolver:** recorded MusicBrainz responses (R.E.M. "Blue" → two ISRCs; Ceremony "Other Hells" → one) through a fake MusicKit adapter. ISRC hit adds immediately; first ISRC misses and second hits; no ISRC → fallback requires confirmation; no MBID → fallback; MusicBrainz down or rate-limited → fallback; cache hit makes no request.
- **PlaylistService (the careful one):** a fake MusicKit adapter. Golden path (authorized, playlist exists, match, add → `.added`), already in playlist, denied authorization, no match, wrong-match confirmation required, duplicate add, network failure. No test touches the real library.
- **Intents:** `WhatsPlayingIntent` result string for a fixture play; airbreak (no song) phrasing.
- **Widget:** timeline entry building for a play and for failure (shows last-known), refresh policy date.
- **Mac playback:** the platform protocol with a fake player, and that `isPlaying` still mirrors `timeControlStatus`.
- **Archive (Phase D):** window days, grouping, offset selection.

**Reference Truth:** SDK interfaces checked for this proposal (`MusicLibrary.createPlaylist`, `add(_:to:)`, `MusicAuthorization.request()`, `AudioPlaybackIntent`, `AppShortcutsProvider`, `ControlWidgetButton`), plus live API responses (play 3726579, show 68216 captured 2026-11-02). Behaviors of Siri, the widget gallery and the real Apple Music library are confirmed by hand on a device, not asserted in tests.

**Validation Trace (REQUIRED):**
- Input: `Play.fixture()` (id 3000448, "I Was Riding My Bike To Work When I Realized I Have No Job" by Teezo Touchdown, album "Making Flippy Floppy").
- Expected: `WhatsPlayingIntent` result == `"I Was Riding My Bike To Work When I Realized I Have No Job by Teezo Touchdown on KEXP"`; widget entry `title == song`, `subtitle == artist`; `PlaylistMatch` for it shows the same title/artist/album before any add.
- These come from our own spec; the independent check is performing each on Brawn.

### 12. Architecture Decision Review

- Amends ADR-003 (publisher seam) — no, extends it: macOS uses the same publisher.
- **New ADR-004:** *The app/widget/intents share a `LiveActivityService`; the player is not a data source.*
- **New ADR-005:** *Navigation is an `AppSection` shell (sidebar on Mac/iPad, tabs on iPhone).*
- **New ADR-006:** *Separate app targets per platform (iOS, visionOS, macOS; tvOS/watchOS kept ready). Station-agnostic code lives in `StationKit`; each station is an adapter package (`StationKitAdapterKEXP`) over its own API client (`KEXPPowerKit`). StationKit never imports a station's API.*
- **New ADR-007:** *Songs are matched by MusicBrainz recording ID → ISRC → MusicKit, with text search plus confirmation only as the fallback.*

### 13. Adversarial Review

**Strongest case for a different approach:** ship only the Apple Music playlist button and the "what's playing" intent. A sidebar shell, a menu bar extra, a widget and a Control Center control add four surfaces to maintain for a one-developer app, and the widget cannot be live.

**Where this design is most likely wrong:**
1. **Song matching.** The MBID → ISRC path is precise, but a MusicBrainz recording can carry several ISRCs, and an ISRC can map to a different release than the one KEXP played (a reissue, a compilation). A near-duplicate is a smaller error than the wrong song. The fallback text search can still return a live version, so it asks first. About 5% of trackplays have no MBID and take the fallback.
2. **Widget freshness.** Users will read "now playing" as live; a widget that is 10 minutes stale is wrong in a way the app never is. The design shows "last played at", but the expectation gap may remain.
3. **Mac playback parity.** `MPNowPlayingInfoCenter` behaves differently on macOS (no `AVAudioSession`, different interruption model); media keys may not route as on iOS.

**What an experienced critic would say:** "You are designing a platform before you've shipped the one feature you built the app for." We proceed in phases ordered by that criticism: playlist and shell first, widget and intents after, archive last.

### 14. Alternatives Considered

**Alternative 1: One multiplatform target with `#if os(macOS)`.** Least wiring, but shells, entitlements and menus diverge enough that `#if` spreads through every file. *Rejected by the owner in favor of a separate Mac target, with shared code in a local package.*
**Alternative 2: Mac Catalyst.** Cheap, but the target is already a native multiplatform one and Catalyst would regress it.
**Alternative 3: Add to the Apple Music library directly via the iTunes track ID, with no confirm step.** Fewer taps, higher wrong-song risk. Kept as a setting ("Add without asking") rather than the default.
**Alternative 4: Share the widget's data through the player's `ResultRetriever`.** Couples the widget to app lifecycle; widgets run when the app does not. Rejected.

### 15. Future Directions

- Could add a Live Activity / Dynamic Island for the current track.
- Could build the stream-metadata tier and, later, the declarative adapter tier (see Ecosystem intent).
- Could add audio fingerprinting (AcoustID/Chromaprint, as `concordance` does) as a last-resort matcher for the ~5% of plays with no MusicBrainz ID, by sampling the live stream.
- Could add CarPlay (needs Apple's audio-app entitlement; confirm eligibility first).
- Could add Spotify playlist add (needs OAuth and a registered app).
- Could add a share extension ("add this link to my KEXP playlist").
- Could reintroduce the iOS 27 `NowPlaying` framework as a second publisher.
- Could sync the "added" set across devices with iCloud key-value storage.

### 16. Open Questions

1. ~~One target or two?~~ Resolved: separate targets. Mac layout resolved (owner, 2026-11-04): a native sidebar app (Live / Archive / Playlists) in a `NavigationSplitView`, with the sidebar showable and hideable (toolbar toggle and View menu via `SidebarCommands`). A menu-bar extra stays a possible later addition, not the primary surface.
   Resolved: the generic package is **StationKit**; adapters are `StationKitAdapter<STATION>`. Resolved: HomeView is Apple's smart-home display (see the note above); licensing is MIT, so reuse is permitted. Resolved (owner, 2026-11-03): repos stay **private until something works**; the iOS, visionOS and macOS apps share **a single bundle ID** (universal purchase); the relay model is adopted; TuneIn was researched and is not a data source (see above).
2. ~~Confirm every add?~~ Resolved: ISRC-resolved songs add immediately with undo; fallback matches ask first. Still open: does the undo suit you, or should the ISRC path also confirm until you trust it?
3. Dedicated playlist name — "KEXP"? One per user, created on first use?
4. Widget sizes: small and medium only, or also a lock-screen accessory?
5. Control Center control on iOS 18+: include in Phase C or defer?
6. Archive playback: start from the show's beginning only, or an arbitrary minute?
7. Are you willing to enable the MusicKit service and an App Group in the Developer portal now? (The widget and playlist phases are blocked without them.)
8. ~~Bundle ID~~ Resolved: `com.JPEnterprises.Spinner`. Still open: the app's *display name* (the product is currently named `KEXPPowerExampleSwiftUI`).

### 17. Documentation Strategy

**Documentation Type:** inline DocC on the services, intents, and `AppSection`; README gains a Features section and a platform matrix (iOS, macOS, visionOS; widget/intents where supported).
**Also updated:** CHANGELOG per phase, `project/master_plan.md` (module structure and roadmap), ADR-004/005, privacy manifest, and a session summary for each phase.
