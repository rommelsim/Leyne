---
name: project-ios-architecture
description: iOS native rewrite — navigation, DataStore, font/theme system, V2 view structure, radius/touch-target patterns
metadata:
  type: project
---

Key patterns observed in ios-native/Leyne/ (as of 2026-06-03):

**Navigation:** `SoftRoute` enum (`Hashable`) drives a `NavigationStack` path per tab in `SoftRoot.swift`. Tabs: `.home`, `.settings`, `.search` (role: .search). Route cases: `.stop(String)`, `.bus(stopCode:svc:fullRoute:)`, `.search`. No router object — paths are `@State [SoftRoute]` on `SoftRoot`.

**DataStore:** `@MainActor final class DataStore: ObservableObject` at `ios-native/Leyne/DataStore.swift`. Key async methods: `loadRoutes()`, `route(service:stopCode:)`, `serviceRoute(service:stopCode:)` (added 2026-06-03), `originStop(ofService:)`. Route data is lazy-loaded and disk-cached via `LTAService`.

**New multi-direction model (added 2026-06-03):**
- `RouteDirection`: direction int, stops, youIndex, anchorPresent, originName/destinationName
- `ServiceRoute`: serviceNo, directions, initialIndex
- `serviceRoute(service:stopCode:)` — returns ServiceRoute? with all LTA directions; initialIndex = direction containing the anchor stop

**SoftBusView state:** holds `serviceRouteData: ServiceRoute?` + `selectedDirIndex: Int`. `currentDirection` and `route` are computed properties. `fullRoute: Bool = false` param — when true shows whole timeline (no journey window). Direction toggle via `.segmented` Picker shown only when 2+ directions.

**SoftSearchView:** `onOpenBus: ((String, String) -> Void)?` optional callback — service row taps resolve origin stop and call `onOpenBus(stopCode, svcNo)` if wired, else fall back to `onOpenStop`.

**Why:** Mirrors Flutter data layer `serviceRoute()` + Android bus screen direction toggle. `fullRoute: true` mirrors Android's `fullRoute` on `SoftBusScreen`.

**How to apply:** When reviewing SoftBusView or adding bus-route features, remember route is a computed view over `serviceRouteData`/`selectedDirIndex`, not a stored `RouteInfo`. Hero ETA and map are always anchored to the original `stopCode` (live arrivals don't change with direction switch).

---

## Theme & font system (updated 2026-06-10)

`Theme.swift` defines `t.sans(size:weight:)` and `t.mono(size:weight:)` — both pipe through `UIFontMetrics.default.scaledValue(for:)` so all Text elements scale with Dynamic Type. **Rule:** Text elements must use `t.sans()` or `t.mono()`. Using `.font(.system(size:))` on a `Text()` element bypasses Dynamic Type — this is a recurring issue in the codebase (see HIG audit findings).

`.font(.system(size:))` on `Image(systemName:)` is fine — SF Symbol icons scale by their own weight and don't need UIFontMetrics treatment.

## Corner radius scale in V2 (2026-06-10 audit)

Observed values (V2 folder only): 2, 4, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 22.  
No shared constants file — all hardcoded inline. The de facto scale:
- **Micro** (icon decorators, MRT bar): 2–4
- **Small** (icon tiles, inner chips): 9–12
- **Medium** (rows, sheets, small cards): 14–16
- **Large** (main content cards): 18
- **Hero/modal** (empty-state cards, onboarding): 22
- Off-scale orphans: 13 (NotifyWhenSheet lead rows), 15 (Search field)

`RoundedRectangle(..., style: .continuous)` is used consistently in V2 — good.
Legacy root-level views (DetailView, AddStopSheet, HomeView) omit `style: .continuous` — a gap to address when those views are rewritten.

## Live Activity: automatic tracking (2026-06-10)

The Live Activity is now **automatic** — no per-alert toggle. `AppModel.autoTrackSoonestAlert()` runs every 5 s from `onTick()`. It scans all arrival alerts, finds the one with the smallest ETA > 0, and hands off the single Live Activity to it via `startLiveActivity`. Key contracts:
- If the currently-tracked bus is at ETA ≤ 0 (mid-finale), the method returns early — the polling loop's `finishLiveActivityAsArrived` owns teardown.
- If no alert has ETA > 0, the method returns without stopping — feed gaps don't kill the live view. Teardown is owned by miss-counter / arrival-finale / `removeAlert`.
- `removeAlert` stops the Live Activity only when the removed alert was the one being tracked; `autoTrackSoonestAlert` re-points it on the next tick if another exists.
- `setNotificationsEnabled(false)` calls `stopLiveActivity()` immediately.
- The tick also has a guard: `if !notificationsEnabled, liveActivity != nil { stopLiveActivity() }`.
- `toggleLiveActivity` was removed. `startLiveActivity` and `stopLiveActivity` remain as private/internal methods. `DetailView.swift` (legacy V1, not wired to V2 navigation) was updated to call them inline.

`NotifyWhenSheet.onDone` signature is now `(Int) -> Void` — no Bool for Live Activity preference. Delivery section removed; `lockScreenNote` is a quiet informational `HStack` (lock SF Symbol + `t.faint` text) placed below `notificationPreviewWide` in `arrivalHero`.

`StopAlertSheet` delivery section removed; `commit()` no longer calls `startLiveActivity`.

## Touch targets (2026-06-10 audit)

HIG minimum is 44×44pt. Violations in V2:
- `SoftBusView` top-bar bell/bus/ellipsis buttons: 40×40 (SoftBusView.swift:264,280,322)
- `SoftHomeView` alert bell button: 42×42 (SoftHomeView.swift:131)
- Multiple icon tiles (32–38pt) used as decorative, not interactive — acceptable
- `SoftSearchView` xmark button inside fieldRow: no explicit frame — inherits content size; likely under 44pt hit area
- Various sheet icon chips (34–36pt) are display-only, but confirm non-interactive

**How to apply:** When adding new interactive controls, enforce `frame(width: 44, height: 44)` minimum. Deviations in the bus view top bar (40pt) are the most user-visible gap.
