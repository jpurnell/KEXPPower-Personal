# Design Proposal: Archive browser (by Date, Host or Show) on iPhone, iPad, Mac, Vision Pro and CarPlay

**Status:** PROPOSED 2026-11-05 (from the owner's CarPlay feedback: an Archive page that resembles the KEXP website, selectable by Date / Host / Show; screenshots of kexp.org/archive supplied)
**Date:** 2026-11-05
**Master Plan Reference:** the "Archive" sidebar section (currently a placeholder), "Finish async `ArchiveManager`", and `CarPlayAudio.md` (the Archive tab).
**Facts marked (live) were checked against `api.kexp.org` on 2026-11-05; (SDK) against the Xcode 27.2 SDK; (repo) in this repository or `KEXPPowerKit`. Anything not confirmed is marked *unverified*.**

---

### 1. Objective
Browse and play KEXP's archived shows the way kexp.org/archive does, in the app's Archive section and in CarPlay, with three ways in, as on the website:

| Mode | The website (from the owner's screenshots) | Here |
|---|---|---|
| **Date** | "Select a date": a grid of day tiles (month, day number, weekday), the current day highlighted, 15 days shown, newest first | the same tiles; a day opens that day's shows |
| **Host** | "Select a host": cards with photo, name, their program(s) in the accent colour, and a show count (e.g. "Cheryl Waters — THE MIDDAY SHOW — 9 SHOWS") | an alphabetical list/grid of hosts with photo, program names and count; a host opens their shows |
| **Show** | "Select a show": cards with the program's picture, name, its hosts, genre tags and a count (e.g. "The Midday Show — CHERYL WATERS — Rock, Eclectic, Variety Mix — 9 SHOWS") | the same, one card per program; a program opens its archived shows |

Choosing a show plays it.

### 2. Motivation
**Current situation:**
- The sidebar has an Archive section that says "coming soon" (repo: `AppSection`).
- `KEXPPowerKit` has an `ArchiveManager` and `ArchiveShow` models, but the master plan records that its async conversion is commented out (`//TODO: - ASYNC`), so archive loading does not work in the app's fork today (repo).
- KEXP's API serves everything the three modes need (live): `/v2/hosts` (106 hosts: `id`, `name`, `image_uri`, `thumbnail_uri`, `is_active`, `location`), `/v2/programs` (41 programs: `id`, `name`, `description`, `tags`, `image_uri`, `is_active`), and `/v2/shows` (68,087 shows in all: `id`, `program`, `hosts`, `host_names`, `program_name`, `program_tags`, `tagline`, `image_uri`, `start_time`). **Filters, checked live 2026-11-06** (a filter that is honoured changes `count`; I also sent impossible ids to catch silent ignoring):
- `/v2/shows/?start_time_after=<ISO>&start_time_before=<ISO>` **works** (one day returned 8 shows; `start_time_after` alone returned 15 for two days). This is "shows on a date".
- `/v2/plays/?show_ids=<id>` **works** (the plays of one show). `show` and `show_id` are ignored. Plays carry no `count`; page with `next`.
- `/v2/shows/` **has no host or program filter that I could find**: `host`, `hosts`, `host_id`, `host_ids`, `hosts_ids`, `hosts__id`, `host_name(s)`, `program`, `program_id`, `program_ids`, `program__id`, `program_name`, `program_tags`, `search`, `id`, `ids` all returned the unfiltered 68,095. `/v2/timeslots/?program=<id>` does filter (59 timeslots, 1 for program 5), so the schedule can say which program airs when.
- **Consequence for the design:** archived audio reaches back about two weeks (3b), so Host and Show modes can fetch the recent window by date and group it on the device (about 15 days, on the order of a hundred shows). The `count` on each host/program card is then "shows in the archive", derived locally, which is also what a listener can actually play. Older shows stay a later option (a full walk of 68k shows is not reasonable).
*Still unverified:* that the 15-day window is the audio window on every day (it moves daily).
- Archived audio is available (live): `GET /get_streaming_url/?bitrate=128&timestamp=<ISO>&stream_time=<ISO>` returned `{"sg-url": "https://kexp-archive.streamguys1.com/content/kexp/20261104095007-5-1935-the-midday-show.mp3", "sg-url-next": "...", "sg-offset": 593}`: a file URL for the show that was on at that time, the next show's file, and an offset in seconds into the file. `/get_show_start/` answered HTTP 500 for the call I tried, so I will not depend on it. The master plan already flagged both endpoints as suspect; this is the first live check of them.

**Drawback of not having it:** the app is live-only. Most of what makes KEXP worth owning (a show you missed) is unreachable.

### 3. Proposed Architecture
#### 3a. Logic in `StationKit`, KEXP wiring in the adapter
Station-agnostic types in StationKit, KEXP's mapping in `StationKitAdapterKEXP` (ADR-006/007):
```
StationKit
  ArchiveShow            id, program name, host names, tagline, image URL, start and end time, tags
  ArchiveHost            id, name, image URL, program names, show count
  ArchiveProgram         id, name, hosts, tags, image URL, show count
  ArchiveCatalog         protocol: days(), hosts(), programs(), shows(on:), shows(by host:), shows(of program:),
                         playback(for show:) -> ArchivePlayback { url, offset, nextURL }
  (default)              a station that has no archive reports it, and the app hides the section
StationKitAdapterKEXP
  KEXPArchiveCatalog     the mapping above onto /v2/hosts, /v2/programs, /v2/shows and get_streaming_url
```
Reasons: the logic is testable in seconds without a simulator, and another public station can implement the protocol with no app change.

#### 3b. App layers
- **Date:** the 15-day tile grid (the website shows 15 and highlights today). **Audio depth, checked live on 2026-11-05:** `get_streaming_url` returned a file for 2026-10-22 and 2026-10-29 and `null` for 2026-10-15 and every older date I tried (2026-10-01, 2026-09-01, 2025-11-06, 2023-11-02, 2021-11-04): archived audio reaches back about two weeks, not years. Show records and song lists go back much further (`/v2/shows` returned a 2021-11-04 Afternoon Show), so older shows can be browsed and their songs listed, but not played.
- **Host / Show:** lists built from `hosts()` and `programs()`, fetched once and cached, because they change rarely. The show count per host and program on the website is derived (a `count` query), not stored by KEXP in those records (*unverified for `/v2/hosts`; to be checked*).
- **Playback:** an archived show is a file with an offset, so it uses the app's one `PlayerController`, with a different item and with seeking, a scrubber and "back to live". Now Playing shows the show, not a song. Remote commands and the lock screen stay as they are. **Probe on a device, 2026-11-06** (debug panel in the Archive tab, through the app's one `PlayerController`; Brawn, iOS 27.3):
  - *Verified:* "play from the show's start" begins at the show's opening. A file begins before its show (a show that began 07:02:50 was in a file that began 06:50:08) and the offset the station returns agrees with the filename's timestamp to the second, so `ArchiveTiming` can derive positions from either.
  - *Verified:* jumping to a song by `offset + (airdate - show start)` lands on the right song ("Little Lies" was played from the list). **Airdates run a little ahead of the audio** (owner: "they tend to be a little ahead of when the song actually plays"), so a jump lands slightly early, in the previous song's tail or the DJ. That is the safe direction; no correction is applied, since it varies by DJ and cannot be measured from here.
  - *Verified:* seeking to 30 s before the end goes to the end of the show; playing `sg-url-next` from 0 begins the next show.
  - *Verified (owner, 2026-11-06):* when a file ends, **playback just stops**; it does not roll on by itself.
  - **Decision (owner, 2026-11-06):** roll into the next show, or return to live, and line the next item up about 30 s before the end of a file. Built as: the one player is an `AVQueuePlayer`; at 30 s from the end the model says what follows (the next archived show if it has ended and has audio; otherwise live, including when the next show is the newest and began within four hours, since its file is still being written) and the player queues it. **Archive files overlap in time** (the Morning Show's file ran 06:50:08 to 10:00:29 and the next began 09:50:08), so the next file is joined where the previous one ended (`ArchiveTiming.joinOffset`: previous start + duration - next start, 621 s in that case) and not played from its start, which would repeat ten minutes. *Caveat to judge by ear:* a live stream queued 30 s early may play about 30 s behind real time, because it buffers from when it connects; the lead is one constant (`PlayerController.handoffLead`) and live could use a shorter one.
  - *Superseded:* "whether the player rolls into the next show by itself when a file ends." (answered above.) If it stops, the next file is queued ahead of the end (`AVQueuePlayer`); the "next" URL is the following show's file, so this is possible.
  - *Not yet verified:* the audio session with the radio and interruptions (phone call, route change), and the lock screen, which still shows the live song while an archive plays (Now Playing is not wired to archives).
- **Add to playlist from an archive:** a show is a list of plays; the add button applies to a play, so archived-show playlists (the song list for that show) come from `/v2/plays?show=<id>`, *unverified: confirm the filter name*.
- **Look:** resembles the website, as the owner asked, in the app's own visual language (the tiles' typography and spacing from the screenshots; the dark host/show cards; the yellow accent used for program names). It is not a copy of the website's CSS or its images; photos come from KEXP's own API URLs, from the allow-listed hosts the artwork loader already uses.

#### 3c. CarPlay
CarPlay shows the same three modes, trimmed to what a template allows: the Archive tab lists "By date", "By host", "By show" (`CPListTemplate`); By date is a short list (or `CPGridTemplate`, SDK: `CPGridTemplateMaximumItems` caps the item count) of recent days; By host and By show are lists, and a list shows only its first `maximumItemCount` items (SDK: `CPListTemplate.maximumItemCount`), so 106 hosts will need sections or a short alphabet index (*unverified: sections count against the same limit*). Apple limits how deep a template stack can go (*unverified: the figure; to be read from the CarPlay guide*); Tab → mode → host → show → play is four levels, which may fit. Photos in CarPlay lists are small; names and counts carry the meaning. This ships after the phone's browser.

### 4. API Surface (StationKit, public and documented)
The protocol and value types above; `ArchivePlayback`; no breaking change (new minor version).

### 5. MCP Schema
Not applicable.

### 6. Constraints & Compliance
Swift 6 strict concurrency; no force unwraps; gate at 0/0. **Pacing:** the API is a community service; requests go through the existing `RequestPacer`, lists are fetched once and cached, and no polling. **Privacy:** requests carry no listener identifier. **Rights:** the audio and images are KEXP's; the app streams from KEXP's own archive host, which the website itself does, and stores nothing. The README's note that KEXP and its logo belong to KEXP stands. **Accessibility:** tiles and cards are buttons with labels that read "November 5, Thursday" and "Cheryl Waters, The Midday Show, 9 shows"; Dynamic Type; Reduce Transparency.

### 7. Source & API Compatibility
Additive. The `ArchiveManager` in `KEXPPowerKit` is left alone (it is the library's and its own TODO); the new code replaces its use in the app rather than finishing it, and I will say so in the library's changelog before removing anything.

### 8. Backend Abstraction
This is the reason for the protocol: nothing KEXP-specific is in StationKit.

### 9. Resource Budget
Host and program lists are a few hundred KB at most, cached for the session. A day's shows are one request. Artwork is loaded lazily and thumbnailed. An archived stream is one HTTP audio stream, as the live one is.

### 10. Dependencies
**Internal:** StationKit (new minor), StationKitAdapterKEXP (new minor), the app. **External:** KEXP's API, as today. **Portal:** none.

### 11. Test Strategy (test first, in StationKit and the adapter)
- **Mapping (adapter, offline with recorded JSON):** a `/v2/shows` record becomes an `ArchiveShow` (hosts, program, times, tags, blank image); a host and a program likewise; the month/day/weekday labels for a date; the tile for "today" is marked.
- **Catalog behaviour:** shows for a date, for a host, for a program; empty days; paging; the playback lookup parses `sg-url`, `sg-url-next` and `sg-offset`, and treats a `null` url (what the API returns when no show matches) as "not available" rather than crashing.
- **App:** view-model tests for mode switching, selection, and the "not available" state; render tests for the tile and card layouts; a UI test (the Mac UI target now exists) that the three modes switch and a tile opens a list.
- **Live (a small, separate, opt-in suite, as the adapter already has):** one real call to each endpoint, to catch the API changing.
- **Playback across shows and on CarPlay:** manual, stated as such.

### 12. Architecture Decision Review
**New ADR-009:** *Archive access is a `StationKit` protocol with a KEXP adapter; the app does not call KEXP's archive endpoints directly.* Extends ADR-006.

### 13. Adversarial Review
1. **"The archive window is not what the website shows."** Hence the unverified marker on the 15 days; the number comes from the API, not from the screenshot.
2. **"Archive playback has gaps at show boundaries."** Possible (3b); found by playing across one before shipping, and the "next" file URL is there to bridge it.
3. **"KEXP changes the endpoints."** The opt-in live suite catches it; the protocol keeps the app insulated.
4. **"This is too big."** It is, which is why it is its own proposal, phased: (a) StationKit types and adapter with tests, (b) Date mode and playback on the phone, (c) Host and Show modes, (d) the Mac and iPad layouts, (e) CarPlay. Each phase ships and is useful alone.
5. **"Copying the website's look."** The layout idea is followed; the code, fonts and images are not copied.

### 14. Alternatives Considered
- **Open the website's archive in a web view:** no playback integration, no Now Playing, no CarPlay. Rejected.
- **Finish the library's `ArchiveManager`:** it is built around start-time steps from the nearest hour and a callback API; the API now serves a file and an offset directly, so the better path is the protocol above. Rejected as the base, kept as a reference.
- **Date mode only:** the quickest, and phase (b); Host and Show follow because the owner asked for all three.

### 15. Future Directions
Search across shows; favourite hosts and programs; downloading a show for offline listening (rights to be considered first); "add every song from this show to a playlist".

### 16. Open Questions
The archive's real depth in days; whether the host/program count comes from the API or is derived; the plays-by-show filter name; archive playback across a show boundary; CarPlay's template depth. Each is an experiment I can run against the live API except the last two, which need a device and Apple's documentation.

### 17. Documentation Strategy
README (Archive row), CHANGELOG (app, StationKit, adapter), master plan (Archive moves from "placeholder" to the roadmap with phases), ADR-009, `PlatformExperience.md` archive note updated, and `CarPlayAudio.md` links here.
