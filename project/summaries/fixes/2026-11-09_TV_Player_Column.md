# 2026-11-09 — Spinner TV: reaching the player

**Branch:** `tvos-target` (worktree `KEXPPower-tvos`)

## Problem
Checking the archive on the tvOS simulator with sim-tap: playback, the timeline, Pause, Back 15 and resume all work, but the player bar at the bottom of each section could be reached only past the last row of the list above it. tvOS's focus engine takes the next row before anything beneath the list.

## Changes
- `RootView`: on tvOS the player bar is a 560-point column on the right (`safeAreaInset(edge: .trailing)`), one `focusSection()`, its material reaching the screen's trailing and vertical edges. Other platforms are unchanged.
- `RootView`: `.onPlayPauseCommand` on the tvOS `TabView` calls `playOrPause()`. On the section it missed presses while focus was in the tab bar, where it is at launch.
- `ArchiveView` (all platforms): the day number is one line with `minimumScaleFactor(0.6)`; "30" had wrapped a digit per line, which made the Oct 25–30 tiles taller.

## Verified
- sim-tap on the tvOS 27.2 simulator: Right from the fifth show of Nov 7 focused "Position in the show"; Down, Right reached Back 15 and Pause; Left returned to the list. Play/Pause from a list row paused and resumed an archive show; from the tab bar at launch it started live, and the live bar appeared in the column. Day tiles are one height.
- Builds: Spinner TV, iOS (for testing), Spinner Mac (for testing), Spinner Watch. App unit tests on an iPhone simulator: 375 tests in 43 suites passed.
- The Mac test run could not start its runners ("System authentication is running"), an environment problem. The `Spinner Widget` scheme built alone fails with an embedding error on the base commit as well; the widget builds inside the iOS app.

## Not done
- Review with entries (needs a signed-in Apple Music account; real Apple TV).
- The Oct 30 "no longer available" show was a station outage, not a bug.

## Revised the same day: Now Playing tab
The owner tried the column in DeviceHub and found it messy (a mostly empty third of the screen, a cramped Host grid, a confusing Right from Live). Replaced with a Now Playing tab on tvOS; sections have no bar there. Also fixed the archive playlist sheet (collapsed to its title on tvOS), its wrapped time column, and the Host/Show/Genre cards (520-point columns on tvOS, even heights). `AppSection` gained `nowPlaying` and `visible(…, showsNowPlaying:)`, test first; `PlayerBarKind` gained a test for it. 377 app tests pass.
