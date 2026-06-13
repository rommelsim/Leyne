---
name: mrt-restructure
description: MRT tab restructured 2026-06-13: ••• menu, saved stations, compact lines list, SoftMrtLineView, SoftMrtNewsView, FavSegment MRT
metadata:
  type: project
---

MRT tab restructured 2026-06-13 (no version bump, iOS-only).

**Why:** Information overload — inline expanding crowd lists made the main scroll very long; lifted maintenance and crowd detail into dedicated pushed views.

**How to apply:** When touching MRT screens, understand the new split:
- `SoftMrtView` = navigation hub (title + ••• menu, disruption banner, saved stations, closest 3, compact lines list)
- `SoftMrtLineView` = per-line crowd detail (pushed from compact line row)
- `SoftMrtNewsView` = advisories + lift maintenance (pushed from ••• → "News & advisories")
- `SoftMrtStationView` = station detail (unchanged logic, added save star in top bar)

**Key changes:**
- `MrtGeoStation`: `Decodable` → `Codable` (required for UserDefaults persistence)
- `AppModel`: `savedMrtStations: [MrtGeoStation]` @Published, `loadSavedMrt`/`persistSavedMrt`/`isMrtSaved`/`toggleMrtSaved`/`removeMrtSaved` — mirrors favServices pattern; UserDefaults key `leyne.savedMrt`
- `SoftMrtRoute`: added `.line(MRTLine)` and `.news` cases
- `FavSegment`: added `.mrt` case; `SoftFavouritesView` now takes `onOpenMrtStation: (MrtGeoStation) -> Void`; tapping a saved station switches tab to MRT and pushes `.station(...)` onto mrtStack
- `SoftMrtView`: map button replaced by `Menu` (ellipsis.circle.fill); nearest list capped at 3; lift maintenance card removed; inline expand removed; compact line rows push `SoftMrtLineView`
- New files: `SoftMrtLineView.swift`, `SoftMrtNewsView.swift`
