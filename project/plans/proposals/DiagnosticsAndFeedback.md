# Design Proposal: Diagnostics and Tester Feedback (finding bugs in TestFlight and App Store builds)

**Status:** PROPOSED 2026-11-09, revised the same day after the owner settled the privacy line. Owner: "we want to make sure we can track down bugs as efficiently as possible, particularly in these TestFlight builds"; "I'd rather have them just sent to a server, automatically ingested and processed, so that we can surface issues in close to real time without a burden on the user"; agreed to the split by channel and a 30-day retention; "We would absolutely want to implement MetricKit". Pairs with `DiagnosticsHub.md` (the server this client talks to), `quality-gate-swift-project/plans/proposals/LoggingMetricKit.md` (the check that an app adopts MetricKit), and `SwiftReleaseKit/project/plans/proposals/MultiPlatformRelease.md` §4a and §4b.

**Built 2026-11-09 (client, local part):** the local log is `DiagnosticsKit`'s `EventJournal` in `.written` durability behind the unchanged `DiagnosticLog.record` calls, and "Send Diagnostics" is `DiagnosticShareButton` in Settings. Still to build: the typed events and uploader (from `SwiftDiagnosticsHub`'s client library), the per-launch header and clean-exit marker, the channel resolver, and the MetricKit experiment.
**Built 2026-11-10 (typed events and uploader, first slice):** see `FieldDiagnostics.md`.

**Facts marked (repo) were read in this repository on 2026-11-09. Anything about Apple's services or frameworks that was not checked is marked *unverified*.**

---

## 1. Objective

When something goes wrong in a Spinner build, the developer sees it within minutes, with enough context to act, and the listener does nothing. What leaves the device depends on the **channel**: a TestFlight build sends its full diagnostic log automatically; an App Store build sends only fixed-shape health events. MetricKit is adopted in every app target, so Apple's crash, hang and exit reports reach the same pipeline. The privacy line is enforced by the code, not by a convention.

## 2. Motivation

