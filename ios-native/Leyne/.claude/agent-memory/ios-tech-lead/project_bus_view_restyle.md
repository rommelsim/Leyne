---
name: project-bus-view-restyle
description: SoftBusView 2.4.0 restyle — what changed, what was preserved, target design mapping
metadata:
  type: project
---

SoftBusView was restyled to the 2.4.0 target design in one file edit (presentation only).

**What changed (UI only):**
- `floatingTopControls`: removed route badge capsule; back + recenter circles moved to outer edges; save button changed from `mappin` to `star`/`star.fill` (gold when saved); extracted `mapCircleButton()` helper.
- `sheetHeader` (peek): replaced Eyebrow + "Towards …" + ConfidenceStatusPill with a two-line title block — "Bus {svc}" at `t.sans(31,.bold)` + "Towards {dest}" at `t.sans(15)` dim + inline green dot + "LIVE" `t.mono(10,.bold)` in `t.soon` when `pillConfidence == .live`.
- `sheetBody`: replaced `heroETA` + divider with `approachingCard` + divider + `alertsSection` + `routeSection` + `nextBusesCard`.
- New `approachingCard`: green-bordered `t.surface` card with `bus.fill` tile in `t.soonBg`, "Approaching"/"Arriving now" in `t.soon`, stops-away line, hero ETA numeral `t.mono(36,.bold)`, progress capsule (Capsule in GeometryReader), stop code + distance + CrowdMeter footer. Shown only when `liveService() != nil && (plot != nil || confidence != .none)`.
- New `nextBusesCard`: "Next buses from this stop" header, up to 3 ETA columns separated by hairline, freshness line with `dot.radiowaves.up.forward` icon + `feedFreshnessLabel`.
- `routeSection`: added "Route progress" `t.sans(15,.semibold)` `t.dim` section header before RouteProgressBar.
- `DraggableSheet` peek height bumped from 322 → 340 to accommodate the taller title block.

**What was preserved (zero behavior changes):**
- Full-bleed Map + DraggableSheet architecture unchanged.
- All data flow: `liveService()`, `confidence`, `pillConfidence`, `showWhisper`, `feed`, `stopsRemaining`, `estimatedBusIndex`, `progressNodes`, `timelineStops`, `nextTwoLabel`, `stopDistanceSuffix`.
- All live tracking: `recomputePlot()`, `ticker`, `setTarget()`, `plot`, `displayCoord`, `lastFix`, `estimatedCoord()`.
- All navigation: `onBack`, `alightId` → `scheduleAlight()`.
- All alerts: `notifyButton`, `liveActivityCTA` — unchanged.
- RouteTimeline and RouteProgressBar — reused exactly as-is, not touched.
- Map markers: MapStopMarker, MapUserMarker, MapBusMarker, MapLegendItem — unchanged.
- DraggableSheet struct — unchanged.
- SaveSheet trigger and `applyServiceSave()` — unchanged.

**Target elements NOT implemented (missing backing data):**
- Share button (`square.and.arrow.up`): no share action exists in the view — correctly omitted.
- "0.6 km away" distance in approaching card: `stopDistanceSuffix` gives stop→user distance, not bus→stop. Bus position is estimated/plotted but no bus-to-stop distance is computed. Distance line shows stops-remaining instead.
- `fmtClock` per-stop times in RouteTimeline are computed by `etaClock()` — already wired, displayed by the existing RouteTimeline component unchanged.

**Build:** Verified `** BUILD SUCCEEDED **` on iOS Simulator (Xcode 16, iOS 26.5 SDK) after restyle.
