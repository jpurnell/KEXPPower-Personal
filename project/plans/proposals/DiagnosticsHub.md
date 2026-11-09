# Design Proposal: SwiftDiagnosticsHub (a general-purpose diagnostics ingest server)

**Status:** PROPOSED 2026-11-09. Owner: "I think we would want to have that ingest server working. I'd love to get something like that on a running app like WineTaster as well, so it would need to be general purpose, and then to surface issues in an actionable way"; "The server would also likely want to use BusinessMath to help identify trends and priorities." Written in the KEXPPower repository for review; **on approval it moves to the new sibling repository `SwiftDiagnosticsHub`** (created from the development-guidelines template as a sibling directory, not nested). The client half is `DiagnosticsAndFeedback.md`.

**Facts marked (repo) were read on 2026-11-09. Anything about hosts, libraries or Apple's behavior that was not checked is marked *unverified*.**

---

## 1. Objective

One server that any of the owner's apps send diagnostics to, that groups what arrives into **issues**, ranks them, and tells the owner about the ones that matter, in close to real time. Adding a second app (WineTaster) is a registration and an event schema, not new server code. It holds nothing that identifies a person.

## 2. Motivation

- Today a bug in a TestFlight build is found by cabling the phone and copying a log (repo: `DiagnosticLog`, `devicectl`). The owner wants issues surfaced without the listener doing anything.
- Apple's TestFlight and MetricKit data is useful but delayed, per-platform and unjoined to what the app was doing.
- The portfolio has a pattern for this kind of service. **SwiftPushHub** (repo, `Tools/SwiftPushHub`) runs under launchd on Teletran-2, accepts authenticated events on a public route, writes them to an SQLite outbox first and answers 202, rate-limits token attempts, keeps an access log, and pushes to the Inbox app on every device. The new server reuses the pattern and sends its alerts through that hub rather than building a second push path.

## 3. Proposed Architecture

```
app ──(SwiftDiagnosticsKit, typed events, background URLSession)──▶ POST /v1/ingest
        │                                                              │ validate against the app's schema, drop the IP,
        │                                                              │ write to SQLite first, answer 202
        ▼                                                              ▼
  per-launch ID, channel                                  group into issues (fingerprint) ──▶ trends, priorities (BusinessMath)
                                                                       │
                              rules ──▶ alert via SwiftPushHub (new issue, regression, spike) · daily digest
                                                                       │
                                       CLI `diag` · MCP tool · (later) a read-only page
```

**Packages (one repository):**
- `SwiftDiagnosticsKit` — the client library an app depends on: the envelope, the event protocol, the scrubber, the disk queue and the uploader. No server code.
- `SwiftDiagnosticsHubKit` — schema registry, validation, storage, fingerprinting, issue state, retention, the rules engine. No listener.
- `SwiftDiagnosticsHubServer` — the listener, configuration, the admin CLI's logic.
- `diag` — the executable: argument parsing only.
- `DiagnosticsMCP` — the MCP tool (so "what is new in Spinner 3.4.0?" is a question, not a login).

**Per-app registration** (`diag app add spinner`): a bundle ID, the platforms, the **event schema** (each kind, the type of each field, and any allowed values), the channels, the alert routing, and a symbol store location for dSYMs. The server rejects an event whose kind or field is not in the schema. **This is the privacy line on the server side**: a field that was not registered cannot be stored, whatever a client sends.

**Envelope (client → server):**
`app`, `platform`, `appVersion`, `build`, `osVersion`, `deviceClass`, `channel` (`development` | `testFlight` | `appStore`), `launchID` (random, new each launch, never saved on the device), `sentAt`, and `events: [ { kind, severity, fields, at } ]`. A `logChunk` kind (text lines, scrubbed) is accepted only for `channel == testFlight` from an app build registered as TestFlight.

