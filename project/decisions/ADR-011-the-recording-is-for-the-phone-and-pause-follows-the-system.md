# ADR-011: Live plays through the recording only where the phone renders the sound; a pause the system asks for is followed

**Date:** 2026-11-17
**Category:** architecture
**Status:** Accepted (decisions quoted below are the owner's, 2026-11-17)
**Amends:** ADR-010 (live rewind by local recording)

## Decision
1. **Where the sound goes decides what live plays.** `PlaybackSource` (phone, receiver, unknown) is read from the audio route and from whether the player handed playback to something external. `LivePlan.choose` returns `.recording` only for the phone; a receiver or an unknown route plays the stream's own address (`.direct`, with a reason that is journaled). Unknown plays the stream: *"Unknown plays the stream is the right fallback."* `CarAudio`, wired and Bluetooth headphones and the speaker are allow-listed as the phone.
2. **The controls follow the plan.** `PlaybackCapabilities.canRewind` is decided with the plan, before the item exists, so they do not change mid-start. A direct stream has no rewind.
3. **A move to a receiver while the recording plays switches to the stream once, at the live edge** (*"live edge is right"*). Moving back to the phone does not switch back by itself.
4. **A live item carries the track's metadata when it is made.** A receiver reads title and artwork from the item it plays; the phone's lock screen reads the system's Now Playing info. Both come from one snapshot. An item made at launch with metadata edited in later was not shown by the display (observed 2026-11-17, fixed in `65f872f`).
5. **A pause the system asks for is followed and recorded, not overridden.** An output device removed (for example switching an AirPlay receiver to "iPhone Speaker") pauses both devices; that is the system's model, as Apple News shows. The listener's own pause and a remote-control pause always pause. The journal records each audio-session action and route change with its reason (`ff1ea3a`).
6. **A live item that goes away while the listener wants audio is put back, without a press**, at most three times without audio in between (`cf52d1f`).

## Context
ADR-010 plays live through a recording served on `127.0.0.1`. An AirPlay receiver (the owner's Kitchen display, which presents as CarPlay views and reports `AirPlay`) fetches the item itself and cannot reach the phone's loopback address: starts took about 24 s of stutter, then 4.3 to 4.8 s once the stream was played directly (observed on Brawn and the display, 2026-11-17). The owner rejected serving the recording over the LAN: the display is *"meant to play indefinitely in the home"*, which would make the phone a server for the whole session and not independent of it. The owner expects the same approach to extend to wearables such as AR glasses.

## Consequences
- Rewind exists only where the phone renders the sound. A receiver plays the stream with no recording window; this is accepted.
- A receiver start is about 4 to 6 s against 0.5 s on the phone. Item ready and playing are reached in 0.5 s; the rest is the receiver's. It is journaled as phases and is to be measured over about twenty starts before any tuning.
- An answered FaceTime Audio call did not interrupt a receiver playing the stream (verified on the display); cellular and declined calls are untested.
- `CarAudio` is treated as the phone and is unverified in a real car.
- A new surface needs one line in `PlaybackSource` (and an observation), not a fix in the player.
- Open: `plan`, `reason` and `surface` on the `liveStart` hub event need a schema change, which needs the owner's approval.

Design: `project/plans/proposals/ExternalSurfaces.md`.
