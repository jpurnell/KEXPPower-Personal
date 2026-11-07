# ADR-009: The archive is built on StationKit and the adapter, and grouped on the device

**Date:** 2026-11-07
**Category:** architecture
**Status:** Accepted

## Decision
The archive is a station-agnostic layer in StationKit (`ArchiveShow`, `ArchivePlayback`, `ArchiveCatalog`,
`ArchiveIndex`) with KEXP's side in `StationKitAdapterKEXP` (`KEXPArchiveCatalog`). The app does not use
`KEXPPowerKit`'s `ArchiveManager`, and its async conversion is not finished.

Browsing by host, show and genre is done on the device: the app fetches the last fifteen days of shows by time and
`ArchiveIndex` groups them. Genres are whatever the shows carry, so they are not an enum.

## Context
The master plan's route to archive playback was to finish `ArchiveManager`'s async conversion (an iOS 27.2 follow-up).
Doing that would have tied the archive to one station's client, left the Mac, CarPlay and any other station to repeat
it, and put the archive in a library the app only partly uses. The route taken, with the owner's agreement at each
step on 2026-11-06 (StationKit 0.9.0 released, then "let's get the adapter done"), was to build the types in
StationKit and the adapter instead.

KEXP's `/v2/shows` filters by time only; there is no host, program or genre filter (checked against the live API on
2026-11-05), and a show's genres are a comma-separated string on its program. Grouping on the device is therefore the
only way to offer the website's Host, Show and Genre filters, and a fifteen-day span is a few hundred shows.

## Consequences
- Any station that can list shows by time and give an audio file for a moment can offer an archive by conforming to
  `ArchiveCatalog`; a station without one does not conform.
- Counts shown for a host or show are for the days loaded (about two weeks, which is also as far back as KEXP keeps
  audio), not a career total.
- KEXP's archive can be wrong (its power outage on 2026-10-30, a truncated file on 2026-11-02). The adapter refuses a
  file that does not belong to the show (0.7.0); the app says how much of a recording exists. Neither tries to repair
  KEXP's data.
- `ArchiveManager` stays in `KEXPPowerKit`, used by nothing here.
