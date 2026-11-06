# Design Proposal: Review section for held Apple Music matches (with Apple Music playback)

**Status:** PROPOSED 2026-11-06, with the album-art addition the same day (from the owner's CarPlay test: a held "Fly Like an Eagle" match interrupted the phone with a live prompt, and the car button was a bare "?"; owner: "shouldn't this just go to the resolution queue", then "a review section would be better, offering Apple Music playback")
**Date:** 2026-11-06
**Master Plan Reference:** `CarPlayAudio.md` §3b-2 ("a text-search match is not guessed at: it is kept as 'needs review' and the phone shows it when the driver is parked"). That sentence promised a queue; what was built is a transient prompt.
**Facts marked (repo) were read in this repository on 2026-11-06. Anything not confirmed is marked *unverified*.**

---

### 1. Objective
A text-guess match from Apple Music is never added on a guess and never loses the song. It goes into a **Review** section where, when parked, the listener can hear the Apple Music version, then add it or reject it.

### 2. Motivation
**Current situation (repo):**
- `SaveState.confirming(CatalogSong)` is held in `SongSavingModel.states`, a dictionary in memory keyed by the KEXP play id. It is lost when the app quits, and the phone shows it as an immediate "Is this the song?" prompt (`SaveButton`).
- From the car this is wrong twice: the prompt appears on a phone nobody is looking at, and the car's button shows only a question mark. Verified on a device 2026-11-06: pressing add in CarPlay on "Fly Like an Eagle" produced `confirming(...)` in the log and the prompt on the phone.
- The saved-pairs ledger (`UserDefaultsSaveLedger`) is persisted; held matches are not.

**Drawback:** the song is only held while the app lives and the prompt is on screen. A driver who presses add on three songs has three prompts stacked up, or none.

### 3. Proposed Architecture
#### 3a. A persisted queue (logic, tested without a device)
`ReviewQueue`, an `@Observable @MainActor` type over a small store protocol (`UserDefaults`-backed in the app, in-memory in tests, as the ledger is). An entry holds: the KEXP play id, what KEXP played (title, artist, album), the Apple Music candidate (`CatalogSong`), the extra playlist chosen if any, and when it was held. It also keeps the **album art**, saved as small image files, not links (3f). It is `Codable`, capped (200 entries; oldest dropped, *a number to confirm*), de-duplicated by play id, and refuses a song already saved.

#### 3b. Where entries come from
- **From the car:** a held match is enqueued with no prompt. The car shows one notice, "Saved for review", and the button shows a tray symbol, not a question mark.
- **From the phone:** pressing add on a text match keeps today's immediate prompt, because the listener is looking at it, and gains a third choice, **Review later**, which enqueues it. "Not this one" still discards.
- **Exact (ISRC) matches** are unchanged: added at once from either place.

#### 3c. The Review section
A new `AppSection.review` on the iPhone and iPad (a tab, with a count badge) and in the iPad sidebar. **Archive and Playlists stay visible as placeholders.** Each row shows what KEXP played with its cover, and the Apple Music guess beneath it (artist, title, album) with *its* cover beside the first, so the two versions can be compared by eye (3f). Three actions:
- **Play** — hear the Apple Music version (3d).
- **Add** — saves through the existing `SongSavingModel.confirm`, then removes the entry.
- **Not this one** — removes the entry. *(Later: offer the other search results, which the catalog search already returns up to ten of.)*

An empty queue says so. The Mac has no playlist add (MusicKit playlists are the iPhone's feature), so the section is not shown there.

#### 3d. Apple Music playback
The point is to *hear* whether it is the right song. Two routes:
- **A 30-second preview** from the catalog entry (`Song.previewAssets`, *unverified in this SDK*): no subscription needed, short, and does not need the player.
- **The full song** through MusicKit's player (*unverified: availability on iOS 17, and whether it needs a subscription the add path already needs*).

I would build the **preview first**: it answers "is it the right song" and avoids two long-running players. **The live stream is paused while a preview plays, and is not resumed automatically** (the listener asked to hear a song; surprising audio later is worse). *Unverified: how the preview's audio session interacts with the stream's `AudioSessionCoordinator`.* This is the largest unknown and is checked on a device before the UI is built on it.

#### 3f. Album art, saved down (owner's addition, 2026-11-06)
The cover is often the fastest way to tell the original from a reissue or a Greatest Hits copy, so both are kept:
- **What KEXP played:** `Track.artworkURL` (repo: it exists, `Track.swift`).
- **The Apple Music candidate:** `CatalogSong` has **no artwork field today** (repo: `id`, `title`, `artist`, `album` only). It gains an optional `artworkURL` (a StationKit minor, additive; `MusicKitCatalog` fills it from the catalog item's artwork, *unverified: the exact MusicKit call that returns a URL at a chosen size*).
- **Saved, not linked:** when an entry is queued the images are fetched once, shrunk with the existing `ArtworkThumbnail` (400 px JPEG, repo) and written beside the queue (`Application Support/Review/`). Links alone are not enough: they can expire or be unreachable on a train, and the review happens later, away from the moment. Fetching is best-effort and off the car's critical path: the entry is queued first, and a missing image shows a placeholder, never blocks or fails the queue.
- **Cleaned up:** an image is deleted when its entry is added or rejected, and orphans (a file with no entry) are swept at launch, so the folder cannot grow.
- **Hosts:** images load only from the allow-listed artwork hosts the app already uses (KEXP's, and Apple's image host for the catalog, *to be added after confirming the host*).

#### 3e. CarPlay
`CarPlayContent.saveNotice` already exists (built 2026-11-06 with its tests, as an alert saying "Review on your phone"); it is reworded to "Saved for review" and shows the held song. The button symbol for a held match stays a phone-or-tray icon (tests exist). Nothing else in the car changes.

### 4. API Surface
Internal to the app target: `ReviewQueue`, `ReviewEntry`, `ReviewStore`, `ReviewArtworkStore`, `ReviewView`, and a preview-playback seam. One public addition: `CatalogSong.artworkURL` (optional, defaults to `nil`) in StationKit, with its adapter wiring: a minor version, nothing breaks. *If a second station app needs it, the queue moves to StationKit with the ledger.*

### 5. MCP Schema
Not applicable.

### 6. Constraints & Compliance
Swift 6 strict concurrency; no force unwraps; gate at 0/0. **Privacy:** the queue holds song titles in the app's own storage; no listener identifier leaves the device. **Accessibility:** each action is a labelled button; the row reads as "Fly Like an Eagle by Steve Miller Band; Apple Music suggests Fly Like an Eagle, Greatest Hits 1974-78". **Rights:** previews are Apple's, played through Apple's API.

### 7. Source & API Compatibility
Additive; StationKit's `CatalogSong` gains a defaulted field, so existing callers and tests compile unchanged. `SongSavingModel` gains an `onHeld` hook (or the queue observes it); the existing `confirming` state and its tests are kept. Existing saves are unaffected.

### 8. Backend Abstraction
The queue holds `Track` and `CatalogSong` from StationKit, which are station- and catalog-agnostic.

### 9. Resource Budget
A few KB of stored entries, plus two thumbnails per entry (about 30-60 KB each at 400 px; at the 200-entry cap, tens of MB at most, *to measure*, and smaller if the cap or size is lowered). Previews stream one at a time. No polling.

### 10. Dependencies
None new. MusicKit is already used by `MusicKitCatalog` and `MusicKitPlaylists`.

### 11. Test Strategy (test first)
- **Queue:** enqueue stores an entry; a repeat of the same play id does not duplicate; a song already saved is refused; the cap drops the oldest; the queue survives being rebuilt from its store; add removes the entry and saves through the existing path; "not this one" removes it; the count is right.
- **Entry points:** a car press enqueues without raising the prompt; a phone press still raises it; "Review later" enqueues.
- **Persistence:** round-trips through the real store and tolerates unreadable data (reads as empty).
- **Artwork (red first):** queuing saves both images and the entry points at them; a failed or missing image still queues the entry; removing an entry deletes its files; a file with no entry is swept; the image is shrunk by `ArtworkThumbnail`; a host not on the allow-list is not fetched. These use a fake fetcher and a temporary folder, no network. In StationKit: `CatalogSong` carries an optional `artworkURL`.
- **Preview seam:** play, stop and "another row started" behave with a fake player; the stream is paused first.
- **On a device (stated as manual):** the preview is audible and the right song, the stream's behaviour afterwards, the car notice, and the badge.

### 12. Architecture Decision Review
No new ADR. It applies ADR-008 (the car and phone share one model) and keeps held-match logic out of the views.

### 13. Adversarial Review
1. **"A queue nobody reads grows forever."** Capped, with a badge on the tab so it is seen.
2. **"A held song gets added twice."** The ledger and de-duplication by play id; add checks the ledger.
3. **"Playing a preview cuts off the radio."** Stated in 3d: the stream pauses, and does not silently resume.
4. **"Previews are not what KEXP played."** Correct: a preview is the *candidate*; the listener judges it against what KEXP showed, which the row displays above it.
5. **"The saved images fill the phone."** Thumbnails only, capped with the queue, deleted with the entry, orphans swept (3f).
6. **"The Mac gets no Review."** Stated; it cannot add to playlists.

### 14. Alternatives Considered
- **Keep the live prompt only, but make it work from the car:** needs a decision while driving, which the owner agreed is unsafe.
- **Auto-add the top text match:** wrong songs in a playlist; rejected earlier.
- **Put the queue inside Playlists:** the owner chose a separate Review section.

### 15. Future Directions
Choose from the other search results; "Add all that match well"; the same queue for archived shows.

### 16. Open Questions
Preview availability and audio-session behaviour (3d); whether the full song is wanted; the queue's cap; the MusicKit call for artwork at a size, and Apple's image host (3f).

### 17. Documentation Strategy
README (Review row), CHANGELOG, master plan (Review section added; Archive and Playlists still placeholders), `CarPlayAudio.md` §3b-2 links here.