**Current situation (repo):**
- `DiagnosticLog` writes timestamped lines to `Application Support/Diagnostics/spinner-log.txt`, each synced before `record` returns, trimmed to 64 KB; about 45 `record` calls (player, CarPlay, Siri intents, live rewind).
- It can only be read with `devicectl` on a cable-connected device. A tester cannot reach it. That is how we learned on 2026-11-09 that Siri never reached the app.
- **No MetricKit anywhere** (no match in the app or in the quality gate's source), no network reporting, no in-app send, no build/OS/settings header in the log, no record of whether the last run ended cleanly.
- TestFlight shows crashes and screenshot feedback, but not what the app was doing before (*unverified until the first build*).

## 3. The privacy line

**Collect health, not behavior.** A record of what someone listened to and when is the sensitive thing in a radio app, even with no accounts.

| | Allowed | Never |
|---|---|---|
| **Every build, automatic** | A typed event: what failed (a case of an enum), an error code or HTTP status, app version and build, OS version, device model class, platform, channel, a random per-launch ID that is never saved, a time. Station-side facts (an archive show's file is damaged; the stream returned 503). MetricKit crash, hang and exit events, as typed fields. | Any persistent identifier (IDFA, IDFV, an installation ID), anything linking one launch to the next, the IP address (the server discards it), Apple Music data (library, playlists, the user token, which songs were saved), location, free text typed by the user, Settings values beyond coarse buckets. |
| **TestFlight builds only, automatic** | Everything above, plus the session's log lines, after a one-time disclosure the tester sees on first launch of the build. Testers agreed to be beta testers. | The same "never" column. Log lines are scrubbed before they leave. |
| **App Store builds** | "Send Diagnostics" in Settings: the listener chooses to share the full log for one bug. | The full log is never sent automatically. |

**The enforcement is in the types.** The uploader accepts a `DiagnosticEvent` and a `LogChunk` (TestFlight only), never an arbitrary string, so a careless log line in an App Store build cannot reach the network.

**Cost:** the App Privacy label changes from "data not collected" to declaring **Diagnostics** (crash data, performance data, other diagnostic data) as *not linked to the user* and *not used for tracking* (*unverified:* Apple's exact categories; reread at submission). The EU's rules on storing or sending from a device are not settled here and need a read before an App Store release (this is not legal advice).

## 4. Proposed Architecture

1. **A better local log** (`DiagnosticLog`): a header per launch (version, build, OS, device class, settings buckets, channel), a session ID, levels, two files so the previous launch survives, a per-minute line budget, and a clean-exit marker.
2. **Typed health events** (`DiagnosticEvent`): the things worth knowing without the log, each with fixed fields and a stable code. To start: `streamFailed(status)`, `playbackStalled(bucket)`, `liveRecordingGap`, `archiveShowUnavailable(showID)`, `apiFailed(endpoint, status)`, `rewindUnavailable(reason)`, `intentFailed(name, reason)`, `previousRunEndedUnexpectedly`, and the MetricKit events (item 6).
3. **Channel** (`BuildChannel`: `.development`, `.testFlight`, `.appStore`), read from the receipt (*unverified on this OS: TestFlight builds carry `sandboxReceipt`*), defaulting to `.appStore` when unsure, so an uncertain build sends less.
4. **Uploader** (`DiagnosticsUploader`): a disk-backed queue, batched, gzipped, sent over a background `URLSession`, with backoff and a cap that drops the oldest; sends nothing when the setting is off or the channel forbids it.
5. **Scrubber** (`LogScrubber`): removes anything shaped like a token, an email, a long hex or base64 run, a home-folder path or an Apple Music identifier from a line before it leaves. Defense in depth; the line itself is the types.
6. **MetricKit** (`MetricKitCollector`): **an experiment in the first TestFlight round, not a requirement.** The owner (2026-11-09) is not yet sure what it adds beyond TestFlight's and Xcode Organizer's own crash and hang data, so it is built small, kept behind `#if canImport(MetricKit)`, and judged on what a real payload shows (§4a, §16 question 6). The typed events and the clean-exit marker do not depend on it.
7. **Settings:** a Diagnostics section: what this build sends, a switch for automatic health events, "Send Diagnostics" (manual, full log, share sheet), and a read-only view of the last lines for the owner.

### 4a. What adopting MetricKit takes (beyond importing it)

*Everything about MetricKit's behavior here is from general knowledge of the framework and **unverified on this machine**; each item is a thing to confirm with a real payload.*

1. **A subscriber, registered early.** One object conforming to `MXMetricManagerSubscriber`, added with `MXMetricManager.shared.add(_:)` as the app launches (the app's init, before any window), and kept alive for the process. Two delegate methods: one for daily metric payloads, one for diagnostic payloads (crashes, hangs, CPU and disk-write exceptions). Registering late can miss the payloads delivered at launch.
2. **Save before doing anything else.** Payloads arrive on a background queue, sometimes right at launch. The first act is to write the raw JSON (`jsonRepresentation()`) to disk, then convert; an upload failure must not lose a crash.
3. **Convert to typed events.** A crash becomes `.crash(exceptionType, signal, terminationReason, callStack)` where the call stack is a typed list of frames (binary UUID, offset, an image name), not a string. A hang becomes `.hang(seconds bucket, callStack)`. The daily metrics become a few numbers worth tracking: **app exit counts by reason** (foreground and background; for an audio app the background reasons are the valuable ones: memory pressure, a watchdog, a background task that ran out of time), launch time, hang rate, peak memory, disk writes, cellular data, animation hitches. Only these fields; no free text.
4. **De-duplicate.** A payload covers a time window; key each event by its window and content so a re-delivery is not counted twice.
5. **Symbolication is a separate pipeline.** A call stack tree holds addresses, not function names. To read it the server needs the build's **dSYMs** and the binary UUIDs. Today nothing keeps them: **the release tool must save each archive's dSYMs per build and upload them to the server** (a new step in `MultiPlatformRelease.md`), and the server symbolicates (macOS `atos` or `llvm-symbolizer`). Until then a crash is a list of addresses (the Xcode Organizer symbolicates Apple's own copy, so it still has a use).
6. **Join to what the app was doing.** A MetricKit crash arrives on a later launch and carries no session ID of ours. The clean-exit marker (§4 item 1) tells the next launch that the last one did not finish and which session that was; the typed `crash` event carries that previous session's random launch ID, and in TestFlight the server then attaches that session's log chunk to the crash. The match is by time window and build, a heuristic (*unverified*).
7. **Every app target and every extension.** The app, and on each platform's own process (the Mac app, the watch app, the TV app). Whether MetricKit covers an app extension (the widget, Top Shelf) or only the host app is *unverified*; each target registers its own subscriber if it can.
8. **Platform availability.** Behind `#if canImport(MetricKit)`; whether watchOS, tvOS and visionOS have it, and which payload types each delivers, is *unverified* and recorded per platform as it is checked. Where a platform lacks it, the typed events and the clean-exit marker are the fallback.
9. **Delay.** Metric payloads arrive about once a day and diagnostic payloads on the next launch after the event. MetricKit complements the live events; it does not replace them.
10. **Testing.** A real payload cannot be fabricated. Fixtures are recorded real payload JSON files (once one exists), plus Xcode's Debug menu simulation of MetricKit payloads (*unverified* wording) for the first run. The quality gate checks that the subscriber exists (`LoggingMetricKit.md`); the conversion is tested against fixtures; delivery is checked on a device and recorded.
11. **Privacy.** A payload holds no user identity; the call stack is our own code's addresses. It still passes through the typed events, so it obeys the same line.

## 5. API Surface

```swift
enum BuildChannel: Sendable { case development, testFlight, appStore }

enum DiagnosticEvent: Sendable, Codable, Equatable {
    case streamFailed(status: Int)
    case playbackStalled(seconds: StallBucket)
    case archiveShowUnavailable(showID: String)
    case apiFailed(endpoint: Endpoint, status: Int)
    case intentFailed(name: String, reason: String)       // `reason` is a fixed code, validated by the server
    case crash(exceptionType: String, signal: Int?, termination: String, stack: [StackFrame], previousLaunch: String?)
    case hang(seconds: StallBucket, stack: [StackFrame])
    case exits(window: DateInterval, counts: [ExitReason: Int])   // from the daily metrics
    // …each case carries only fixed, typed, non-personal fields
    var code: String { get }                               // stable: the server groups by it
}

struct DiagnosticLog {                                     // existing; gains
    enum Level: String, Sendable { case info, notice, warning, error }
    func record(_ category: String, _ message: String, level: Level = .info)
    func startSession(build: BuildInfo, channel: BuildChannel) -> String
    func previousSessionEndedCleanly() -> Bool
    func report(including: [ReportSection]) -> String
}

#if canImport(MetricKit)
final class MetricKitCollector: NSObject, MXMetricManagerSubscriber, Sendable {
    static func start(storingIn: URL, sink: DiagnosticsUploader)   // registers; call from the app's init
}
#endif

actor DiagnosticsUploader {
    init(endpoint: URL, appKey: String, channel: BuildChannel, queue: DiskQueue, enabled: @Sendable () -> Bool)
    func send(_ event: DiagnosticEvent) async
    func send(logChunk: LogChunk) async                    // refuses unless channel == .testFlight
}

struct LogScrubber { static func scrub(_ line: String) -> String }
```

The event protocol, envelope, scrubber, queue and uploader live in a small package, `SwiftDiagnosticsKit` (in the SwiftDiagnosticsHub repo), so WineTaster and later apps reuse them with their own event cases.

## 6. MCP Schema

Not applicable on the client. The server exposes one (`DiagnosticsHub.md` §5).

## 7. Constraints & Compliance

- No third-party analytics SDK; the only network destination is the owner's server.
- No persistent identifier; the per-launch ID is generated at launch and held in memory.
- `privacy-manifest` checker satisfied; the manifest declares the Diagnostics data types.
- Swift 6 strict concurrency; `DiagnosticLog` stays a `Sendable` value type; a failing write or send must never crash or block the app.
- CarPlay: the sync-before-return rule for log lines stays (CarPlay has ended the process with an exception before).
- Battery and data: background sends only; batches capped at 64 KB; log chunks on Wi-Fi only (§16).

## 8. Source & API Compatibility

Additive. `record(_:_:)` keeps its two-argument form. Existing log lines are unchanged. The file names stay, plus `spinner-log-previous.txt`.

## 9. Backend Abstraction

Not compute-intensive. Skipped.

## 10. Resource Budget and Dependencies

- Log: 256 KB per file, two files. Target under 30 lines per minute at `info` in a ten-minute playback session; high-rate events recorded on change, not per tick.
- Upload: health events are tens of bytes; a TestFlight log chunk is capped at 64 KB per request and the queue at 1 MB; saved raw MetricKit payloads at 10 or 1 MB, whichever is smaller.
- Dependencies: `MetricKit` (system); `SwiftDiagnosticsKit` (new, ours, no third-party dependencies).

## 11. Test Strategy

Red first, Swift Testing.
- **The privacy line, as tests:** an `.appStore` uploader refuses a `LogChunk`; a `.development` build sends nothing by default; an unknown channel resolves to `.appStore`; no `DiagnosticEvent` case has a free-form `String` field except validated codes (a test enumerates every case and its field types); the scrubber removes each secret-shaped fixture and keeps ordinary lines.
- `DiagnosticLog`: header once per session; levels; two-file rotation keeps the last launch; the cap trims whole lines; the clean-exit marker; an unwritable folder does not throw.
- `DiagnosticsUploader` with a fake transport: batches, retries with backoff, drops oldest past the cap, sends nothing when disabled, survives a relaunch.
- `MetricKitCollector`: recorded payload fixtures convert to the expected typed events; a duplicate payload is counted once; the raw payload is saved before conversion (a conversion that throws still leaves the file).
- `report(including:)`: the sections asked for, in order; settings from an injected `UserDefaults` suite.
- **Not testable offline, checked by hand and recorded:** the share sheet, MetricKit delivery, the receipt-based channel, a background upload on a locked phone, the server end to end.

## 12. Architecture Decision Review

- **ADR:** the privacy line is enforced by types and by channel, not by review.
- **ADR:** a small shared client package, so every app gets the same line.
- **ADR:** MetricKit is an experiment, and the quality-gate rule for it is advisory and opt-in (only projects that declare a distribution are evaluated, as a note, not a warning).
- **Layer:** `DiagnosticLog`, the event enum, the scrubber and the queue are plain types; the settings view and the MetricKit subscriber are the only platform code.

## 13. Adversarial Review

- **"The channel check is wrong and an App Store build sends a full log."** Default is `.appStore`; the uploader refuses a log chunk unless the channel is positively `.testFlight`; the server rejects a log chunk for an app build registered as App Store. Two checks, one on each side.
- **"A new event case smuggles in a string."** The field-types test enumerates the cases.
- **"The scrubber misses something."** Second line of defense; the first is that App Store builds never send log lines.
- **"A crash is an unreadable list of addresses."** Until dSYMs are kept and uploaded (§4a item 5). Called out as a required release-tool step, not left implicit.
- **"The log fills with noise."** Rotation, the line budget, the previous-launch file.
- **"A crash leaves no trace."** Lines are synced before return; MetricKit adds Apple's report next launch; the clean-exit marker records that the last run did not finish.
- **"Time and device class together re-identify someone."** The per-launch ID is random and unsaved; the server keeps coarse device class, drops the IP, and keeps events 30 days.
- **"MetricKit does not cover our extension or a platform."** §4a items 7 and 8; the fallback is the typed events.

## 14. Alternatives Considered

1. **Manual send only.** Rejected by the owner's goal (no burden, near real time); kept for the App Store path.
2. **A third-party service (Sentry, Firebase).** Rejected: an SDK, an account, and a privacy label we do not control.
3. **One policy for every channel.** Rejected: too permissive for the App Store, too thin to debug a beta.
4. **TestFlight and MetricKit alone.** Rejected: neither shows what the app was doing, or non-crash failures such as a stalled stream or a failed Siri intent.
5. **MetricKit as a requirement in every app.** Considered, then pulled back by the owner on 2026-11-09: its value over TestFlight and Organizer is unproven for a small user base, so it is an experiment and the quality-gate rule is advisory and opt-in (`LoggingMetricKit.md`).

## 15. Future Directions

Order of work:
1. **Audit** each subsystem for what a report needs (playback start, stall and recovery; stream errors with status; live-recording gaps and the rewind window; archive and API failures; intents; widget and Control Center; Watch connectivity; the Top Shelf). Recorded in `project/checklists/CURRENT_Diagnostics.md` with line volume at each point.
2. `SwiftDiagnosticsKit`: envelope, event protocol, scrubber, queue, uploader, with the privacy tests.
3. The log changes (header, levels, session, two files, budget, clean-exit marker) and the Settings section.
4. `MetricKitCollector` in the iPhone app; record a first real payload as a fixture; then the other targets.
5. The server (`DiagnosticsHub.md`) running; a real event from a TestFlight build reaching it.
6. dSYM retention and upload in the release tool; server-side symbolication.
7. Wire typed events at each error path from the audit.
8. The "What to Test" text from the CHANGELOG, generated by the release tool, telling testers what the build sends.

## 16. Open Questions

1. **Watch and Apple TV.** Does each talk to the server itself? *Recommendation:* TV and phone yes; the watch through the phone first (WatchConnectivity reliability *unverified*).
2. **MetricKit on watchOS, tvOS and visionOS, and for app extensions** (*unverified*). Recorded per platform as checked.
3. **Cellular.** *Recommendation:* health events yes; log chunks on Wi-Fi only.
4. **Automatic health events in App Store builds: on by default and visible, or off until chosen?** *Recommendation:* on, visible, easy to turn off, disclosed in the label and a first-run note.
6. **What does MetricKit add here?** Candidates: exit reasons by cause (for a background audio app, memory-pressure and watchdog kills), hang call stacks, and delivery into our own pipeline joined to our logs. Against that: TestFlight and Organizer already show crashes, hangs and (for App Store builds with enough opted-in users) exit and performance data with no code; MetricKit delivery to TestFlight builds is reported as unreliable (iOS 18 forum reports) and may depend on a device setting. *Decision rule:* after one TestFlight round, keep it only if a real payload showed something the typed events and Apple's own tools did not.
5. **What does "#11" refer to in the Stack Map?** Not found; taken to mean user feedback gathering. Please confirm so the right entry is closed.

## 17. Documentation Strategy

**Documentation Type:** API docs, a README section ("Reporting a problem" and "What the app sends"), a plain-language page for testers and the App Store privacy answers, and a DocC article in `SwiftDiagnosticsKit` on the privacy line, adopting MetricKit and adding an event.

- Also: CHANGELOG, master plan (What's Working, Roadmap), an ADR for each decision in §12, and the §15 checklist.
