# Design Proposal: Pausing and rewinding the live stream

**Status:** PROPOSED 2026-11-07 (from the owner's request for "catch up to live" in the style of ESPN's app, and from `ArchiveTransport.md` §5, which held live rewind back until a probe said whether KEXP's archive could do it). **It cannot; see §2.** What remains is a choice between a small feature and a large one.
**Date:** 2026-11-07
**Master Plan Reference:** Roadmap, Phase 3 (Live rewind); `ArchiveTransport.md` §5 (superseded by this document).
**Facts marked (live) were checked against `api.kexp.org` and `kexp.streamguys1.com` on 2026-11-07; (repo) in this repository or `KEXPPowerKit`. Anything not confirmed is marked *unverified*.**

---

## 1. Objective

While the live stream plays, let the listener pause it and come back to where they were, go back a few seconds to hear
something again, and return to the live edge with the bolt, as they can for an archived show.

## 2. What the probes found

The idea in `ArchiveTransport.md` was: rewinding 15 seconds on live switches to KEXP's archive at `now − 15 s`. It does
not work, for a reason that is in KEXP's data and not in anything we can build around:

- **The archive has no audio for the show on the air (live).** On Saturday 2026-11-07, asking `get_streaming_url` for
  any moment during Positive Vibrations (on since 9:00 PST) returned `null`, at 5 s, 15 s, 30 s, 1, 2, 5, 15, 30, 45,
  60, 90 and 120 minutes ago. Asking for a moment in the previous show (Sounds of Survivance, which ended at 9:00)
  returned its file. A show's file appears only after the show is over. How long after is *unmeasured*; it does not
  matter for a 15-second rewind.
- **The live stream cannot rewind itself (live).** `kexp.streamguys1.com/kexp160.aac` and `kexp64.aac` are Icecast
  streams of raw AAC (`audio/aac`, `icy-metaint: 0`), with no `Accept-Ranges` header and no HLS variant (the two HLS
  addresses tried answer 404). A server-side window, which is how most apps do this, does not exist.
- **The player does not keep what it has played (general `AVPlayer` behaviour for a progressive stream; not tested
  here).** It can hold audio *ahead* of the playhead (the app already asks for 300 s, repo), not behind it, and a live
  stream reports no seekable range.

So the only audio that can ever be rewound on live is audio the app itself has kept.

## 3. Options

**A. Rewind through the archive.** Rejected: §2, the audio is not there.

**B. Pause live, resume where you left off; no rewind.** The player already reads ahead (300 s) while playing. If it
keeps reading while paused, a pause of up to about five minutes resumes at the paused moment, and the listener is then
some minutes behind live. The screen would say "Paused · 2:14 behind live" and the bolt would return to live (the same
reconnect as the archive's, about 4 s). Back 15 on live would be unavailable. Small: a clock, a label, and a fix if the
player drops the stream while paused.
*Unverified, and the whole of the option:* whether `AVPlayer` keeps buffering a paused Icecast AAC stream, for how long,
and whether Icecast drops a client that stops reading. Phase 0 below tests it on a device.

**C. A time-shift buffer on the device.** The app reads the live stream itself, keeps the last N minutes, and plays from
that, so pause, rewind, scrub and catch up all work, for any window N. The workable shape, since AAC in ADTS framing can be
cut at frame boundaries:

- `LiveRecorder` reads the stream (`URLSession` bytes), cuts it at ADTS frame boundaries into segments of about six
  seconds, writes them to a temporary folder, and keeps the last N minutes.
- `LocalHLSServer` serves a live HLS playlist and the segments on `127.0.0.1` (Network framework), so `AVPlayer` plays a
  stream that *does* have a rewind window, with `seekableTimeRanges`, a live edge and a rate, all natively. (Packed-audio
  HLS needs an ID3 timestamp on each segment, per Apple's HLS specification, which I have not re-read for this; the
  recorder would write it.)
- `LiveWindow`, a pure type like `ArchiveTransport`, holds the arithmetic: the window, how far behind live, skip and
  scrub targets. The lock screen and the car use StationKit's transport commands, already built.
- 160 kbps is about 72 MB an hour, so a 30-minute window is about 36 MB on disk, cleared when the app starts and stops.

Large: three new pieces, a local server and its App Transport Security exception for local networking, and a StationKit
release if the segmenter is to be reusable. And it has costs in §5.

**D. Leave live as it is.** The slim live bar already pauses and plays; the bolt already reconnects.

## 4. Recommendation

Phase 0 first, then B if it holds, and C only if the owner wants rewind enough to take its costs.

- **Phase 0 (an afternoon):** a debug-only probe on the device, like the archive probe, logged to `DiagnosticLog`: play
  live, pause for 30 s, 2 min and 6 min, resume, and record where playback resumes and whether the stream survived.
  This turns B's unverified premise into a fact.
- **If B holds:** build it, with tests for the "behind live" arithmetic and for the label, as the archive transport was
  built. Rewind on live stays out, and the proposal says so on screen by not offering it.
- **C** is a feature of its own, to be approved separately once the owner has seen B.

## 5. Risks, mostly of C

- **Pausing suspends the app.** On a pause the audio session stops and iOS suspends the app within seconds, which stops
  the recorder, so a pause of any length in the background leaves a gap in the buffer. Keeping a session alive by
  playing silence is a workaround I would not rely on. C therefore works reliably while the app is
  playing or in front of the listener, and degrades to "the window starts again when you resume" otherwise. B has the
  same shape of limit: the player's buffer fills only while the connection is alive.
- **Data and battery.** C downloads the stream whenever live is the current source, paused or not. That needs Low Data
  Mode handling and a clear off switch.
- **A local HTTP server in the app** is more surface than the app has today. It binds to the loopback address only, serves
  nothing but the segments, and takes a random port.
- **Mac, Watch and CarPlay.** The Mac and CarPlay share the player and would get it. The watch has its own player
  (`WatchPlayer`) and would not, in this proposal.
- **Song information stays live.** The playlist and Now Playing text come from KEXP's API, which describes the live
  edge. While the listener is behind it, the app would show the song for the live edge, not for what they are hearing,
  unless the plays' times are lined up with the window. That is solvable (the archive playlist already does it) and
  is a part of C's size.

## 6. Alternatives considered

- **Ask KEXP for a live HLS stream with a rewind window.** The right fix, and it is KEXP's to give: it would make this
  proposal a small change on the app side. Worth asking if the owner knows someone there.
- **Cache audio inside `AVPlayer` with a custom `AVAssetResourceLoader`.** Possible for a progressive stream, but the
  app would then be writing its own seekable media server inside the loader; the local HLS server uses what the system
  already does well.

## 7. Test strategy (if built)

`LiveWindow`: the window's bounds, how far behind live, skip and scrub targets, a window shorter than a skip, NaN
inputs. `LiveRecorder`'s segmenter: a recorded stretch of ADTS bytes cut at frame boundaries with no frame split, a
segment that begins mid-frame, the oldest segment dropped at the cap. `LocalHLSServer`: playlist and segment responses
for a known buffer, and nothing served for a path outside it. Playback itself, and the pause behaviour of §3 B, only on
a device.

## 8. Decisions for the owner

1. Is "pause live and come back" (B) most of what is wanted, or is rewinding (C) the point?
2. If C, how long a window: five minutes, thirty, an hour?
3. Is it worth asking KEXP about a live HLS stream first?

## 9. Documentation strategy

On approval: this file's status; the master plan's Roadmap item; the README's "not built yet" list; `ArchiveTransport.md`
§5, which now points here. If C is built, an ADR for the local server and the buffer.
