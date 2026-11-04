# Spinner

A fast, native Apple-platform listener for KEXP 90.3 FM (Seattle): the live playlist, the live stream, and (eventually) one-tap saving to a dedicated Apple Music playlist. It is meant to be quicker and friendlier than the station's own app, and to be built from parts other public-radio stations can reuse.

**Status: 3.2.0, private.** It plays the live stream and shows the playlist and show on iPhone, iPad, Mac, Apple Vision Pro and Apple Watch. Add to Apple Music playlist works on iPhone, iPad and Vision Pro (MusicKit cannot write playlists on the Mac). Not built yet: the archive, CarPlay, a watch widget, and Siri and Shortcuts intents. See `project/master_plan.md` and `project/plans/upcoming/PlatformExperience.md`.

| Platform | Target | Notes |
|---|---|---|
| iOS / iPadOS 17 | `KEXPPowerExampleSwiftUI (iOS)` | lock-screen Now Playing, background audio; embeds the watch app |
| macOS 14 | `Spinner Mac` | own target and entitlements; plays the stream; Playback menu (Space) |
| visionOS 1 | shares the iOS target | |
| watchOS 10 | `Spinner Watch` | standalone; Digital Crown volume; background audio |
| Widget | `Spinner Widget` | small, medium and large on iPhone, iPad, Mac and Vision Pro (visionOS 26); play/pause from the widget |

All targets use the bundle ID `com.JPEnterprises.Spinner` (the watch app adds `.watchkitapp`).

## Built on

- [`StationKit`](https://github.com/jpurnell/StationKit): station-agnostic core (Now Playing snapshot and publisher, audio session, artwork loading, music links).
- [`StationKitAdapterKEXP`](https://github.com/jpurnell/StationKitAdapterKEXP): KEXP as a `Station`.
- [`KEXPPowerKit`](https://github.com/jpurnell/KEXPPowerKit): the KEXP API client.

## Working on it

Design-first, test-first, with the quality gate at zero errors and zero warnings; see `CLAUDE.md` and `development-guidelines/`. After cloning, run `git config core.hooksPath .githooks` so the commit hooks run (`CLAUDE.md` mentions a `scripts/bootstrap.sh` that does not exist yet).

MIT licensed. KEXP and its logo belong to KEXP; the app icon is an abstract wave, not the station's mark.
