# Design Proposal: Spinner sends typed health events to the diagnostics hub

**Status:** PROPOSED 2026-11-10. The owner asked for the Spinner uploader after the hub went live on its host (`diagnostics.roseclub.org:9110`, SwiftDiagnosticsHub 0.2.0). Carries out step 4 and the typed-event part of step 2 of `DiagnosticsAndFeedback.md` (approved 2026-11-09), using the client library in `SwiftDiagnosticsClient` (0.2.0: `DiagnosticsUploader`, `DiskQueue`, `ChannelResolver`, `Transport`, the schema validator). **Implemented 2026-11-10, unreleased.** Added the same day, after KEXP's API was down and the app reported none of the failures: `apiFailed(endpoint, outcome, status?)` with a coalescer (a repeated failure once per ten minutes per launch). The live poll does not look at the HTTP status, so it reports an outcome and no status; making the library's router throw a status-carrying error would let it report one. Differences from §4 as built: `FieldDiagnostics` also has an awaitable `send(_:)` (tests await it; `report(_:)` is the fire-and-forget wrapper), `flush()` returns `FlushResult?` (the client's result type has no public initialiser, so a sender with no uploader returns `nil`), and a `requestFlush()` is the non-waiting form the scene-active hook calls. First slice only: typed events from every build. Log chunks from TestFlight builds are the next slice (§15).

**Facts marked (repo) were read in the repositories on 2026-11-10. Anything not checked on a device is marked *unverified*.**

---

## 1. Objective

When a Spinner build fails in a way worth knowing about, or starts after the last run ended badly, send one small, typed, anonymous event to the hub, with no way for a person, a station or a song to travel with it, and nothing at all when the listener has turned the setting off.

## 2. Motivation

**Current situation (repo):** Spinner records a local log and can share it by hand ("Send Diagnostics"), which depends on a listener choosing to send a file. The hub is running and registered Spinner on 2026-11-10 with a deliberately small schema; nothing sends to it. A TestFlight round with no reports means finding out about a failure only if the tester says so.

**What the app can truthfully report today (repo):**
- How the previous run ended: `RunMarker.begin()` returns `PreviousRun` (first launch, ended while active, ended in the background, quit). The registered `launch` kind has the same four codes.
- Rewind fallbacks, each already a log line in `LiveTimeShift` and `AVPlayer`: no audio arrived in time, the local server failed, the "back to live" watch gave up after 40 s.
- **Not available:** a stream failure with an HTTP status. No code path in the app holds one today, so the registered `streamFailed` kind stays unused rather than being fed a made-up number.

**Cost of the status quo:** nothing is learned about a build that fails on someone else's phone unless they say so.

## 3. Proposed Architecture

Five small pieces, all plain types except the settings row:

1. **`FieldEvent`**: an enum of what Spinner may report (`launch(previousRun:)`, `rewindUnavailable(reason:)`), each case converting to the client's `EventRecord` with typed fields only. There is no case that takes a string.
2. **`FieldDiagnostics`**: owns one `DiagnosticsUploader` (endpoint, key, identity, channel, disk queue, transport) and offers `report(_:)` and `flush()`. Fire-and-forget: it never throws, never blocks the caller and does nothing when disabled.
3. **`FieldIdentity`**: builds the client's `AppIdentity` from the bundle (`CFBundleShortVersionString`, `CFBundleVersion`), the platform, the OS version and a coarse device class (`iPhone`, `iPad`, `Mac`, `AppleTV`), not a model identifier.
4. **The setting**: `UserDefaults` key, **on by default**, read at each send (`enabled:`), with a "Diagnostics" section in Settings on every platform (a switch and a plain statement of what is sent).
5. **The schema**: Spinner's schema is a JSON file in this repo, `project/diagnostics/spinner-schema.json`, the source of truth. The hub's apps file takes its Spinner entry from it. A test validates every event the app can produce against that file with the client's own `SchemaValidator`, so the app and the server cannot drift without a test failing.

**Where it is called from:** the app's `init` (the launch event, using the value `RunMarker.begin()` already returns); scene becoming active (`flush()`, to retry what a failed send left on disk); the three rewind fallbacks (`report(.rewindUnavailable(...))`, next to the log line they already write).

**Channel:** `ReceiptChannelResolver.bundle`. A Debug build is `.development` and **sends nothing** (the client's default `sendsFromDevelopment` is off). A Release build with no receipt resolves to `.appStore`, the most restrictive channel; a TestFlight build should resolve to `.testFlight` (*unverified*: the `sandboxReceipt` convention has not been seen in this project). Slice 1 sends only typed events, which every channel may send, so a wrong channel cannot leak text.

## 4. API Surface

```swift
enum FieldEvent: Sendable, Equatable {
    case launch(previousRun: PreviousRun)
    case rewindUnavailable(RewindReason)

    var record: EventRecord { get }          // typed fields only
}

enum RewindReason: String, Sendable, CaseIterable {
    case noAudioInTime, serverFailed, gaveUpWatching
}

struct FieldIdentity {
    static func make(info: [String: Any], platform: Platform, osVersion: String, deviceClass: String) -> AppIdentity
}

struct FieldDiagnostics: Sendable {
    static let shared: FieldDiagnostics
    init(uploader: DiagnosticsUploader)      // tests inject one over a fake transport
    func report(_ event: FieldEvent)         // non-blocking, never throws
    func flush()
}

enum FieldDiagnosticsSetting {
    static let key = "fieldDiagnosticsEnabled"
    static func isOn(_ defaults: UserDefaults = .standard) -> Bool    // true when never set
}
```

## 5. MCP Schema

Not applicable.

## 6. Constraints & Compliance

- **The privacy line is the types.** `launch` carries one of four codes; `rewindUnavailable` one of three. No free text, no show, song or station identifier, no setting values, no persistent ID (the client makes a random launch ID held in memory), no address (the hub discards it).
- Swift 6 strict concurrency; `FieldDiagnostics` is `Sendable` over an actor; no `@unchecked Sendable`.
- A failing queue, send or setting must never crash or block the app. The CarPlay rule (sync-before-return for the local log) is unchanged, and this path is separate from it.
- No third-party SDK; the only destination is the owner's server over TLS (a Let's Encrypt certificate on a non-standard port, which App Transport Security permits).
- **Privacy manifest:** `PrivacyInfo.xcprivacy` gains a `NSPrivacyCollectedDataTypes` entry for diagnostic data (not linked to the user, not used for tracking). The exact Apple category and purpose strings are *unverified* and are re-read at submission; the App Privacy label changes from "data not collected" before any App Store release. The EU's rules on sending from a device are not settled here (this is not legal advice).
- Quality gate 0/0, no suppressions; logger calls annotated.

## 7. Source & API Compatibility

Additive. `DiagnosticLog.record` keeps its form. The new package dependency is SwiftDiagnosticsClient (`https` URL, up to next minor of 0.2.0), added to the iOS, Mac and TV targets as DiagnosticsKit was. **Not on the watch app in this slice** (it has no diagnostics code today; a separate step, §15).

## 8. Backend Abstraction

Not compute-intensive. Skipped.

## 9. Resource Budget

A launch sends one event of tens of bytes; a fallback sends one more. The queue is capped at 1 MB on disk by the client and drops the oldest. Requests are one per flush, over the system's `URLSession`. Battery and data cost are negligible; *unverified:* the first real numbers from a device.

## 10. Dependencies

`SwiftDiagnosticsClient` (ours, private, 0.2.0), which brings `SwiftRedaction` (ours). Nothing third-party.

## 11. Test Strategy

Red first, Swift Testing, in the existing iOS and Mac test targets.
- **`FieldEvent`**: each case becomes the expected kind, severity and typed fields; an ended-while-active launch is a warning, the others info.
- **Against the schema:** every `FieldEvent` value (all `PreviousRun` and `RewindReason` cases) is decoded from the real `project/diagnostics/spinner-schema.json` and passes the client's `SchemaValidator` for the app channel; a value outside it is refused. This is the drift guard.
- **`FieldIdentity`**: version and build from an info dictionary, tokens for platform and device class, a missing key does not crash.
- **`FieldDiagnostics` over a fake transport**: `report` produces one request whose envelope decodes, names `spinner`, carries the identity, the channel and exactly the event; nothing is sent when the setting is off; the setting defaults to on; a transport failure keeps the event queued and the next `flush` sends it; a Debug-channel uploader sends nothing.
- **Setting**: `isOn` is true when never set, false once turned off, read at each send (turning it off mid-session stops the next send).
- **Not testable offline:** a real send to the live hub, the channel on a TestFlight build, and delivery from a phone on cellular. Checked by hand after install (the hub's issue list shows the event), and recorded as unverified until then.

## 12. Architecture Decision Review

- **Decision (ADR):** the schema is a file in the app's repo and the hub's registry is derived from it, not the other way round. The app is the thing that knows what it can send; a test ties them together.
- **Decision (ADR):** slice 1 sends only what the app can truthfully say today (`launch`, `rewindUnavailable`); `streamFailed` waits for a real status.
- **Decision (ADR):** on by default, with a switch, as `DiagnosticsAndFeedback.md` §3 decided ("every build, automatic"). *Open question 1.*
- **Layer:** plain value types and one actor; the settings row is the only UI.

## 13. Adversarial Review

- **"The key is in the app, so anyone can post as Spinner."** Yes: the key identifies the app, it is not a secret (as `DiagnosticsHub.md` states). The server validates every event against the schema, so a forged event is at worst a valid-shaped fake `launch`, and the per-key and per-address limits bound the volume. App Attest is the deferred hardening.
- **"A launch event on every launch is volume and a pattern."** One event per launch, no persistent ID, no timing beyond the request time the hub already discards after the retention window; the launch ID is random per run and not linkable across runs.
- **"The listener was never asked."** The setting is a visible switch with a plain statement, on by default as approved; a TestFlight tester has agreed to be a tester. An App Store release additionally needs the privacy label and a read of the EU rules (§6).
- **"A wrong channel leaks text."** Slice 1 carries no text on any channel, so it cannot. The channel matters from slice 2.
- **"A send blocks launch."** `report` returns at once; the queue write and the send happen on the uploader's actor, off the main actor.
- **"The hub is down."** The event stays queued on disk, the client backs off exponentially, and the app is unaffected.

## 14. Alternatives Considered

1. **Send the log automatically.** Rejected by the approved design: logs go out only from TestFlight after a disclosure, never from the App Store.
2. **Send nothing until the full pipeline (stream status, MetricKit) exists.** Rejected: `launch` and the rewind fallbacks are real signals now, and the pipeline needs a real first event to be proven end to end.
3. **Make the hub's registry the schema's source.** Rejected (§12).
4. **A setting that is off by default.** Considered: respects the listener more, and would make the data nearly empty, which defeats the point for a small user base. Left to the owner (*Open question 1*).

## 15. Future Directions

1. Slice 1 (this proposal), then confirm one event reaches the hub from a real device.
2. Slice 2: session log lines from TestFlight builds only: a one-time disclosure on first launch of the build, a `logChunk` kind (text, TestFlight channel only) in the schema, and the client's `send(logChunk:)`.
3. `streamFailed(status)` and `apiFailed` once a code path holds a status; `playbackStalled`.
4. MetricKit events (an experiment, per the approved design).
5. The watch app; the same package, its own target.
6. WineTaster (its own proposal; its schema file lives in its repo).

## 16. Open Questions

1. **Default on or off?** *Recommendation:* on, as the approved design says, with the switch in Settings. Turn it off for the App Store release if the privacy label or EU reading says so.
2. **Debug builds send nothing.** Good for development; it means a developer cannot see the pipeline from an Xcode run. *Recommendation:* keep it, and check from a Release install.
3. **Where the key lives.** *Decided 2026-11-10 (owner):* not in git, because the repository is public. An untracked `Config/Secrets.xcconfig` supplies a build setting, the Info.plist carries it, and the app reads it; a build without it sends nothing. The proposal first recommended the constant in source; a check found the repository public and the owner chose to keep it out.
4. **Platforms in slice 1:** iPhone, iPad, Mac, Apple TV. *Recommendation:* yes; the watch is separate.

## 17. Documentation Strategy

**Documentation Type:** API docs on the new types, plus CHANGELOG ("Unreleased"), README status, the master plan's status and Last Updated, and a pointer from `DiagnosticsAndFeedback.md` to this proposal. The Settings footer states what is sent in plain words. `project/diagnostics/README.md` says how the schema file reaches the hub (copy the entry into the hub's apps file; restart it) and how to check an event arrived.
