# Design Proposal: Pausing, rewinding and cushioning the live stream

**Status:** DIRECTION AGREED 2026-11-07 (owner: "pause and resume and rewind if possible"; the use is a subway, with "a 5-10 minute cache"). APPROVED 2026-11-07 to build through Phase 0 (owner: "ok with the 10 minute window with the 5 minute rewind, and we should make that a setting"); §8 records the decisions. Earlier the same day it was PROPOSED, from the request for "catch up to live" in the style of ESPN's app, and from `ArchiveTransport.md` §5, which held live rewind back until a probe said whether KEXP's archive could do it. **It cannot; see §2.** BUILT 2026-11-07/08, Phases 0 to 2 (see §4), with Settings (§10) shipped as `project/plans/upcoming/Settings.md`. Not yet checked on a device: skip and scrub on the lock screen, the song following in the car, and a dead zone on a subway. Phase 3 is unbuilt.
**Date:** 2026-11-07
**Master Plan Reference:** Roadmap, Phase 3 (Live rewind); `ArchiveTransport.md` §5 (superseded by this document).
**Facts marked (live) were checked against `api.kexp.org` and `kexp.streamguys1.com` on 2026-11-07; (repo) in this repository or `KEXPPowerKit`. Anything not confirmed is marked *unverified*.**

---

## 1. Objective

While the live stream plays, let the listener pause it and come back to where they were, go back a few seconds or a few
minutes, and return to the live edge with the bolt, as they can for an archived show. And let them listen a few minutes
behind live on purpose, so that a dead zone on a subway line does not stop the music.

## 2. What the probes found

The first idea (`ArchiveTransport.md`) was: rewinding 15 seconds on live switches to KEXP's archive at `now − 15 s`. It
does not work, for a reason that is in KEXP's data and not in anything we can build around:

- **The archive has no audio for the show on the air (live).** On Saturday 2026-11-07, asking `get_streaming_url` for
  any moment during Positive Vibrations (on since 9:00 PST) returned `null`, at 5 s, 15 s, 30 s, 1, 2, 5, 15, 30, 45,
  60, 90 and 120 minutes ago. Asking for a moment in the previous show (Sounds of Survivance, which ended at 9:00)
  returned its file. A show's file appears only after the show is over. How long after is *unmeasured*.
- **The live stream cannot rewind itself (live).** `kexp.streamguys1.com/kexp160.aac` and `kexp64.aac` are Icecast
  streams of raw AAC (`audio/aac`, `icy-metaint: 0`), with no `Accept-Ranges` header and no HLS variant (the two HLS
  addresses tried answer 404). A server-side window, which is how most apps do this, does not exist.
- **The player does not keep what it has played (general `AVPlayer` behaviour for a progressive stream; not tested
  here).** It can hold audio *ahead* of the playhead (the app already asks for 300 s, repo), not behind it, and a live
  stream reports no seekable range.

So the only audio that can ever be rewound on live is audio the app itself has kept.

## 2b. What a cushion can and cannot do

This matters for the subway, so it is stated before the design.

A broadcast cannot be fetched again. When the connection drops for three minutes, the three minutes of audio broadcast
in that time are not delivered later, and KEXP's archive will not have that show's file until it has ended (§2).

What a cushion *can* do: if the listener is already five minutes behind live when the signal goes, the player has five
minutes of audio ahead of it and plays through the dead zone without a break. When the signal returns, playback runs on
through what was cached, and then **jumps forward over the minutes that were missed**, to the audio that arrived after.
The listener hears music the whole time and misses a stretch of the broadcast; they do not hear silence, or a spinner.

The cushion therefore bridges a dead zone no longer than its length, and the missed audio is skipped, not recovered. A
dead zone longer than the cushion still ends in silence. The listener has to be behind live *before* the dead zone:
a cushion cannot be built once the signal has gone.

## 3. Options

**A. Rewind through the archive.** Rejected: §2.

