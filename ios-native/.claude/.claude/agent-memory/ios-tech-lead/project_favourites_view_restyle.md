---
name: project-favourites-view-restyle
description: SoftFavouritesView 2.4.0 restyle — large title + Edit toggle, three-segment filter, FavStopCard, service section preserved, + Add stop row
metadata:
  type: project
---

Restyled `/Users/rommel/Documents/Leyne/ios-native/Leyne/V2/SoftFavouritesView.swift` as part of the 2.4.0 UI overhaul.

**Key decisions:**
- Replaced `FavFilter` (all/stops/services/busStop) with `FavSegment` (all/pinned/nearby). Old enum was only used internally — no external breakage.
- Single "Edit" button in the title row toggles both `editingStops` and `editingServices` together for a coherent flow (rather than per-section Edit buttons, which are now only present on the services section to allow independent service editing).
- The three-segment control uses a custom pill layout (not `SortChipRow`) to match the spec: green `t.soon` fill for selected, `t.contrastFg` text on selected, `t.dim` on unselected, all inside a `t.surface` rounded container.
- Nearby stops come from `ds.nearby` (same as SoftHomeView) deduped against `m.pins`; walk/distance for pinned stops computed via free functions `walkMinFromLocation`/`distanceMFromLocation` using `DataStore.shared.stopByCode` and `LocationManager.shared`.
- Introduced `FavStop` private value type with a `Source` enum (.pinned(Pin) / .nearby(NearbyStop)) to unify both stop types through a single `FavStopCard`.
- `FavStopCard` is a private struct in the same file — matches `SoftNearbyStopCard` layout exactly (identity block → hairline divider → MiniBusChip row, cornerRadius 18, padding 16) with the gold star badge (`Color(hex: "F5B500")`) for pinned stops.
- Favourite services (`m.favServices`) preserved in full under "Saved services" section header; only visible on the "All" segment (hidden when user picks Pinned or Nearby, since those segments are stop-focused).
- "+ Add stop" row at the bottom wired to `onOpenSearch()`.
- `refreshable` pull-to-refresh preserved, covering pins + favServices + prefetchNearbyArrivals.

**Why:** 2.4.0 design spec requires large title + segmented All/Pinned/Nearby control and SoftNearbyStopCard-matching card style.

**How to apply:** When reviewing Favourites tab changes, expect FavStopCard (private, in-file) as the canonical card — it should stay in sync with SoftNearbyStopCard if that card's layout changes. [[native-rewrite-status]]
