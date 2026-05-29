---
name: next-implementation-tasks
description: Recommended next implementation tasks for native iOS and Flutter Android, by priority.
metadata:
  type: project
---

## iOS native — recommended next tasks

### P1: Fix the alight alert wiring in SoftBusView

`SoftBusView.scheduleAlight(stopCode:)` writes directly to raw UserDefaults keys instead of going through `m.setActiveAlight(busNo:stopCode:stopName:fireAt:)`. `AppModel` already has the full implementation including `NotificationsManager.scheduleAlightAlert`. The stub was marked "Phase 3" but Phase 3 is done — the method exists. Fix is ~5 lines: replace the raw UserDefaults writes with `m.setActiveAlight(...)` and compute `fireAt` from `RouteInfo` (stopsToAlight - 2) × 90 s.

### P2: Wire Live Activity CTA in SoftBusView (parity.md Task #12)

The `liveActivityCTA` view is built and commented out at the call site. AppModel has full ActivityKit wiring (`toggleLiveActivity`, `startLiveActivity`, `isLiveActivityActive`). The CTA button action needs to call `m.toggleLiveActivity(service, stopName: ds.stopName(stopCode), stopCode: stopCode)`. Then restore the `liveActivityCTA` call site in `body`. Precondition: verify `liveService()` returns non-nil before enabling the button.

### P3: Live bus coordinate on map in SoftBusView

`DataStore.route()` hard-codes `busCoord: nil`. `DataStore.liveBus(service:stopCode:)` already fetches real GPS coordinates from LTA. After `loadRoute()` resolves, call `liveBus(service: svc, stopCode: stopCode)` and merge the coordinate into the `RouteInfo`. Then restore the bus annotation in the MapKit `Map` view body (it's already stubbed with a comment: "No live bus annotation: r.busCoord is always nil today"). Also add the per-second coordinate refresh to `SoftBusView` (currently only arrival ETA updates; bus position doesn't move on map after initial load).

### P4: kChangelog entries for shipped versions

`AppModel.kChangelog` only has `"2.0.0"`. Users upgrading through 2.1.0 → 2.2.x see nothing. Add entries for at least the current version before the next archive. Update `kChangelog` in `AppModel.swift` and mirror the entry to `CHANGELOG.md` (per [[feedback-changelog]]).

### P5: Verify Inter font bundling

`leyne-2.0-plan.md` specifies Inter 400/500/600/700. Confirm font files are present in the Xcode project and the `Theme.swift` `Font.custom(...)` calls reference the correct PostScript names. If fonts are missing, SwiftUI silently falls back to system sans and the design spec isn't met.

---

## Flutter Android — recommended next tasks (if/when Android is prioritised)

Per `specs/parity.md` priority order:

1. **Detail Mode B (Variant B Smart Hero card)** — port `SoftBusView` layout to Flutter `lib/screens/v2/soft_bus_screen.dart`. This is the biggest visual delta between the two platforms.
2. **5-step onboarding** — Flutter currently has 4 steps; add the notifications priming step (Step 3 in iOS). Partial work is in the current diff (removed Skip + `onDone` callback).
3. **Heartbeat pulse + staggered entrance** — Home card animation pass in `lib/screens/v2/soft_home_screen.dart`.
4. **Route progress vertical stem** — port `RouteTimeline` from iOS to `lib/widgets/route_timeline.dart`.
5. **Primary-bus long-press** — add `primaryBus: String?` field to Flutter `Pin` model + long-press menu in `SoftPinCard`.
6. **Platform-design pass on alight card** — `lib/screens/detail_screen.dart` `_onBusAlertCard` was visually copied from iOS layout; replace with Material switch + card elevation (flagged in `specs/parity.md`).

---

## Housekeeping

- Delete `AddStopSheet.swift` (dead code; `m.showAdd` never flips in SoftRoot). Do via Xcode to get pbxproj cleaned automatically.
- Decide: remove `AppTab` enum from AppModel (superseded by `SoftTab` in SoftRoot) or keep for legacy deep-link compat. Currently not breaking anything but adds confusion.

Related: [[parity-gaps-ios-flutter]], [[architecture-ios-native]]
