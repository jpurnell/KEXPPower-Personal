# Spinner

A fast, native Apple-platform listener for KEXP 90.3 FM (Seattle): the live playlist, the live stream, and (eventually) one-tap saving to a dedicated Apple Music playlist. It is meant to be quicker and friendlier than the station's own app, and to be built from parts other public-radio stations can reuse.

**Status: 3.3.0 released, private; the archive is built on top of it and unreleased.** It plays the live stream and shows the playlist and show on iPhone, iPad, Mac, Apple Vision Pro and Apple Watch, with a Now Playing widget (small, medium, large) on iPhone, iPad, Mac and Vision Pro, a sidebar and a mini player on the Mac. Add to Apple Music playlist works on iPhone, iPad and Vision Pro (MusicKit cannot write playlists on the Mac). The archive (unreleased) lets you browse the last two weeks by date, host, show or genre and play a show from its start or from a song, with a player that stays over every section: scrubber, back 15, forward 30, and a bolt to catch up to live; the lock screen and CarPlay's Now Playing screen get skip and scrub too. Not built yet: the archive's Mac layout and CarPlay tab, live rewind, and Siri and Shortcuts intents. See `project/master_plan.md` and `project/plans/upcoming/PlatformExperience.md`.

| Platform | Target | Notes |
|---|---|---|
| iOS / iPadOS 17 | `KEXPPowerExampleSwiftUI (iOS)` | lock-screen Now Playing, background audio; Archive and its player; CarPlay Audio (Live, with the show and host, and add to playlist; the Archive tab is not built yet); embeds the watch app |
| macOS 14 | `Spinner Mac` | own target and entitlements; plays the stream; Playback menu (Space); keyboard access to rows; Open in Music; the archive and its player (shared code, not yet given a layout of its own); UI tests (`Spinner Mac UITests`) |
| visionOS 1 | shares the iOS target | |
| watchOS 10 | `Spinner Watch`, `Spinner Watch Widget` | standalone; Digital Crown volume; background audio; Smart Stack and watch-face widget (rectangular, circular, inline, corner) |
| Widget | `Spinner Widget` | small, medium and large on iPhone, iPad, Mac and Vision Pro (visionOS 26); play/pause from the widget; a Control Center play/pause control on iOS 18 and macOS 26 |

All targets use the bundle ID `com.JPEnterprises.Spinner` (the watch app adds `.watchkitapp`).

## Built on

- [`StationKit`](https://github.com/jpurnell/StationKit): station-agnostic core (Now Playing snapshot and publisher, audio session, artwork loading, music links).
- [`StationKitAdapterKEXP`](https://github.com/jpurnell/StationKitAdapterKEXP): KEXP as a `Station`.
- [`KEXPPowerKit`](https://github.com/jpurnell/KEXPPowerKit): the KEXP API client.

## Working on it

Design-first, test-first, with the quality gate at zero errors and zero warnings; see `CLAUDE.md` and `development-guidelines/`. After cloning, run `./scripts/bootstrap.sh` so the commit hooks run (it sets `core.hooksPath` and checks that `swift` and `quality-gate` are installed).

MIT licensed. KEXP and its logo belong to KEXP; the app icon is an abstract wave, not the station's mark.
