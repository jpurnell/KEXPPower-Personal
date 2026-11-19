# KEXPPower Capability Map

**Purpose:** Scannable inventory of what this project can do — feature areas, key types, external interfaces, and application domains.

**Last reviewed:** 2026-11-19. **Partial:** only the Diagnostics and Playing to other surfaces areas below have been mapped. Playback, the archive, Live Rewind, CarPlay, widgets, the watch app, Siri and Shortcuts and the Mac and TV targets are not yet described here; see `project/master_plan.md` ("What's Working") for those until they are.

> **Format reference:** See `development-guidelines/rules/capability_map.md` for field definitions,
> naming conventions, and maintenance rules.

---

## Diagnostics (opt-in health reports)

**Key types:** `FieldConsent`, `FieldDiagnostics`, `DiagnosticsSettingsSection`, `MetricKitSubscriber` (consent and views from `SwiftDiagnosticsConsentUI`, mapping from `SwiftDiagnosticsMetricKit`, both in the SwiftDiagnosticsClient package)
**Interfaces:** the first-launch question (an ordinary iOS sheet, asked once), Settings > Diagnostics, and an upload to the owner's diagnostics hub (`POST /v1/ingest`, `X-Diagnostics-Key`). Nothing is sent, and no connection to the hub is made, until the person agrees; turning it off stops sending at once and deletes any report still waiting on the device.
**Applications:** the owner learns that the app is crashing, hanging or failing its network requests, and how stable each build is, without any identifying information leaving the device. A report carries the app version, the system version, the kind of device and a random number that is new each launch. Kinds: launch and rewind health, coalesced API failures, and (iPhone, iPad, Mac, Vision Pro, not Apple TV) the operating system's crash, hang, CPU and disk-write reports and a few coarse daily numbers through MetricKit.
**Dependencies:** SwiftDiagnosticsClient 0.3.1 (consent, wire contract, queue, MetricKit mapping); the hub's apps file must register schema version 4 (`project/diagnostics/spinner-schema.json`); an ingest key in `Config/Secrets.xcconfig` (never committed; `Secrets.xcconfig.example` carries a decoy key that alerts the owner if anyone uses it).

---

## Playing to other surfaces (AirPlay receivers, CarPlay, future wearables)

**Key types:** `PlaybackSource`, `LivePlan`, `DirectReason`, `PlaybackCapabilities` (`Diagnostics/PlaybackSource.swift`); `PlayerController` (`playLive`, `routeDidChange`, `liveItem(url:)`, `liveItemWentAway`); `LiveStartRunner`, `LiveStartWatch`, `LiveStartEvidence`.
**Interfaces:** nothing the listener configures. Live plays through the 10-minute recording where the phone renders the sound, and the stream itself on a receiver or an unknown route; the controls (rewind or not) follow that plan. The journal records `live plan: direct (…)`, the start's phases, route changes, audio-session actions and `the live item went away`.
**Applications:** a home display or HomePod plays KEXP live from the phone's handoff with the track's title and art, independent of the phone's battery, and keeps playing through an answered FaceTime Audio call. A new surface (a car, glasses) is one line in `PlaybackSource` plus an observation.
**Dependencies:** ADR-011 (amends ADR-010); the audio route and `AVPlayer.isExternalPlaybackActive`; `StationKit`'s `AudioSessionCoordinator`. Unverified: a real car, other receivers, a cellular or declined call.

## Links into the app (`spinner://`)

**Key types:** `SpinnerLink` (`.open`, `.live`, `.playLive`, `.archive`, `.archiveDay`, `.settings`, and `.probe` on a debug iOS build; `Kind` navigate or act; `init(url:)` for the Top Shelf, `init(notificationURL:)` for a notification), `AppNavigation` (section, a requested archive day taken once, Settings, a debug panel) (`TV/TopShelfContent.swift`, `AppSection.swift`); consumed by `RootView`, `ArchiveView`, `SettingsButton` and the app's `onOpenURL`.
**Interfaces:** `spinner://open`, `live`, `live/play` (acts), `archive`, `archive/2026-11-18` (the station's day), `settings`, `probe/archive`, `probe/live` (debug). The scheme is registered in the iOS, Mac and tvOS Info.plists. A link that arrives from a notification is read with `init(notificationURL:)`, which refuses every link that acts.
**Applications:** a hub alert, delivered through the Inbox (and later Spinner's own push), can open the app at the place to look: a day's archive, Settings, a debug panel. Design: `Tools/SwiftPush/project/plans/upcoming/DeepLinks.md` (Appendix A).
**Dependencies:** SwiftPush 1.0.0-beta.3 and the push hub 1.2.0 for an alert to carry a link; the Inbox for it to open one. Unverified on a device. Not done: a link to a single show (the archive's show identifier is not chosen) and the Mac's Settings window (a separate scene).
