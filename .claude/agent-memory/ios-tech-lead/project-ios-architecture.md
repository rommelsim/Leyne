---
name: project-ios-architecture
description: iOS native rewrite key architectural patterns — navigation, state, DataStore API
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
