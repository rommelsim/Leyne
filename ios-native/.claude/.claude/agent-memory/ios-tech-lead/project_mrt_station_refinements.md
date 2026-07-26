---
name: mrt-station-refinements
description: MRT nearby-card compaction, station-detail back button, and station-detail redesign (2.7.0, 2026-06-13)
metadata:
  type: project
---

Three refinements to the MRT views shipped in 2.7.0 on 2026-06-13.

**FIX 1 — Nearby-station card matches SoftNearbyStopCard exactly**
- `nearbyStationCard` in `SoftMrtView.swift` reworked: tile 42×42 r12, name sans(17 semibold), VStack spacing 2 (not 4), pills row uses `Spacer(minLength: 0)` to fill, meta line uses `t.mono(12.5)` and `t.soon` colour for walk (matching compactMeta), `t.dim` for distance. Pill padding reduced to h:6 v:2.
- Outer card: padding 14, cornerRadius 18, t.surface bg, t.line 1pt stroke — identical to SoftNearbyStopCard.

**FIX 2 — Back button + swipe now match SoftStopView**
- `SoftMrtStationView` had a text-label chevron back (non-standard). Replaced with `circleButton(icon:)` — 44×44 Circle, t.surface fill, t.line 1pt stroke overlay, chevron.left at system(16 semibold) — identical to SoftStopView's `circleButton`.
- `enableSwipeBack()` was already present; left in place.
- Top bar structure: HStack { circleButton + Spacer } with .padding(.top, 4) — matches SoftStopView's topBar.

**FIX 3 — Station-detail redesign**
- Hero header: 4pt coloured rule (first line's colour, w:36), station name sans(31 bold), prominent pills (mono 12 bold, h:10 v:5), walk/distance meta (t.mono 12.5, t.soon + t.dim).
- Crowd section: eyebrow "CROWD NOW", one card per line: line badge (36×36 r10) + line name + crowd indicator (dot + label + sublabel). Loading/unavailable/unknown states all handled gracefully.
- Alerts: eyebrow + per-alert card (t.surface r14) with coloured MRTLineBar, title, detail, free-service chips.
- Lifts: eyebrow + grouped card with hairline dividers between items. Section omitted entirely when empty.
- Empty state card: checkmark.circle.fill + "All clear" + "No live updates" — shown only when relevantLines is also empty.
- All sections use `eyebrow(_:)` helper (mono 10 semibold, tracking 1.5) matching SoftMrtView's sectionHeader.

**Why:** MRT tab felt visually inconsistent with Bus/Stop tabs — bulkier cards, non-native back button, sparse station detail.

**How to apply:** When touching MRT views, reference SoftNearbyStopCard in SoftHomeView.swift (line ~412) as the canonical nearby-card template. Back button is always circleButton + enableSwipeBack. [[mrt-phase2-architecture]]
