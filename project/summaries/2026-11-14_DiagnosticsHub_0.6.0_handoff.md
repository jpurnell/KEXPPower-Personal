# Session Summary: Diagnostics Hub 0.6.0 (analysis and alerts), opt-in consent, handoff

| Date | Phase | Status |
| :--- | :--- | :--- |
| 2026-11-14 | DiagnosticsHub completion plan, slices 2 to 4 (`SwiftDiagnosticsHub/project/plans/proposals/DiagnosticsHubCompletion.md`) | COMPLETED (slices 5 and 6 not started; see section 6) |

This session ran across several repositories. **Spinner** is this repo (`KEXPPower`, public, branch `swiftui_example`). The rest are Swift packages under `/Users/jpurnell/Dropbox/Computer/Development/Swift/Tools/`: `SwiftDiagnosticsClient`, `SwiftDiagnosticsHub`, `SwiftDiagnosticsReadAPI`, `SwiftPushHub`, `quality-gate-dashboard`. The hub's own plan, changelog and runbook live in its repo; this file is the single handoff for all of it.

## 1. Core Objective

Finish the DiagnosticsHub pipeline (detection, ingest, processing, analysis, presentation) up to a release that can sit behind a TestFlight build: consent off by default everywhere, MetricKit wired, statistics from BusinessMath, and alerts that reach the owner's phone, with decoys. Then deploy it for real and prove it with a drill.

## 2. Design Decisions

- **Decision:** Diagnostics are **opt-in in every build**, with no network call to the owner's servers before the person agrees. **Rationale:** the owner's instruction; "no identifying information is sent" is stated in the question itself. The consent model, its wording and its views live in `SwiftDiagnosticsClient` (`DiagnosticsConsent`, `SwiftDiagnosticsConsentUI`, 0.3.0 and 0.3.1), not in each app, so every app asks the same way. **Alternatives:** an app-local switch (rejected: the old default was on).
- **Decision:** **Every statistic comes from BusinessMath and nowhere else** (Wilson interval, Poisson tail, median absolute deviation, two-proportion test). **Rationale:** the owner does not want two versions of anything. BusinessMath got three additions first (alpha.15); the hub pins `3.0.0-alpha.16` exactly.
- **Decision:** the **spike rule** is a Poisson tail on the median of recent days, tightened for overdispersion (56-day dispersion window plus a square-root tightening of the probability). **Rationale:** a replay by the BusinessMath session found the plain rule 4.6 to 13.5 % false alarms a day on noisy-but-flat data; the as-built rule is under 2 % and catches 79 of 100 steps within a week. Slow ramps are caught by no detector tried.
- **Decision:** the crash-free rate is **a proxy** ("runs that ended while the app was in use"), never "crashes" and never "crash-free users". The **true rate is shown** (owner decision 2026-11-13: no rounding of small crash-like counts), which makes a small crash-like count derivable from it when a build has 5 or more launches.
- **Decision:** alerts go through the owner's **own push hub** (`SwiftPushHub` 1.1.1, pinned by revision) on a dedicated `diagnostics` channel, so there is one implementation of delivery. The hub needs macOS 15 and names the identity package `swift-identity` (same repository as `SwiftIdentity`; SwiftPM treats the two spellings as two packages and refuses both).
- **Decision:** the hub runs as a **LaunchDaemon under the owner's user** (not root, not a login agent), from a **notarized app bundle run by its own path**. **Rationale:** see section 6, "Context Loss Warning": macOS 15 refuses an unsigned, ad-hoc or link-run daemon a LAN connection in silence.
- **Decision:** `mutedBuilds` per app: builds that never alert (a debug build's launches look like crashes to the proxy) and still appear in `diag health`. A muting clears an alert raised before it. **Alternative rejected:** a build-number floor (Spinner's first TestFlight build is also numbered `1`).

## 3. Work Completed

### Design Proposal
- [x] Proposals written and approved before code: `RicherSignals.md`, `Analysis.md`, `AlertsAndDecoys.md` (hub repo, `project/plans/proposals/`). The owner reviewed all three; the build followed them, with as-built departures recorded in each (section 12).
- [x] Constraints compliance: no suppressions, strict TDD, path-scoped commits through hooks (never `--no-verify`).

