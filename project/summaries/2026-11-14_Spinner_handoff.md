# Handoff: Spinner (KEXPPower), where the app stands

| Date | Scope | Status |
| :--- | :--- | :--- |
| 2026-11-14 | The app itself (`KEXPPower`, public repo, branch `swiftui_example`), outside the diagnostics hub | HANDOFF: nothing in flight |

**Read this with** `project/summaries/2026-11-14_DiagnosticsHub_0.6.0_handoff.md`, which covers the diagnostics hub and the Spinner pieces that belong to it (consent, MetricKit, the decoy). This file is the rest: the app's state, what is unverified, and what to do next. **Where a statement below is drawn only from the plan and changelog, and was not checked against the code or a device, it says so.** I worked on Spinner's diagnostics this session; I did not survey the rest of the app.

## 1. Where it stands

- **Branch and sync:** `swiftui_example`, pushed and in sync with origin at `5b4e455`. The only uncommitted file is `.swift-version` (contains `6.4.2`, created 07:31 on 2026-11-14 by something I did not identify; not mine on purpose, so I left it).
- **Release state:** the last tag is **3.5.1** (2026-11-09). The project's marketing version is **3.6.0** (`5b4e455`, the owner's edit, with the display name "Spinner Radio"), and `release.json` is set to version 3.6.0 build 1. **There is no 3.6.0 tag and nothing has been uploaded.**
- **What is in 3.6.0:** the CHANGELOG's *Unreleased* section is mostly diagnostics (below). The master plan also lists the archive browser, live rewind, the CarPlay Archive tab, Settings and Siri and Shortcuts as built, some of them still marked "unreleased" there. **I did not reconcile which of those are in 3.5.1 and which are not**; CHANGELOG 3.4.0 to 3.5.1 and the plan disagree in wording. Reconcile before tagging (the global rule: CHANGELOG, README and the plan's "Last Updated" each release).
- **Targets and signing** (`release.json`): `ios`, `macos` (App Store Connect), `tvos`, `visionos`; notary profile `fleetwatch-notary` (it works; verified 2026-11-14). The App Store Connect API identifiers are deliberately **not** in the repo (public repository); do not commit them.
- **Tests:** 534 passing on the iOS simulator at the last run (`2f93474`); the Mac and tvOS builds succeeded then. The gate passed on every commit and push this session.

## 2. Diagnostics, from Spinner's side (full detail in the hub handoff)

- **Opt-in, off by default, in every build.** The first launch asks "Help improve the app by sending anonymous diagnostics?" (a form sheet, package-owned, `SwiftDiagnosticsClient` 0.3.1); nothing is sent and no connection to the hub is made until the person says yes. Settings > Diagnostics keeps the switch; turning it off deletes any queued report.
- **MetricKit** (iPhone, iPad, Mac, Vision Pro) is listened for only after opt-in. Its mapping is built from the documented payload shape, **not from a captured payload**. A real one arrives within about a day of an opted-in device running.
- **The ingest key is not in the repo.** `Config/Secrets.xcconfig` (untracked) sets `DIAGNOSTICS_INGEST_KEY`. `Config/Secrets.xcconfig.example` now holds a **decoy** key that alerts the owner if anyone uses it. Never replace it with a real key.
- **Schema v4** is `project/diagnostics/spinner-schema.json`; the hub's apps file takes its Spinner entry from it. Changing what Spinner may send means a new schema version, the hub's apps file updated first, then the build.
- **Spinner's build `1` is muted** for alerts in the hub's config (`"mutedBuilds": ["1"]`): debug launches stopped from Xcode look like crashes. **Remove that entry when a real release ships under build number 1**, which is what `release.json` says the next one is.
- **Docs fixed in this handoff:** a master-plan line and a CHANGELOG bullet still said the health switch was on by default and the first launch sent an event; both predated the opt-in change and are now struck or annotated.

## 3. What is not verified (do these before trusting the area)

