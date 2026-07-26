---
name: project-stop-view-restyle
description: SoftStopView 2.4.0 restyle — new top bar, title block, section header, card-per-service design; what was changed vs preserved
metadata:
  type: project
---

SoftStopView was fully restyled in 2.4.0 to match SoftNearbyStopCard's visual language. Key changes:

- Top bar: 44×44 circular buttons (back, star toggle, ellipsis/sort menu) replacing the old inline header with embedded back+title+distance chip. Sort control moved from `SortChipRow` into the ellipsis `Menu`.
- Title block: large bold stop name (t.sans(31,.bold)), mono code·road subtitle, walk+distance row in t.soon green, freshness label right-aligned — all left-aligned below the bar.
- Section header: "Buses arriving" (t.dim) + "● LIVE" dot in t.soon (only when feed == .live).
- Bus cards: t.surface rounded-rect (cornerRadius 16), ServiceBadge(.md) with serviceBadgeColors(), destination + followingText (2nd/3rd arrivals in t.mono(12) t.dim), Capsule ETA pill (t.soonBg/t.soon for live+soon, t.surfaceHi/t.fg otherwise), "~" prefix for ghost arrivals only.
- `OccupancyLabel` removed from cards (not in target design) — it was in the old cards.
- `highlight` (lead card border) pattern from old code dropped — target has uniform cards.
- walkDistanceInfo now derives walkMin from haversine distance (~80 m/min) rather than reading a NearbyStop.walkMin field (which isn't available here).
- All existing behaviour preserved: onBack, onOpenBus, SaveSheet (pin flow), hint toast, refreshable, .onAppear ensureArrivals, all three sort modes, arrivalA11y, footer, emptyArrivals.

**Why:** 2.4.0 UI overhaul aligning Stop detail with the SoftNearbyStopCard canonical card pattern.
**How to apply:** When reviewing future Stop view changes, expect this layout. The old `updatedRow` / `header` / `sortControl`+`pinButton` pattern is gone.
