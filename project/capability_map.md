# KEXPPower Capability Map

**Purpose:** Scannable inventory of what this project can do — feature areas, key types, external interfaces, and application domains.

**Last reviewed:** 2026-11-14. **Partial:** only the Diagnostics area below has been mapped. Playback, the archive, Live Rewind, CarPlay, widgets, the watch app, Siri and Shortcuts and the Mac and TV targets are not yet described here; see `project/master_plan.md` ("What's Working") for those until they are.

> **Format reference:** See `development-guidelines/rules/capability_map.md` for field definitions,
> naming conventions, and maintenance rules.

---

## Diagnostics (opt-in health reports)

**Key types:** `FieldConsent`, `FieldDiagnostics`, `DiagnosticsSettingsSection`, `MetricKitSubscriber` (consent and views from `SwiftDiagnosticsConsentUI`, mapping from `SwiftDiagnosticsMetricKit`, both in the SwiftDiagnosticsClient package)
**Interfaces:** the first-launch question (an ordinary iOS sheet, asked once), Settings > Diagnostics, and an upload to the owner's diagnostics hub (`POST /v1/ingest`, `X-Diagnostics-Key`). Nothing is sent, and no connection to the hub is made, until the person agrees; turning it off stops sending at once and deletes any report still waiting on the device.
**Applications:** the owner learns that the app is crashing, hanging or failing its network requests, and how stable each build is, without any identifying information leaving the device. A report carries the app version, the system version, the kind of device and a random number that is new each launch. Kinds: launch and rewind health, coalesced API failures, and (iPhone, iPad, Mac, Vision Pro, not Apple TV) the operating system's crash, hang, CPU and disk-write reports and a few coarse daily numbers through MetricKit.
**Dependencies:** SwiftDiagnosticsClient 0.3.1 (consent, wire contract, queue, MetricKit mapping); the hub's apps file must register schema version 4 (`project/diagnostics/spinner-schema.json`); an ingest key in `Config/Secrets.xcconfig` (never committed; `Secrets.xcconfig.example` carries a decoy key that alerts the owner if anyone uses it).
