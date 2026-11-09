# ADR-010: Live rewind records the stream on the device and plays it through a local server

**Date:** 2026-11-08
**Category:** architecture
**Status:** Accepted

## Decision
The live stream is read by the app itself (`LiveRecorder`), cut at ADTS frame boundaries into segments of about two
seconds (`ADTSSegmenter`), and kept as the last ten minutes at most (`LiveBuffer`). `LiveRelay` joins them, and
`LocalHLSServer` serves an HLS playlist and the segments on `127.0.0.1`, so `AVPlayer` plays a stream that has a rewind
window, a live edge and a rate. Live is always played through this, so the window is already full when the listener
wants to rewind. The window is a setting (Off, 5 or 10 minutes; default 10); Off, and any failure to start the
recorder or server, plays the direct stream as before.

## Context
The first idea (`ArchiveTransport.md` §5) was to rewind by switching to KEXP's archive at `now - 15 s`. Probed on
2026-11-07, KEXP's archive has no audio for the show on the air, at any offset from 5 seconds to 120 minutes back, so
the idea cannot work whatever the app does. Pausing with the player's own buffer was rejected too: a paused app is
suspended within seconds, the buffer stops filling, and the 300 seconds the app can ask for is below the 5 to 10
minutes the owner wants for a subway. Asking KEXP for a live HLS stream would simplify everything and is still open.

## Consequences
- Pause, rewind, scrub, catch-up and a cushion for a dead zone all follow from one mechanism. Proven on an iPhone 15 Pro
  (Phase 0): the stream plays a steady 3 seconds behind the clock, recording continues with the screen locked, and music
  played on through two minutes of airplane mode with the player five minutes behind.
- Live plays about 3 seconds behind the station, and six to ten when the window is on; Off removes that delay.
- The window costs about 12 MB on disk at 160 kbps (5 MB at 64 kbps), cleared when the app starts and stops. The
  recorder downloads the stream the listener would have downloaded, so a playing listener uses no more data.
- The app serves HTTP on the loopback interface and carries a local-networking App Transport Security exception.
- Changing the window or the quality restarts live (`PlayerController.reconfigureLive`).
- The segmenter and buffer are generic and could move to StationKit if another station wants them; they live in the
  app for now.
- If KEXP ever offers a live HLS stream with a window, this layer can be dropped for it.