### Tests Written (RED phase)
- [x] Golden path: rate against R reference values (0/10, 1/10, 10/10, 0/5, 3/1000); build comparison against the library's own p-value; priority score each term at 0, at 1 and mid; alert rules each on its trigger and one step short; dispatcher cooldown, restart, all-clear, retry; file ledger across a reopen; decoy hits read from the audit; the alerting pass end to end over an in-memory store.
- [x] Edge cases: fewer than 5 launches gives no rate or score; history under 7 days gives no spike verdict; days under the minimum read as zero (a suppressed 1 and a suppressed 4 give the same verdict); impossible counts refuse; a muted build clears an open alert.
- [x] Invalid input: every `alerts` configuration field out of range names the field; unknown members refused; an unusable credentials file turns alerting off with a fixed reason and never stops the hub.
- [x] Deterministic seeds: the spike replays use a fixed LCG seed (seeds 1 to 100, plus offsets 1,000 and 9,000).
- [x] **Mutation-checked** at each step by editing the source and watching the tests fail; mutants that survived were killed with new tests (for example: build comparison's small-cell checks, the spike floor of five, platform separation in the health comparison, the spike history boundary, the launch-kind filter, the retry-backoff timestamp, and a muted build clearing an old alert).

### Implementation (GREEN phase)
- **Created (hub):** `Analysis/{Analysis,Spike,BuildComparison,PriorityScore,AnalysisService}.swift`; `Alerting/` additions; `FileAlertLedger`, `AlertingPass`, `AlertingSetup`, `AlertingReport`, `PushHubAlertSender`; `scripts/package-hub.sh`, `Packaging/DiagnosticsHub-Info.plist`; `project/runbooks/AlertsDeploy.md`; the DocC article `ReadingTheNumbers`.
- **Created (ReadAPI 0.2.0):** `ReadHealth`, `ReadHealthCell`, `ReadRate`, `ReadBuildComparison`; `ReadIssue.priority` and `spiking`; `ReadClient.health`.
- **Created (Client 0.3.0 and 0.3.1):** `DiagnosticsConsent`, `EventCoalescer`, `RunMarker`, `IngestKey`, `SwiftDiagnosticsMetricKit` (mapping and subscriber), `SwiftDiagnosticsConsentUI` (an ordinary iOS form sheet; `asksAboutDiagnostics(model:appName:)`).
- **Modified (hub):** `Issue.severity` (SQLite migration 4); `ReadSurface.health`; the read route `GET /v1/read/apps/{app}/health`; `diag health`; `diagnostics-hub-admin status`; `BackgroundWork` (an `onTick` hook); `HubServerConfiguration` (`alerts`).
- **Modified (Spinner):** `FieldConsent`, the app file (package modal, two sites), `SettingsView`, `PrivacyInfo.xcprivacy`, `spinner-schema.json` v4 (five MetricKit kinds), `Config/Secrets.xcconfig.example` (the decoy ingest key).
- **Modified (quality-gate-dashboard, local only):** Field screens for Mac and iOS with sort, filter and a "Select" mode, plus the Local Network plist keys.

### Documentation
- [x] DocC on every public API; `ReadingTheNumbers.md`.
- [x] CHANGELOG, README and master plan reconciled in the hub (0.6.0), ReadAPI (0.2.0), Client (0.3.0, 0.3.1) and Spinner (Unreleased). Roadmap items marked done with their reasons.
- [x] Runbook `AlertsDeploy.md` is the verified procedure, including what each failed attempt showed.
- Playground-ready: No (these are services and libraries).

## 4. Mandatory Quality Gate (Zero Tolerance)

Every push of this session ran the full `quality-gate --strict` through the repository hook. Results at the last push of each repo:

| Check | Status |
| :--- | :--- |
| **hub 0.6.0 (`5b44025`)** | ✅ 51 of 51 checkers, 0 errors, 0 warnings, 0 suppressed (notes only: cognitive complexity of four functions) |
| **ReadAPI 0.2.0 (`6bc9059`)** | ✅ passed |
| **Client 0.3.1 (`8959a23`)** | ✅ passed |
| **Spinner (`2f93474`, `ffeebef`)** | ✅ passed (534 tests, iOS simulator) |
| **tests (hub)** | ✅ 180 + 165 + 15 (Swift Testing; the three suites of the package) |

I did **not** re-run `quality-gate` at the end of this summary: nothing in any repo has changed since the last passing push except this file and the capability map. If a fresh run is wanted, `quality-gate --strict --continue-on-failure` in each repo.

### If Any Check Failed (earlier in the session, all resolved)
- **test-quality, fallback, safety, concurrency, doc-lint, fp-safety** findings in newly written code were fixed at the root with no suppressions (for example: `String(format:)` replaced by a small formatter, an `@unchecked Sendable` test helper given its justification, cross-module double-backtick doc links made single).
- **release-readiness** blocked the first tag push for a missing CHANGELOG entry for 0.6.0: fixed by reconciling the CHANGELOG before tagging.
- **xcode-build** failed on one commit because **another session** had checked out a branch and staged dependency changes in the shared working directory; resolved by committing and pushing from a separate worktree, which has since been removed.

## 5. Project State Updates

- [x] Active checklist: none exists in `project/checklists/` (only `blocked/` and `completed/`, both empty).
- [x] `project/master_plan.md`: updated for diagnostics opt-in, MetricKit and the 3.6.0 state earlier this session (commit `ffe4b4d`); the package modal and its pin on 2026-11-13 (`2f93474`). Not changed again today.
- [x] `project/capability_map.md`: was the unfilled template. **Filled in for the one area this session shipped (Diagnostics)**; the other areas of the app are not yet mapped and the file says so.
- Hub, ReadAPI and Client repos' own plans were reconciled in their release commits.

## 6. Next Session Handover (Context Recovery)

### Immediate Starting Point

> The diagnostics work is finished and deployed. Nothing is half-done. The next piece of work, if any, is **slice 5** (hardening) or the **dashboard's Field page showing the new health numbers**; both need a design proposal first. Start with `SwiftDiagnosticsHub/project/master_plan.md` ("What's Next") and the umbrella plan `project/plans/proposals/DiagnosticsHubCompletion.md`.

What is live, so you do not have to rediscover it:
- **Hub 0.6.0** on Chromedome (`chromedome.local`, x86_64, macOS 15.8.2): ingest `https://diagnostics.roseclub.org:9110`, read listener `192.168.1.3:9111`. Runs as the LaunchDaemon `com.roseclub.diagnostics-hub` (as `jpurnell`), executing `~/bin/DiagnosticsHub.app/Contents/MacOS/diagnostics-hub-server`; it started by itself after a reboot with nobody logged in.
- **Alerts** go to the owner's phone via the push hub on Teletran-2 (`https://push.keepitfun.biz:9095`, channel `diagnostics`, sender `diagnostics-hub`); credentials at `~/.diagnostics-hub/push-credentials.json` on Chromedome (mode 600). `diagnostics-hub-admin status ~/.diagnostics-hub/hub.json` says whether alerting is on.
- **Decoy** `spinner-ingest-key` is planted and its key is in Spinner's `Config/Secrets.xcconfig.example` (pushed). Using it from any machine gives the ordinary 400, an audit line with the caller's address, and a phone alert. (An earlier decoy, `spinner-example-key`, was revoked; its key was lost.)
- **Deploy procedure** (verified twice): `ssh chromedome.local`, `cd ~/SwiftDiagnosticsHub && git fetch && git checkout <commit> && swift build -c release`; then on the dev Mac `scripts/package-hub.sh`. It signs (Developer ID, hardened runtime), notarizes (`hub-notary` profile), staples, installs and stops the old process so launchd restarts it. Back up `~/.diagnostics-hub/data/hub.sqlite` with `sqlite3 ... ".backup ..."` first if a migration is involved. Never `cp` a WAL-mode database.

### Pending Tasks

- [ ] **Dashboard Field page** (`quality-gate-dashboard`): show the crash-free rate with its interval, the build comparison and an issue's priority and spike flag (the read API already returns them). It needs ReadAPI 0.2.0 in its dependency floor and a design proposal.
- [ ] **Push the dashboard's five local commits** (`5f5ed0c`, `aa77256`, `e6eaf00`, `668c518`, `d4ceae8`): the owner has not asked.
- [ ] **Slice 5, hardening**: App Attest, HTTP-01 certificate issuance before the **Dec 16 / Jan 9 / Jan 26** renewals, symbolication. Needs its own proposal.
- [ ] **Slice 6, proof**: a captured MetricKit payload replaces the constructed fixtures (`SwiftDiagnosticsMetricKit` tests are built from the documented shape, not from a real payload). A device that has opted in delivers one within about a day.
- [ ] **WineTaster (slice 7)** waits for an explicit owner go.
- [ ] **Hub liveness**: a stopped background loop cannot report itself, and nothing outside the hub watches it.
- [ ] **Tune** the spike constants and the priority weights against a week of real counts (named constants; the numbers are documented, not final).
- [ ] **App Store privacy label** (the owner's step) and a decision whether to add an address sentence to the disclosure: the hub keeps no address except a decoy's, but the question's wording makes no claim about network addresses.
- [ ] **The first-launch sheet on real devices**: Springer and Brawn both have the build with the package's ordinary sheet (installed 2026-11-13). I only saw the layout in an iPad simulator render; the owner should confirm it looks right on the devices, and opt in on one so the first real event from this build reaches the hub (check with `diag`).

### Blockers

- **Blocker:** none for finished work.
- **Dependency:** the dashboard work needs the owner's go; slice 5 and 6 need their own design proposals and the owner's choices.

### Context Loss Warning

- **macOS 15 Local Network privacy is the trap.** A bare x86_64 daemon is refused every LAN connection with `-1009` ("not connected to the internet") and **no prompt**. What was tried: unsigned (never asked), ad-hoc signed (asked once, refused after the next build), Developer ID signed bundle run through a link (refused), and finally **a Developer ID signed, hardened-runtime, notarized and stapled app bundle run by its own path with no link or alias anywhere**, which delivered on a fresh process and after a rebuild. **A leftover link into the bundle broke delivery even though nothing ran through it.** Whether notarization is required once there is no link was **not isolated**. Never leave a link, alias or second copy of the program at another path. Apple-signed tools (`curl`, `python3`) are exempt, which is why they reached the push hub when the hub could not.
- **The `hub-notary` notarytool profile vanished once** (probably my stalled command, not proven). Recreate with `xcrun notarytool store-credentials hub-notary --team-id BNDA9Y6YV9` (the owner types the app-specific password; never ask for it). The script says whether the profile is missing or Apple is unreachable.
- **The shared hub working directory.** `SwiftDiagnosticsHub` is used by **another session** (branch `feat/tlskit-1.0-beta`, then a detached HEAD at `2496def`). Do not switch branches there. Use a separate `git worktree` for anything you commit, and remove it when done. The pre-push hook gates the working tree, so someone else's staged changes can fail your push.
- **`origin/main` carries the other session's dependency bump** (`6c2713d`: SwiftHTTPService and SwiftTLSKit to 1.0 betas). The deployed binary was built from `c91b2c1`, which includes it; the tag `0.6.0` is `5b44025`, docs and scripts only on top.
- **Gate warning, not an error:** `quality-gate` runs `release-readiness` only on a tag push: a version in the CHANGELOG without a matching entry blocks it. Reconcile the CHANGELOG, README and plan before tagging.
- **Spinner owner edits that must stay uncommitted:** `KEXPPower.xcodeproj/project.pbxproj` (display name "Spinner Radio", `MARKETING_VERSION` 3.6.0), the visionOS icon files, `image_logo_1024.png`, and the Spinner TV scheme files. I committed only path-scoped files and kept those out.
- **The crash-free rate is a proxy.** It counts a launch after a run that ended while the app was in use, which includes a force-quit, a jetsam kill and Xcode's stop button. Debug builds therefore look unstable: Spinner's build `1` is muted for exactly that reason (`"mutedBuilds": ["1"]` in `hub.json`). **Remove that entry when a release ships under build number 1.**
- **Secrets stay out of the public repo and out of chat.** The push-hub credentials, the Spinner ingest key and the reader key live in owner-only files on the hosts. The decoy key in `Secrets.xcconfig.example` is bait by design. Never print a key or put one in a prompt to a peer session.
- **Standing rules that applied the whole session:** design proposal first; strict red/green TDD with mutation checks; gate 0/0 with no suppressions before committing; pushes, tags and deploys only with the owner's approval; no `rm -rf`, ask before deleting; no fan-out agents; scratchpad, not `/tmp`; peer and system notifications are not approval. Mistakes made and fixed this session (so they are not repeated): a wrong line number lost a decoy key (capture a key by pattern and length, never by line number, and delete the capture only after the key is in place); an unquoted heredoc around text full of backticks executed my own words as commands (write such text to a file with a tool); a script edit that silently did not apply (check that a replacement happened before running the script).

---

## Metrics

"Before" counts were not recorded at the start of the slice work, so only the end state is given; do not read a delta into this table.

| Metric | Before | After |
|--------|--------|-------|
| Hub tests (three suites of the package) | not recorded | 180 + 165 + 15 |
| ReadAPI tests | not recorded | 17 |
| Client tests (at 0.3.1) | not recorded | 174 (136 + 23 + 15) |
| Spinner tests (iOS simulator) | not recorded | 534 |
| Hub release build on Chromedome | not measured before BusinessMath | measured 1:46 to 5:52 (cold with BusinessMath 5:52; incremental 1:46 to 3:13) |
| Hub server binary | 24 MB | 49 MB (BusinessMath and the push stack linked in) |

---

**Session Duration:** several sessions' worth across 2026-11-12 to 2026-11-14
**AI Model Used:** Claude Sonnet 5.5
