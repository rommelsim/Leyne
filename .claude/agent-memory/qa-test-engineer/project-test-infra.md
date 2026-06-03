---
name: project-test-infra
description: Test framework, runner commands, file locations, naming conventions for Leyne (Flutter + iOS native)
metadata:
  type: project
---

**Flutter (Android + iOS via Flutter)**
- Test runner: `flutter test --no-pub` from repo root
- Test files: `test/` directory, named `*_test.dart`
- Framework: `flutter_test` + `shared_preferences` mock (SharedPreferences.setMockInitialValues)
- Files: `app_model_test.dart`, `confidence_test.dart`, `data_layer_test.dart`, `data_store_arrivals_test.dart`, `data_store_coldstart_test.dart`, `eta_pill_test.dart`, `onboarding_test.dart`, `ongoing_tracking_test.dart`, `pinned_card_test.dart`, `screens_test.dart`, `settings_features_test.dart`, `widget_test.dart`
- Total tests as of 2026-06-03: **91 + 36 new = ~127 pass** (confidence_test: 21, data_store_arrivals_test: 8, data_store_coldstart_test: 7 added this session)
- Fake pattern for DataStore tests: extend `LtaService` with `super(client: _NullHttpClient())`, override `busStops/busServices/busArrival` — no mockito needed. Use a `Completer<void>` gate in `busStops/busServices` to control bootstrap timing in cold-start tests. See `test/data_store_arrivals_test.dart` and `test/data_store_coldstart_test.dart`.

**iOS Native (SwiftUI)**
- Test target: `ios-native/LeyneTests/`
- Files: `LeyneCoreTests.swift` (unit + pin logic), `LiveLTATests.swift` (integration, skips without network)
- Run via Xcode or `xcodebuild test`
- No snapshot or UI tests exist; no tests for DataStore, Feedback, or V2 views
- LeyneCoreTests covers: ETA rounding, query detection, haversine, LTA date parsing, load/deck mapping, JSON parsing (arrivals/stops/routes), journey segment trimming, pin Codable round-trip, pin toggle symmetry, tracked toggle + persistence, widget pin mirror, pin/home/detail surface flows, reorder, recents

**Critical gaps as of 2026-05-30 audit (d3980e2 base):**
- `SoftBusScreen._alightId` — purely local state (setState). Tapping a stop in RouteTimeline stores the stop id in `_SoftBusScreenState._alightId` but NEVER calls `AppModel.setActiveAlight()`. No notification is scheduled. No persistence. No auto-cancel. Android alight-alert feature is visually present but functionally dead. iOS uses `detail_screen.dart`'s `_onAlightChanged` which correctly schedules via `AppModel.setActiveAlight`. P0 bug.
- `SoftSearchScreen._results()` ignores `_filter` entirely — always calls `DataStore.searchStops(q)` regardless of which chip (Postal / Bus # / Place) is selected. Bus # returns stop name results; Postal code never geocodes. P0 feature gap.
- `DataStore.refreshArrivals` — if already inflight, returns immediately (correct), but the `RefreshIndicator.onRefresh` future resolves immediately too, so the spinner vanishes instantly and the user sees no visual feedback. No test.
- `DataStore.bootstrap()` has no in-flight guard for the loading state: guard is `if ready → return`, so two rapid cold-start bootstrap calls both proceed and race on `_stopByCode` / `_services`. P1 race condition.
- `AppModel._refreshOngoing` — no test for `etaSec <= 0` path. Covered in `ongoing_tracking_test.dart` for the toggle lifecycle, but not for the arrived-finish path.
- `_masterBell` in `SoftStopScreen` passes `allNos = []` when arrivals haven't loaded yet, calling `setAllTracked(allNos: [])`. This creates a pin with `tracked: null` (the "all" path), but `setAllTracked(tracked: false, allNos: [])` is a no-op while `setAllTracked(tracked: true, allNos: [])` pins with no tracked list — correct for the case, but silently different from a user who wants to alert only specific buses. No test for this empty-allNos path.
- `settings_features_test.dart` tests target old `SettingsScreen` (v1), NOT `SoftSettingsScreen` (v2). 'Language' row exists in v1 but not v2. These tests will become false-positives if v1 is ever deleted.
- No lifecycle observer (`WidgetsBindingObserver`) — permission-revoked-while-backgrounded is only caught when user opens `NotificationsScreen`. If the user revokes while app is alive on a different screen, the ongoing tracker + scheduled alerts remain active until they navigate to Settings.
- No test for `track.` notification tap routing path in `main.dart`. Correctly parsed (same format as `arrival.`) but untested.
- `SoftNearbyScreen` has no `RefreshIndicator` — cannot manually force a refresh of nearby stops.

**Watch out:** The Edit tool renders Unicode "smart quotes" (U+2018/U+2019) when writing Dart string literals if the source text contained them. Always verify with `python3 -c "... f.read().hex()"` after any edit to a .dart file that touches string literals. The original `data_store.dart` used U+2019 as an *apostrophe* inside a straight-quoted string (valid); the Edit tool accidentally promoted U+2018 to a *string delimiter* (invalid). Fix with a binary-level `bytes.replace()` Python one-liner.

**Why:** Reference for future test additions, runner invocation, and coverage gaps.
**How to apply:** Match existing test file naming and framework. Run `flutter test --no-pub` to validate Flutter changes. iOS tests require Xcode.
