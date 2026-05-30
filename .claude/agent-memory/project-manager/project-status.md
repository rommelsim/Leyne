---
name: project-status
description: "Leyne current project status — committed state, open gaps, and critical path. Snapshot as of 2026-05-30 (post d3980e2)."
metadata:
  type: project
---

## Overall health: At Risk (Android) / On Track (iOS) — 6-agent Android audit 2026-05-30 found 2 launch blockers

## Android quality remediation
Six agents audited Flutter V2 (`lib/screens/v2/`) on 2026-05-30. 36 findings across 5 categories. Full roadmap in [[android-quality-roadmap]].

**Sprint 0 (must do before next AAB):** 8 items — search chip wiring (L), alight alert wiring (M), ETA fabrication fix (S), CI/infra fixes (4×S, 1×S CHANGELOG).
**Sprint 1 (reliability):** 10 items — all S/M, mostly one-file wiring fixes.
**Sprint 2 (parity/feel):** 10 items — font scaling (L), haptics (M), provenance chips (M), 7×S.
**Sprint 3 (polish/a11y):** 6 items — Semantics pass (L), widget replacements (M), 4×S/M.
**Post-launch native:** Android foreground service (XL) + home-screen Glance widget (XL).

## Platform versions in play

| Platform | Version | State |
|---|---|---|
| iOS native (`ios-native/`) | 2.3.0+13 | Build ready. Rejection fixes committed (d3980e2). Pending Archive + App Store upload. |
| Android/Flutter (`lib/`) | 2.3.0+22 | Rejection fixes committed. Pending AAB upload to Play. |

## What is DONE (committed, as of d3980e2)

- Full V2 "Soft" palette + six screens on both platforms; V2 is the default/only path (no flag gate)
- iOS V2 screen layer: `ios-native/Leyne/V2/` — 9 primitives + 6 screens wired to real DataStore
- Flutter V2 screen layer: `lib/screens/v2/` — matching 6 screens
- Notifications system: arrival + alight alerts, exact scheduling, deep-link tap-to-open (both platforms)
- iOS: Live Activities (ActivityKit), WidgetKit, edge-swipe-back, spring push animation
- Android: ongoing live-tracking notification (foreground-only); stop alert controls (per-bus bells + master bell)
- Pull-to-refresh on iOS V2 (Home/Stop/Bus) via `DataStore.refreshArrivals`
- Onboarding v2 (both): no-skip, 5-step with location + notification + ATT priming
- iOS CI job added: `ios-native/` xcodebuild on every push (commit 24ddf78)
- Flutter test suite: 91 tests passing; analyze clean
- App Store rejection fixes (d3980e2): all "beta" labels stripped, alight alert real (not stub), search chips real (iOS), version bumped 2.3.0
- CHANGELOG.md: "Unreleased 2.3.0" block written; not yet moved to a released block (pending Archive/AAB cut)

## Open correctness issues (pre-ship)

### P1 — blocks honest store release
- **Android search chips decorative**: `soft_search_screen.dart` line 104 routes all four filter chips through `searchStops(q)` only — postal geocode, Bus#, and Stop ID chips ignore `_filter`. iOS fixed in 2.3.0; Android has the identical gap. Risk: Guideline 2.2 exposure if Apple audits Android (not immediate, but technical debt).
- **`kChangelog` frozen at "2.0.0"** (`AppModel.swift` line 64): no entries for 2.1.0, 2.2.x, 2.3.0 → What's New screen silently skips on every upgrade. Users miss the changelog entirely.

### P2 — quality/polish, not blocking ship
- `SoftBusView.scheduleAlight` writes raw UserDefaults instead of calling `m.setActiveAlight(...)` (stale stub, ~5 lines)
- `kChangelog` missing 2.1.0/2.2.x/2.3.0 entries (see P1 above — arguable upgrade to P1)
- Live bus map marker never shows: `DataStore.route()` hard-codes `busCoord: nil`
- Dynamic Type: `Theme.swift` `sans`/`mono` use `.system(size:)` with no `relativeTo:` — whole app ignores accessibility text scaling
- iOS `SoftToggle` should be native SwiftUI `Toggle` (a11y, system tint)
- Dead V1 iOS files (`HomeView.swift`, `SettingsView.swift`) unreferenced — delete via Xcode to drop V1 path

### P3 — deferred, not blocking
- Android pull-to-refresh not yet wired (GAP 6/9/15) — `DataStore.refreshArrivals` exists; just needs `RefreshIndicator` wrappers
- GAP 14: Flutter route timeline invents per-stop ETA minutes (`etaMin` fabrication)
- GAP 1: Flutter onboarding missing footnote hints on steps 4–5
- GAP 8: Flutter stop detail hero-card-first layout vs iOS flat sorted list
- Android true background tracking via foreground service (current: foreground-only)
- No analytics/ATT funnel (post-launch blind spot)

## Critical path to ship

1. CHANGELOG.md: move "Unreleased 2.3.0" → versioned block, update `kChangelog` in AppModel.swift
2. iOS: Archive 2.3.0+13 → TestFlight → App Store resubmit (check `forceTestUnitForRelease = false`)
3. Android: `scripts/build-android-prod.sh` → AAB upload to Play (verify `SCHEDULE_EXACT_ALARM`)
4. Monitor App Store + Play review outcomes

**Why:** Working tree is clean; builds are code-complete. The only gate is the human archive/upload step.
**How to apply:** Start every session with git status. Next immediate action is cutting the builds.

Related: [[project-risks]], [[next-actions]]