**B. Pause live and resume, using the player's own buffer; no rewind.** The player reads ahead while playing, so a pause
could resume at the paused moment. Rejected as the whole answer, because it cannot give the subway cushion: a pause puts
the app in the background, where iOS suspends it within seconds and the buffer stops filling; the 300 s the app asks for
is below the 10 minutes wanted; and whether `AVPlayer` keeps buffering a paused Icecast stream at all, and whether the
server drops a client that stops reading, is *unverified*.

**C. A time-shift buffer on the device (chosen).** The app reads the live stream itself, keeps the last N minutes, and
plays from that. Pause, rewind, scrub, a cushion and catch up all follow from one mechanism. AAC in ADTS framing can be cut
at frame boundaries, so:

- `LiveRecorder` reads the stream (`URLSession` bytes), cuts it at ADTS frame boundaries into segments of about two
  seconds, writes them to a temporary folder, and keeps the last N minutes. If the connection drops, it retries with a
  backoff, and when the stream returns it starts a new segment marked as a discontinuity, so the player jumps the hole.
- `LocalHLSServer` serves a live HLS playlist and the segments on `127.0.0.1` (Network framework), so `AVPlayer` plays a
  stream that *does* have a rewind window, with `seekableTimeRanges`, a live edge and a rate, all natively. (Packed-audio
  HLS needs an ID3 timestamp on each segment, per Apple's HLS specification, which I have not re-read for this; the
  recorder would write it.)
- **Live is always played through this**, so that the window is already full when the listener wants to rewind. If the
  recorder or server cannot start, the app falls back to the direct stream it uses today.
- `LiveWindow`, a pure type like `ArchiveTransport`, holds the arithmetic: the window, how far behind live the playhead
  is, skip and scrub targets. The lock screen and the car use StationKit's transport commands, already built.
- **Size is small:** 160 kbps is about 20 KB a second, so a 10-minute window is about **12 MB** on disk (5 MB at the 64
  kbps data-saver rate), cleared when the app starts and stops. The recorder downloads the same stream the listener
  would have; it adds no data while playing, and only a little (the stream continues while paused) when the app is alive.

The pieces are three new types and a local server, with its App Transport Security exception for local networking, and a
StationKit release if the segmenter is to be reusable. Large, but each piece is testable on its own (§7).

**D. Leave live as it is.** The slim live bar already pauses and plays; the bolt already reconnects.

## 4. Recommendation

Build C, in phases, each ending in something that can be tried on a device.

- **Phase 0 (built, proven on a device 2026-11-07), a spike (the risk is here, so it comes first):** the segmenter, tested first against a recorded stretch of
  the stream; the local server; and `AVPlayer` playing live through them on Brawn. Then the two questions that decide
  whether C works at all, answered by trying them: does it keep recording with the screen locked, and does playback
  ride through airplane mode for as long as the cushion lasts and then jump the hole.
- **Phase 1 (built):** `LiveWindow` and the UI on the slim live bar and the Live screen: a "behind live" clock, back 15, back 5
  minutes, a scrubber over the window, pause and the bolt. Tested like `ArchiveTransport`.
- **Phase 2 (built; checked in tests only):** the lock screen and CarPlay, through `NowPlayingPublishing.installTransportCommands` (done, StationKit
  0.11.0); the playlist and Now Playing text aligned to what is being heard instead of the live edge.
- **Phase 3, if wanted (not built):** a setting for the cushion ("Stay 5 minutes behind live") that holds the playhead behind live
  once it is there.

## 5. Risks

- **Latency.** HLS plays a few segments behind the live edge by design. With two-second segments the "live" position
  would be roughly six to ten seconds behind the direct stream's, which is perceptible against the radio in the room, and
  against the song shown on screen (which comes from the API). It is the price of always having a window. *Unmeasured*;
  Phase 0 measures it.
- **Pausing suspends the app.** On a pause the audio session stops and iOS suspends the app within seconds, which stops the
  recorder, so a long pause in the background leaves a gap. The window then continues from before the pause and jumps
  the gap when playback resumes. The cushion of §2b is built by *playing* behind live, not by pausing for ten minutes.
  Keeping a session alive by playing silence is a workaround I would not rely on.
