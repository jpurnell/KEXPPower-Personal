# Design Proposal: Spinner TV Top Shelf

**Status:** Approved by the owner 2026-11-09 (layout chosen: a row of covers)
**Branch:** `tvos-target`

### 1. Objective
When Spinner is in the Apple TV Home screen's top row, show what KEXP is playing: the song on the air and the last several, as album covers. Select opens Spinner; Play starts the live stream.

### 2. Proposed Architecture
- **A Top Shelf extension**, `Spinner TV Top Shelf` (`com.apple.tv-top-shelf`, tvOS 17), embedded in Spinner TV. Its `ContentProvider` (a `TVTopShelfContentProvider`) fetches from `KEXPStation` itself (`nowPlaying`, `recentTracks`, `currentProgram`), so the shelf is current when the app is not running, as the widget is.
- **`TopShelfRow`** (pure, in the app's sources, tested on iOS): turns the station's answers into a titled row of tiles. The song on the air first, then recent songs without repeats, at most ten; each tile is the song and artist with the artwork (KEXP's logo when there is none). The title is "Now on KEXP", with the show and host when known.
- **`SpinnerLink`** (pure, tested): the `spinner://` links the shelf's actions open, `open` and `live/play`, and parsing them back. The TV app registers the scheme and, on `live/play`, plays the live stream (leaving the archive if one is playing).
- **Sectioned content, square images** (`TVTopShelfSectionedContent`, `.square`), because KEXP's art is square and small; the carousel's 16:9 images would blur it (owner's choice).
- **Refresh:** the app's `WidgetPublisher` already reloads on a new song or show; on tvOS that reload also calls `TVTopShelfContentProvider.topShelfContentDidChange()`.

### 3. Error Handling
Each station call fails on its own: no song on the air still gives the recent row; no show gives the plain title. Nothing at all returns `nil`, and tvOS shows the static Top Shelf image.

### 4. Testing Strategy
Unit tests for `TopShelfRow` (order, repeats, the limit, airbreaks, titles, artwork fallback) and `SpinnerLink` (round trip, foreign URLs refused). The extension itself is checked on the tvOS simulator's Home screen.

### 5. Open Questions
None.

### 6. As built (2026-11-09)
- `Spinner TV Top Shelf` target (app extension, `com.JPEnterprises.Spinner.topshelf`), embedded in Spinner TV, linking StationKit and StationKitAdapterKEXP; `TopShelfContent.swift` is compiled into the iOS app (for its tests), Spinner TV and the extension.
- `loadTopShelfContent()` is `nonisolated(nonsending)`: as a default (`@concurrent`) async override, Swift 6 refused to return the non-`Sendable` `TVTopShelfContent` to the superclass's caller. Matching the superclass's isolation fixes it without `@preconcurrency`.
- The TV app registers `spinner` in `CFBundleURLTypes`; `RootView` handles `spinner://live/play` on tvOS. `WidgetPublisher.reloadWidgets()` calls `TVTopShelfContentProvider.topShelfContentDidChange()` on tvOS, where WidgetKit does not exist.
- Checked on the tvOS 27.2 simulator: "Now on KEXP · The Morning Show with Lisa LeClair" over the covers; a focused cover titled "Little Thing Gone Wild · Black Rebel Motorcycle Club"; Play opened Spinner on Live, playing. Not checked: a refresh while the Home screen is showing (needs the song to change while watching).
