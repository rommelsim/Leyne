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
- Total tests as of 2026-05-29: ~72 (67 pass, 5 fail — see [[known-failing-tests]])

**iOS Native (SwiftUI)**
- Test target: `ios-native/LeyneTests/`
- Files: `LeyneCoreTests.swift` (unit + pin logic), `LiveLTATests.swift` (integration, skips without network)
- Run via Xcode or `xcodebuild test`
- No snapshot or UI tests exist; no tests for DataStore, Feedback, or V2 views
- LeyneCoreTests covers: ETA rounding, query detection, haversine, LTA date parsing, load/deck mapping, JSON parsing (arrivals/stops/routes), journey segment trimming, pin Codable round-trip, pin toggle symmetry, tracked toggle + persistence, widget pin mirror, pin/home/detail surface flows, reorder, recents

**Critical gaps (as of 2026-05-29 diff):**
- `DataStore.refreshArrivals` — new async force-refresh has no unit test; error path (preserving stale state when already .loaded) is untested
- `Feedback.ensureEngine` — `setActive(true)` removal behaviour cannot easily be unit-tested without device; manual regression test needed
- `SoftStopView.trackAllLabel` — 4 branches (`"Alert all"`, `"All alerts"`, singular `"1 alert"`, plural `"N alerts"`) have no unit tests
- `SoftHomeView` pull-to-refresh fires `refreshArrivals` sequentially for each pin — no test for the multi-pin refresh ordering or partial failure

**Why:** Reference for future test additions, runner invocation, and coverage gaps.
**How to apply:** Match existing test file naming and framework. Run `flutter test --no-pub` to validate Flutter changes. iOS tests require Xcode. Fix 5 failing tests before any CI gate.
