---
name: softbusview-audit
description: P0–P2 design/UX findings for SoftBusView (ios-native/Leyne/V2/SoftBusView.swift) — bus arrival detail screen — audited 2026-05-30
metadata:
  type: project
---

SoftBusView is the V2 (Soft/Liquid Glass) bus arrival detail screen. Key findings from 2026-05-30 audit:

**Why:** Screen has a critical font-size bug causing "Arr" to clip, a map vs. caption contradiction, and two notification affordances with no clear differentiation.

**How to apply:** When working on SoftBusView or related ETA display, reference these issues before implementing changes.

## P0 Issues
- `SoftBusView.swift:144–151`: `t.mono(56)` is unconditional — "Arr" clips at any accessibility text size. Fix: `t.mono(eta?.big == "Arr" ? 36 : 56).minimumScaleFactor(0.6).lineLimit(1)`. DetailView.swift:440 already does this correctly (44 vs 64).
- `SoftBusView.swift:141–176`: "ARRIVING IN" eyebrow + "Arr now" ETA is grammatically broken when bus is arriving. Fix: swap eyebrow to "Arriving now" when `eta?.live == true` and suppress the big "Arr" text.
- `SoftBusView.swift:318–359`: Map shows a bus-icon `MapStopMarker` on the stop coordinate, but caption says "live position isn't shared yet." Bus icon on the stop pin implies it is the live bus. Fix: change `MapStopMarker` to use `mappin.fill` and update legend to `mappin.fill` icon for "STOP".

## P1 Issues
- `SoftBusView.swift:163`: "FOLLOWING" eyebrow is jargon. Fix: rename to "THEN" — mirrors DetailView ServiceTapRow copy.
- `SoftBusView.swift:219–308`: `notifyButton` and `liveActivityCTA` are stacked with no visual separation or differentiation. Both answer "tell me when the bus comes." Fix: add `DSection`-style eyebrow headers ("ALERTS", "LOCK SCREEN") OR merge into a single tracking card with Live Activity as primary and notification as secondary.
- `SoftBusView.swift:79–80`: Pin button labels "Pinned" (state) not "Unpin" (action) when active. Fix: `isPinned ? "Unpin" : "Pin stop"`.
- `topActionRow` is inside ScrollView; scrolls away. Fix: lift out to ZStack sibling like DetailView.swift does (topBar pattern).

## P2 Issues
- `notifyButton` a11y label says "Tap to cancel" — VoiceOver instruction anti-pattern. Fix: "Arrival alert enabled for bus X".
- ETA numeral uses `.monospaced` design for countdown numbers. Consider `t.sans` for numeric ETAs; keep mono for "Arr" and bus number codes.

## What's correct
- `liveStatusChip` has correct a11y label and honest monitored/scheduled duality.
- `liveActivityCTA` is correctly suppressed when `areActivitiesEnabled` is false.
- `glassSurface()` fallback chain (iOS 26 material → opaque surface) is clean.
- `arrivalCard` uses `t.surface` (#FFFFFF) not glassSurface — keeps Live GPS chip contrast ratio ~5.4:1 above AA.

[[next-fixes]]