**Ingest hardening:**
- A per-app ingest key, embedded in the app. It is not secret (anyone can extract it from the binary); it only identifies the app and lets the server rate-limit and revoke. The real protections are: strict schema validation, size limits (64 KB per request, 100 events), rate limits per key and per address bucket kept in memory, and rejection of anything unregistered. App Attest (DeviceCheck) could stop forged traffic; its fit here, and its cost in complexity, is *unverified* (§16).
- **The IP address is never stored.** The listener uses it for in-memory rate limiting only. The hub's access log records addresses on purpose (honeypot triage); the ingest route is excluded from it, and the repo's tests assert that no stored row or log line holds a peer address.

## 4. Issues, Trends and Priorities

**Fingerprint.** An issue is `app + kind + code + a normalized location`. For a typed event the code and fields (status, endpoint) decide it. For a crash or hang the location is the top frames of the call stack after symbolication (symbolicated with the build's dSYM; until then, the binary UUID and offsets, so the same crash still groups).

**Issue record:** first seen, last seen, event count, **distinct launches affected** (the count of unique `launchID`s, the nearest thing to "how many people", with no identity), the builds and platforms it appears in, per-build counts, sample events, the log chunks around it (TestFlight only), state (`new`, `ongoing`, `resolved`, `regressed`, `muted`) and the build it was fixed in.

**Resolved and regressed.** `diag resolve <issue> --in 3.4.1` marks it fixed in a build. If the issue appears again in that build or a later one it becomes `regressed` and alerts. The release tool's upload step can call this (`diag release spinner 3.4.1 57`) so the server knows which builds exist and which is newest.

**BusinessMath.** Used for the numbers, in `SwiftDiagnosticsHubKit`, only where a statistic is meaningful:
- **Rate and trend per issue:** events per distinct launch over time, moving averages, and a trend direction, from BusinessMath's time-series statistics and moving-average functions.
- **Spike detection:** a sudden rise against an issue's own baseline, using its anomaly detection or a z-score (*to be checked against the library's actual API*).
- **Crash-free launches per build**, the number to compare 3.4.0 with 3.4.1: launches with no crash or hang over all launches, with a confidence interval so a small sample is shown as uncertain.
- **Priority score:** distinct launches affected, severity, the channel weighting (an App Store build outranks a TestFlight one), trend, and recency, combined by a documented formula; the top of `diag issues` is ordered by it, and the formula's inputs are shown with each issue so a ranking can be argued with.
- **A minimum-sample rule.** With a small user base most issues have a handful of events. Below a threshold (to be set, for example fewer than 20 launches in the window) the server says "too few launches to call a trend" and ranks by severity and recency instead; it does not alert on a statistic. A crash is always alertable on its first occurrence; a *rate* is not.
- *Unverified:* that BusinessMath builds as a Swift package on the server host (Teletran-2: x86_64, macOS 15.8, Swift 6.4.1 per the hub's master plan). Here it is available as tools; the package dependency has to be checked at implementation time. If it cannot be used, the same functions are small and can be written and tested in the Kit.

## 5. Actionable Surfacing

- **Alerts through SwiftPushHub**, by rule, not firehose: a new issue in an App Store or TestFlight build, a regression, a crash-free rate falling below a threshold for a build, a spike in an issue with enough launches to count. An alert says: app, version, what, how many launches, first seen, and the command to see it (`diag show <id>`). A daily digest carries the rest.
- **`diag` CLI:** `issues` (ordered by priority, filterable by app, build, channel, state), `show <id>` (the fingerprint, the symbolicated stack, per-build counts, the trend and why it is ranked where it is, the nearest log lines), `resolve`, `mute`, `builds`, `app add|list`, `retention`, `status` (the same observability the hub has: last event time per app, queue depth, rejected counts by reason).
- **MCP tool:** `diagnostics_issues`, `diagnostics_issue`, `diagnostics_builds`, so a question to Claude reads the same data the CLI does.
- **Dashboard:** see §5a. Pulling TestFlight crash and screenshot submissions from App Store Connect into the same issue list (`MultiPlatformRelease.md` §4b) follows.

### 5a. The dashboard: integrate with the IJS dashboard, keep the server separate

Owner question, 2026-11-09: a separate GUI app, or integrate with the IJS system, "since that's like finding code issues in the wild".

**Recommendation: one dashboard, two backends.** The IJS dashboard (repo: `quality-gate-dashboard` is the SwiftUI window, `ijs-dashboard-api` the OpenAPI contract and client with a `DashboardSource` protocol, `ijs-dashboard-server` the read-only server with passkey sign-in, tenants and grants) gains a **Field** section that reads this server. The two servers stay separate processes.

*Why integrate the interface:* the two answer one question from opposite ends, static findings before release and runtime failures after. The owner already signs in to one dashboard with a passkey; a second app means a second install, a second sign-in and a second place to look. The join is the real value: a field crash symbolicated to a file and function can show the gate's findings on that same code (a hang in a function the complexity or concurrency checker had flagged), which neither tool can say alone.

*Why keep the servers apart:* `ijs-dashboard-server` is read-only by design (only `GET` and `HEAD`; anything else is a `405`) and serves a git clone of the corpus on a different host (Teletran 2, per its README). This server takes public, unauthenticated-ish writes, holds high-volume event data under a deletion policy, and runs on Chromedome. Putting an ingest route in the read-only server would give up its simplest security property. It would also couple two data lifecycles that have nothing in common: a corpus recomputed when a git `HEAD` moves, and events that expire after 30 days.

**What is shared, so little is rebuilt:**
- The **contract-first pattern**: this server publishes its own OpenAPI document and a client product (`SwiftDiagnosticsHubClient`) the way `ijs-dashboard-api` does, with golden responses replayed in tests.
- **Sign-in**: the same passkey scheme (`SwiftWebAuthn`) and device keys, so one enrolment works; the read routes sit behind it, and the ingest route does not (it has its own app key).
- **Tenants and grants**: the read API names a tenant and an app, and a grant limits which apps a credential sees, as the corpus server does.
- **UI**: a new `DiagnosticsSource` beside `DirectDashboardSource` and `ServerDashboardSource`, and a Field section (issues by priority, an issue's trend and stack, builds with their crash-free rate). *Unverified:* how the dashboard's data model and navigation would take a second source; I read the packages' READMEs, not their code.

**The join key, and what it needs:** a symbolicated stack gives a function and file; the gate's findings are keyed by project, file and line at a commit. The link needs the **commit each build was made from**, which the release tool knows when it archives (`MultiPlatformRelease.md` gains "record the git commit with each build"); the server stores it with the build, and the dashboard looks the finding up in the corpus at that commit. Until that exists a field issue shows no related findings, and says why.

**Alternative considered: a separate GUI app.** Faster to start and free of the dashboard's structure, but duplicates sign-in and navigation, and loses the join. Kept as the fallback if the dashboard's data model cannot take a second source without a rewrite; decide after reading its code, at step 9b.

## 6. Constraints & Compliance

- **Privacy:** no persistent identifier, no IP stored, a schema-enforced field allowlist, 30-day retention of raw events (owner, 2026-11-09), TestFlight log chunks only from testers who saw the disclosure. After 30 days only **aggregates** remain (counts per issue, per build, per day) with no event rows; whether to keep aggregates longer is §16.
- **No per-person deletion** is possible because nothing identifies a person; the retention window is the deletion policy, and the App Privacy answers say so.
- Swift 6.2+, strict concurrency, `Sendable` types, no force unwraps; quality gate at 0 and 0; DocC on public API.
- Secrets: the APNs and hub credentials stay in the hub; this server holds only a token to send alerts through it.
- **Host: `chromedome.local` / roseclub.org** (owner, 2026-11-09): macOS 15.8.1, x86_64, Swift 6.4.1 (re-verify with `swift --version` over ssh before building; these notes have been stale before). Built on the host, not cross-compiled. That host **does not run the quality gate** (no `quality-gate` binary; corpus and telemetry host only), so the gate runs on the development machine before a release is copied. Runs under launchd on a loopback port with TLS terminated as the hub's is. The hub itself runs on Teletran-2, so alerts reach it over its authenticated public route, not loopback, and a hub outage must not lose an alert: alerts are written to the server's own outbox first and retried.

## 7. Source & API Compatibility

New repository, so nothing exists to break. The wire format is versioned (`/v1`); a change that is not backward compatible is `/v2` with both served during a transition. `SwiftDiagnosticsKit` follows semantic versioning; an app adopting it pins a version.

## 8. Storage

SQLite, as the hub's outbox is (repo): tables for apps and schemas, raw events (with a retention timestamp), issues, per-day aggregates, builds, symbol-store index. A nightly job deletes expired raw events and prints what it removed. Written first, then processed, so a crash mid-processing loses nothing.

## 9. Resource Budget

A small user base means low volume (events per day in the hundreds to low thousands, *an estimate*). Limits: 64 KB per request, 100 events, a request-rate cap per key, a database size alarm in `status`. Symbolication runs on demand and is cached per build. BusinessMath runs on a schedule (every few minutes) over the recent window, not per event.

## 10. Dependencies

`swift-argument-parser`, SQLite (as the hub), `swift-process-kernel` (for `atos` / `llvm-symbolizer`, as `SwiftReleaseKit` does), the hub's alert client, and **BusinessMath** for §4. The listener framework is whatever `SwiftPushHubServer` uses (*to be read at implementation time so the two do not diverge*). No analytics SDK.

## 11. Test Strategy

Red first, Swift Testing, as the hub does.
- **Schema enforcement:** an unregistered kind is rejected; an unregistered field is rejected; a field of the wrong type is rejected; a `logChunk` from a non-TestFlight channel is rejected; an oversize request is rejected; none of these writes a row.
- **No IP stored:** a request through the router with a peer address leaves no row or log line containing it (the test asserts this on the database file and the log output).
- **Fingerprinting:** the same typed event groups together; different codes do not; two crashes with the same top frames group; a crash with different frames does not.
- **Issue state:** new → ongoing; `resolve --in` then a later-build recurrence becomes `regressed` and alerts once; mute silences alerts, not storage.
- **Retention:** raw events past 30 days are deleted and aggregates kept; a test with an injected clock.
- **Priorities and trends:** against fixed time series with known answers (a flat series, a ramp, a spike); the minimum-sample rule (a spike in 5 launches produces "too few", a spike in 500 produces an alert); crash-free rate with its interval.
- **Alert rules:** each rule fires once, not every minute; the digest contains what is left; a fake alert sink records the messages.
- **Symbolication:** a fixture dSYM and a fixture stack produce the expected function names (or the test is marked as needing the tool, run by hand).
- **Not testable offline, checked by hand and recorded:** the public route and TLS, a real app sending, push to the Inbox app, BusinessMath on the host.

## 12. Architecture Decision Review

- **ADR:** a separate repository, not a module in SwiftPushHub. Reason: different data (high volume, with retention and deletion rules) and a different security posture (an unauthenticated-ish public ingest route); the hub stays a push service. The new server is a *client* of the hub for alerts.
- **ADR:** the schema registry is the server's privacy enforcement; client types are the first line, the server the second.
- **ADR:** no IP stored; the ingest route is excluded from the hub-style access log.
- **Layering:** Kit has no listener; Server has no logic that is not in the Kit; the CLI is argument parsing only, as in both existing tools.

## 13. Adversarial Review

- **"The ingest key is in the binary; anyone can post junk."** Yes. Schema validation limits what junk can be stored, rate limits cap volume, a key can be revoked, and junk is visible in `status` as rejected counts. A flood within the limits can still pollute issues; App Attest (§16) is the next control.
- **"A forged event triggers a push alert at 3 a.m."** Alert rules need more than one event or a minimum number of distinct launch IDs for a non-crash, and a global alert rate limit; a crash alerts on first sight, so a forged crash could alert once per fingerprint. Accepted, with the per-fingerprint dedupe.
- **"The statistics lie with few users."** The minimum-sample rule and the confidence interval.
- **"dSYMs are missing, so crashes are addresses."** The release tool must retain and upload them (`DiagnosticsAndFeedback.md` §4a item 5); `status` shows builds with no symbols.
- **"Distinct launches are not people."** True; one person is many launches. It is a measure of reach, labelled as launches, never as users.
- **"The public route exposes the host."** The ingest listener binds to loopback and is reached through the hub's existing route; the hub's `HostAllowList` and rate limiting apply (*to be confirmed that the route can carry a second backend*).
- **"Combining app, version, device class and time identifies someone in a very small beta."** Retention is 30 days and the data carries no identifier; with a handful of testers a person is identifiable by anyone who knows them regardless. The disclosure screen is honest about this; the tester list is the owner's own.
- **"A schema change breaks old app versions."** Fields are only ever added; a removed field is ignored, not rejected, for the versions registered as live.

## 14. Alternatives Considered

1. **Put it in SwiftPushHub.** Rejected (§12).
2. **A hosted service (Sentry, Firebase Crashlytics, Datadog).** Rejected: an SDK and a label we do not control, data on someone else's servers, and no integration with the owner's tools. Would be faster to start; the owner chose to own it.
3. **Only Apple's data (TestFlight, Organizer, MetricKit).** Kept as an input, not sufficient: no pre-crash context, no non-crash failures, no cross-app view.
4. **Per-app servers.** Rejected: the owner wants WineTaster to reuse it.
5. **No server; manual send.** Rejected by the owner's goal.

## 15. Future Directions

Order of work (each ends with a real run recorded in the master plan):
1. The repository from the development-guidelines template; `SwiftDiagnosticsKit` envelope and schema types; schema registry and validation, with the privacy tests.
2. Storage, ingest route, the 202-after-write path, rate limits, retention.
3. Fingerprinting and issue state; the `diag` CLI.
4. Alerts through the hub; the daily digest.
5. BusinessMath: trends, spike detection, crash-free rate, priority score, minimum-sample rule.
6. Symbolication and the symbol store; the release tool's dSYM upload and `diag release`.
7. The MCP tool.
8. Register Spinner; one real TestFlight event end to end. Then WineTaster (*its platforms and distribution are unverified; the only thing found at its path was a 257-byte file*).
9. **Gaps to clear quickly (owner's instruction), in this order:** (a) App Attest on the ingest route, after the first TestFlight round and before an App Store build sends events; (b) the dashboard section (§5a); (c) App Store Connect feedback in the same issue list; (d) the build-to-commit link that joins a field issue to the gate's findings on the same code.

## 16. Open Questions

1. ~~**Which host?**~~ **Decided 2026-11-09: `chromedome.local` / roseclub.org.** Consequences: alerts to the hub cross machines (retry from an outbox, §6); the gate is not available there; confirm the hub's route accepts a second sender before wiring alerts.
2. **App Attest.** **Deferred, not dropped** (owner, 2026-11-09: "we can skip at first, but we'll want to get these gaps cleared quickly"). It is scheduled as step 9a in §15, to land after the first TestFlight round and before any App Store build sends events, and it is tracked as a named gap in the master plan so it cannot drift.
3. **Aggregates beyond 30 days.** Keep per-issue, per-build, per-day counts indefinitely so trends across releases survive? *Recommendation:* yes; they hold no events.
4. **Do alerts go to every device or only some channels of the Inbox?** *Recommendation:* a `diagnostics` channel, so notification preferences are per device, as the hub supports.
5. **WineTaster.** What does it need first, and is it on TestFlight or the App Store?

## 17. Documentation Strategy

**Documentation Type:** Narrative Article Required.

- Combines 3+ APIs (schema, ingest, issues, BusinessMath, alerts): Yes. Explanation over 50 lines: Yes. Needs background (the privacy line, why distinct launches): Yes.
- **Articles:** `AddingAnApp.md` (register an app and an event schema), `ThePrivacyLine.md`, in the `.docc` catalog (names that match no symbol).
- Also: README, a man page and an operator's runbook modelled on the hub's, CHANGELOG, master plan, an ADR per decision in §12, and the plain-language privacy page the apps link to.