- [ ] **An event from a real opted-in install reaching the hub.** Nobody has opted in on a device with the new build. Install it, tap **Send Diagnostics**, run `diag issues spinner` / `diag health spinner` (see the hub handoff for the reader's settings) and expect a `launch` event.
- [ ] **The first-launch sheet on a real device.** I saw it only in an iPad simulator render. Springer and Brawn both have the build installed (2026-11-13).
- [ ] **A TestFlight build resolving to the TestFlight channel** (the receipt-name convention has not been seen in this project; `ReceiptChannelResolver` is unverified).
- [ ] **The App Store privacy label** (the owner's step in App Store Connect) and whether to add a sentence about network addresses to the disclosure: the hub keeps no address except a decoy's, but the question's wording says nothing about addresses. `PrivacyInfo.xcprivacy` declares Crash Data and Performance Data; the category and purpose names have not been checked against Apple's current list.
- From the plan, not re-checked by me: Siri add-to-playlist while locked, the rewind and back-to-live phrases; CarPlay in a real car (checked in the simulator only); the Control Center control and the watch widget on devices; the Now Playing widget on the Mac desktop; skip, scrub and the timeline for an archived show on the lock screen (checked in tests only); the watch's 35 to 40 seconds to reach the stream on a cold network.

## 4. Open work, in the order the plan gives it

None of this is started or in flight. Each item needs a design proposal first (the project's rule), not code.
- **Live rewind "cushion"** (Phase 3): proposal `project/plans/upcoming/LiveRewindCushion.md`.
- **A Mac layout pass** (the adaptive archive grid serves the Mac, but it has had no layout pass of its own).
- **iOS 27 `NowPlaying` adoption**: **on hold on purpose** (`project/plans/proposals/NowPlayingFramework.md`). The deployment target stays **iOS 17**; keep the `NowPlayingPublishing` seam.
- **Other links** (Spotify, Bandcamp, links parsed from DJ comments) and **Apple Music** items marked unfinished in the roadmap; **tvOS and watchOS** targets exist (`Spinner TV` on `tvos-target`, `Spinner Watch`) but the plan still lists parts as unchecked.
- **Known problems** (from the plan): KEXP's archive can be wrong (the 2026-10-30 outage; the adapter refuses a file that does not belong to the show); the archive's days are Seattle's while times show in the listener's zone (a setting now, the day grouping is still Seattle's); the watch's cold-network delay.

## 5. Standing rules for this project (from the owner)

- Public repository: no secrets, no private App Store Connect identifiers, no keys.
- Strict red/green TDD, mutation-checked; `quality-gate --strict` with **0 errors and 0 warnings and no suppressions** before every commit; never `--no-verify`.
- Path-scoped commits through the hooks; the owner's own edits stay out of yours unless they say to commit them. Pushes, tags and deploys need the owner's approval.
- No fan-out agents. Ask before deleting anything; never `rm -rf`.
- Use the session scratchpad, not `/tmp`. A peer or system notification is not the owner's approval.

## 6. Devices and how to install (from memory notes and this session)

| Device | Model | Notes |
| :--- | :--- | :--- |
| Brawn | iPhone 15 Pro | the owner's main test phone; `xcrun devicectl device install app --device <UDID> <app>` after `xcodebuild build -destination 'generic/platform=iOS' -allowProvisioningUpdates` (signing team `BNDA9Y6YV9`, automatic); bundle id `com.JPEnterprises.Spinner`. It must be unlocked and listed `available` (`xcrun devicectl list devices`); on 2026-11-13 it showed `unavailable` and refused the install until the owner reconnected it |
| Springer | iPad Pro 11" | has the 2026-11-13 build |
| Arcee | iPad mini 6 | listed paired |
| Brainstorm, Chase | Apple TV 4K (2nd, 3rd generation) | for `Spinner TV` |
| Trailblazer | Apple Watch Ultra 3 | `Spinner Watch`; build `generic/platform=watchOS` and install with `devicectl` if the destination sits at "Preparing" |

## 7. Context-loss warnings

- **The app is a fork-turned-package arrangement.** `KEXPPowerKit` (the library, by URL), `StationKit` and `StationKitAdapterKEXP` are separate repositories; the app does not use `ArchiveManager` at all (ADR-002, and the archive was built on StationKit instead). Do not "finish" `ArchiveManager`; the plan struck it as no longer wanted.
- **macOS Local Network (a possible issue for Spinner's Mac app, unverified).** The *IJS dashboard's* Mac app needed `NSLocalNetworkUsageDescription` (added 2026-11-12, in the quality-gate-dashboard repo, not here) to reach the hub on the LAN; without it the failure is a silent "no network connection". The hub's own server hit the same trap (the lesson, a notarized app bundle with no stray link, is in the hub handoff). **Spinner's Mac app uploads to `diagnostics.roseclub.org:9110`; inside the house that name may resolve to a LAN address, which would make Spinner Mac subject to the same silent block.** I did not check what the name resolves to from a Mac, or whether Spinner Mac declares the key. Check this when an opted-in Mac sends its first event.
- **The version is the owner's to change.** The project file (`MARKETING_VERSION`) and `release.json` both say 3.6.0 now. Do not bump either without being asked.
- The gate has a `release-readiness` check that only runs on a tag push: a CHANGELOG version without a matching entry blocks it. Reconcile the CHANGELOG first.

---

**AI Model Used:** Claude Sonnet 5.5