- **Background execution** is the biggest unknown: whether the recorder keeps downloading, and the local server keeps
  answering, while the screen is locked and audio is playing. Expected to work (audio is a background mode), *unverified*:
  it is the first thing Phase 0 tries.
- **A local HTTP server in the app** is more surface than the app has today. It binds to the loopback address only, serves
  nothing but the segments, and takes a random port.
- **Mac, Watch and CarPlay.** The Mac and CarPlay share the player and would get it. The watch has its own player
  (`WatchPlayer`) and would not, in this proposal.
- **Song information stays live.** The playlist and Now Playing text come from KEXP's API, which describes the live
  edge. While the listener is behind it, the app would show the song for the live edge unless the plays' times are lined
  up with the window. That is solvable (the archive playlist already does it) and is Phase 2.

## 6. Alternatives considered

- **Ask KEXP for a live HLS stream with a rewind window.** The right fix, and it is KEXP's to give: it would remove
  the recorder and the local server and make this a small change on the app side. Worth asking if the owner knows someone
  there; it does not need to hold this up.
- **Cache audio inside `AVPlayer` with a custom `AVAssetResourceLoader`.** Possible for a progressive stream, but the app
  would then be writing its own seekable media server inside the loader; the local HLS server uses what the system
  already does well.
- **Play slightly slower to build a cushion gradually.** Rejected: at 0.9× a five-minute cushion takes fifty minutes,
  and the sound changes.

## 7. Test strategy

`LiveWindow`: the window's bounds, how far behind live, skip and scrub targets, a window shorter than a skip, a hole in
the window, NaN inputs. `LiveRecorder`'s segmenter: a recorded stretch of ADTS bytes cut at frame boundaries with no
frame split, a segment that begins mid-frame, the oldest segment dropped at the cap, a dropped connection and the
discontinuity after it. `LocalHLSServer`: playlist and segment responses for a known buffer, a playlist that moves its
media sequence as segments are dropped, and nothing served for a path outside the buffer. Playback itself, the
background behaviour, the latency, and riding through a dead zone: only on a device, and Phase 0 is built to find out
early.

## 8. Decisions

1. **Window length: decided 2026-11-07.** A 10-minute window with a 5-minute rewind button, **as a setting** (§10).
2. **Latency: resolved by the setting.** The window setting has an **Off** choice, which plays the direct stream as today,
   without the extra six to ten seconds and without rewind. On (5 or 10 minutes) plays live through the buffer. The
   default is 10 minutes, since the owner wants the cushion; the first ten minutes of a listen have a shorter window,
   which the scrubber shows. *Not asked of the owner directly; changing the default is a one-line change.*
3. **Asking KEXP about a live HLS stream first.** Not a blocker; it would simplify everything if they can. Open.

## 10. Settings

**Built 2026-11-08; the design, its decisions and the order of work are in `project/plans/upcoming/Settings.md`. What follows is the original ask, kept as written.**

The owner: "I think we are approaching a point where settings might start looking useful." The app has one setting today
(stream quality, in Settings on macOS only). This feature needs the first one that matters on every platform, so it is
also the moment to give the app a Settings screen. Proposed contents, only what the app can already do:

- **Rewind window:** Off, 5 minutes, 10 minutes (default 10). The rewind button jumps back by the smaller of 5 minutes
  and the window.
- **Stream quality:** 64 kbps (data saver) or 160 kbps. It exists on the Mac; the iPhone and iPad have no way to choose it
  today, and it changes the window's size on disk.
- **Times in:** my time zone or the station's. The archive now shows times in the listener's zone while its days stay
  Seattle's (`master_plan.md`, Known Problems); a choice lets a listener see one or the other.

Where it lives: a screen on iOS and iPadOS (a gear in the sidebar or tab list), the system Settings scene on the Mac
(which already has the quality control), and the values in `UserDefaults`, read through one small tested type. The
screen is its own small design proposal when the window setting is built; this section only fixes what it must hold.

## 9. Documentation strategy

On approval: this file's status; the master plan's Roadmap item; the README's "not built yet" list; `ArchiveTransport.md`
§5, which already points here. An ADR for the local server and the buffer once Phase 0 has said whether it works.
