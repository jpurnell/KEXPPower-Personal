# Archive Transport: scrubber, skip, catch up to live

**Status:** Proposed 2026-11-07. Follows `ArchiveBrowser.md` (the player that plays archived shows).

## 1. Problem

Playing an archived show gives the listener one control, "Back to live". A show runs two to four hours, and there is
no way to see where you are, jump back to a missed song, skip past a segment or pause from the screen that is playing it.
Players for recorded radio and sport (ESPN, podcast apps) offer a scrubber, a short rewind, a longer skip forward, and a
way back to the live edge.

## 2. What the listener gets

On iPhone, iPad and Mac, the bar that today says "Playing from the archive" becomes a player:

- **Play / pause.**
- **Scrubber** covering the show, with elapsed and remaining time. Dragging seeks; the time under the thumb reads as
  show time ("1:12:05"), not file time.
- **Rewind 15 s** and **forward 30 s** (the conventional pair; the asymmetry is deliberate, a rewind recovers a missed
  line and a forward skips a break).
- **Catch up to live**, a lightning-bolt button that replaces the text "Back to live" (the label stays for VoiceOver).
  Same action as today: `returnToLive`.
- The lock screen, Control Center, CarPlay and headphones get the same commands through the system Now Playing screen
  (`MPRemoteCommandCenter`): play, pause, skip back 15, skip forward 30, scrub (`changePlaybackPosition`). While the
  player is on the live stream those skip and scrub commands stay disabled, as the system expects for a live stream.

## 3. The timeline is the show, not the file

Facts from the probe (`ArchiveBrowser.md`): a file starts before its show (the offset says how far in the show begins),
and files overlap by about ten minutes. A scrubber over the raw file would start at a few minutes of someone else's show
and end in the next one.

- **Range:** from the show's offset to the show's end. The end is the next show's start time (the index already finds the
  next show), minus this show's start, added to the offset; clamped to the file's real duration. If there is no next show
  (the one on the air), the range runs to the file's end as it is so far.
- **Position:** `player time − offset`, clamped to the range.
- **Seeking before the start** clamps to the show's start (no wandering into the previous show's tail).
- **Skipping or scrubbing past the end** rolls into the next show through the roll-over that already exists
  (`ArchiveContinuation`), or to live if there is none.

All of this arithmetic goes in one pure type, `ArchiveTransport`, with no player in it: `range`, `position(at:)`,
`seekTarget(skip:from:)`, `seekTarget(fraction:)`. It is where the tests are.

## 4. Pieces

| Piece | Change |
|---|---|
| `ArchiveTransport` (new, pure) | Range, position, skip and scrub targets, time text. Tested first. |
| `ArchivePlayer` protocol | Adds `position`/`duration` (observed), `pause`/`resume`, `seekArchive(to:)`. Fake player in tests. |
| `PlayerController` | Publishes position (a periodic observer, about twice a second, only while playing an archive); registers remote commands; sets elapsed time and rate in the Now Playing info so the lock screen scrubber moves without polling. |
| `ArchiveBrowserModel` | Owns an `ArchiveTransport` for the playing show; `skip(by:)`, `scrub(to:)`. |
| `NowPlayingArchiveBar` | Becomes the player view described in §2; compact on iPhone, wider on iPad and Mac. |

## 5. Not in this change

- **Rewinding the live stream.** ESPN's "catch up to live" implies a live stream you can pause and rewind. KEXP's live
  stream cannot; but the archive may cover the last few minutes (`get_streaming_url` takes a timestamp), which would let
  a "rewind 15 s" on live switch to the archive at `now − 15 s`, with the bolt coming back. It needs a probe: how close to
  "now" does the archive's file reach, and does it ever refuse? Decide after the probe; the transport here is built so it
  can adopt that.
- Per-song jumps (tapping a song in the show's playlist to seek there). Separate phase in `ArchiveBrowser.md`.
- Playback speed.

## 6. Risks

- **Airdates run ahead of the audio** (known). The scrubber is time-based and does not depend on song dates, so it is
  unaffected; per-song jumps will be.
- **The end of the range is an estimate** when the show ran over or under its slot. The next show's start is the best
  data available; the roll-over still happens at the real end of the file.
- **Position updates and SwiftUI:** a half-second observer must not redraw the whole Archive screen. Position lives in
  its own small observable that only the bar reads.
- **Remote commands are global.** They must be enabled only while an archive show is playing and removed when it stops,
  or the lock screen shows dead buttons on the live stream.

## 7. Test plan (red first)

`ArchiveTransport`: range with and without a next show; clamped to file length; position at, before and after the
offset; skip back at the start stays at the start; a skip forward that reaches the end of the show (or a scrub to 100%) goes on to what follows rather than landing on the end; scrub by
fraction; NaN and infinite durations give an empty range, not a crash. `ArchiveBrowserModel` with the fake player:
`skip` and `scrub` seek to the right file time; skipping past the end calls the continuation. Remote command wiring and
the bar's layout are checked on the devices, since neither is reachable by an automated test.

## 8. Order of work

1. `ArchiveTransport` and its tests.
2. Player protocol, fake, model methods.
3. `PlayerController` position and Now Playing elapsed/rate; remote commands.
4. The bar's view, on iPhone then iPad/Mac.
5. Device check on Brawn and Springer; lock screen and CarPlay on the way.
6. Live-rewind probe, as a separate decision.
