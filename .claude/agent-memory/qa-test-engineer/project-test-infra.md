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
- Files: `app_model_test.dart`, `data_layer_test.dart`, `eta_pill_test.dart`, `onboarding_test.dart`, `pinned_card_test.dart`, `screens_test.dart`, `settings_features_test.dart`, `widget_test.dart`
- Total tests as of 2026-05-30: **83 pass, 0 fail** (the 5 previously failing tests were fixed in this changeset)

**iOS Native (SwiftUI)**
- Test target: `ios-native/LeyneTests/`
- Files: `LeyneCoreTests.swift` (unit + pin logic), `LiveLTATests.swift` (integration, skips without network)
- Run via Xcode or `xcodebuild test`
- No snapshot or UI tests exist; no tests for DataStore, Feedback, or V2 views
- LeyneCoreTests covers: ETA rounding, query detection, haversine, LTA date parsing, load/deck mapping, JSON parsing (arrivals/stops/routes), journey segment trimming, pin Codable round-trip, pin toggle symmetry, tracked toggle + persistence, widget pin mirror, pin/home/detail surface flows, reorder, recents

**Critical gaps as of 2026-05-30 changeset:**
- `DataStore.refreshArrivals` — no unit test; especially the error path that preserves `.loaded` state and the concurrent-inflight guard (if inflight → silent no-op, spinner never spins but no error)
- `AppModel.toggleOngoing` — lifecycle not tested: start, idempotency (toggle same key twice), arrived→auto-nil, service-disappears-but-data-empty (keeps last state), persists across screen pop (no cleanup hook)
- `AppModel._refreshOngoing` — no test for etaSec <= 0 path setting _ongoingKey = null + calling showOngoing(finished:true)
- `AppModel.setAllTracked` — no direct test; exercised only indirectly via _masterBell wiring; edge cases (allNos empty list, already-all state toggling to subset) untested
- `AppModel.rescheduleIfNeeded` — no test; returns early when notifications off (correct), but the schedule call path is untested
- Ongoing notification NOT cancelled when user disables notifications globally (`setNotificationsEnabled(false)` calls `clearAll()` but does NOT set `_ongoingKey = null` — state leak)
- `settings_features_test.dart` expects `Language` row (`findsOneWidget`) but `SoftSettingsScreen` (v2) has removed it — passes only because tests target old `SettingsScreen`, not the V2 screen
- Payload format asymmetry: `track.` payload is `track.{stopCode}.{busNo}` — same as `arrival.` — correctly parsed in main.dart. No unit test for `track.` tap routing.

**Why:** Reference for future test additions, runner invocation, and coverage gaps.
**How to apply:** Match existing test file naming and framework. Run `flutter test --no-pub` to validate Flutter changes. iOS tests require Xcode.
