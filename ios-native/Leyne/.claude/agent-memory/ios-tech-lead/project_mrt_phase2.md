---
name: project-mrt-phase2
description: MRT tab Phase 2 architecture — nearest stations, station detail, map viewer, search integration; SoftMrtRoute nav enum; MrtGeoStation Hashable
metadata:
  type: project
---

MRT tab restructured in Phase 2 (2026-06-13):

- `SoftMrtView` now has a NavigationStack (via `mrtNavStack` in SoftRoot). Layout: title "MRT / Stations near you" → system map button → "Closest to you" nearest station cards (using `MrtGeo.nearestStations`) → "All lines" section (preserves full line-status board).
- `SoftMrtStationView` — new station detail pushed from nearest cards. Shows crowd per line for that station (matched by station code in `ds.crowdByLine[line]`), disruption alerts, lift maintenance. `onBack` closure-based because toolbar is hidden.
- `MrtMapView` — sheet (not push) from system map button. UIScrollView-backed `ZoomableImageView` with pinch + double-tap-to-zoom. Loads from `Assets.xcassets/MRTSystemMap.imageset` (empty placeholder — user must drop in PNG). Falls back to "Open LTA system map" button linking to `https://www.lta.gov.sg/content/ltagov/en/map/train.html`.
- `SoftMrtRoute: Hashable` enum with `.station(MrtGeoStation, distanceM: Int?, walkMin: Int?)` — defined in SoftRoot.swift alongside SoftRoute.
- `MrtGeoStation` — added `Hashable` conformance (was only `Equatable`) in `MrtGeo.swift` to satisfy SoftMrtRoute's Hashable requirement.
- `SoftSearchView` — added `onOpenMrtStation: ((MrtGeoStation) -> Void)?` optional callback. Results section now includes "MRT stations" section using `MrtGeo.stations(matching:)`. Tapping calls `onOpenMrtStation`.
- `SoftRoot.navigateToStation(_:)` — tab-switch helper that sets `tab = .mrt` and `mrtStack = [.station(...)]`. Called from Search tab and legacy .search route.

**Why:** Phase 2 spec required Bus-sibling UX for MRT (nearest-first, tappable cards → detail) to complement the Phase 1 line-status board.

**How to apply:** When adding navigation into the MRT tab, use `SoftMrtRoute`. The MRT tab now has its own `mrtStack: [SoftMrtRoute]` in SoftRoot (not bundled with homeStack). Do not push SoftMrtStationView from Bus/Home stacks — go through `navigateToStation`.
