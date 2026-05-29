---
name: known-failing-tests
description: Known broken Flutter tests — updated after each major changeset
metadata:
  type: project
---

**As of 2026-05-30**: All 83 Flutter tests pass. The 5 previously failing tests were fixed in this changeset (onboarding API drift, notification default `?? false`, widget empty-state copy).

**Previously failing (now fixed):**
1. `onboarding_test.dart` — `onDone` param removed, fixed by rewriting test
2. `settings_features_test.dart:48` — notification default was `?? true`, test expected `false`; fixed to `?? false`
3. `settings_features_test.dart:144` — same root cause
4. `widget_test.dart:42` — expected `'No pinned stops yet'`, actual `'No stops pinned'`; string updated

**Latent failure risk (not currently failing but fragile):**
- `settings_features_test.dart` tests target old `SettingsScreen` (v1), NOT `SoftSettingsScreen` (v2). The test asserts `find.text('Language')` finds one widget. If v1 SettingsScreen ever removes the Language row (as v2 already has), these tests will fail. The V2 settings screen is what users actually see.
- If `settings_features_test.dart`'s "shows trimmed Personalize rows" test is ever pointed at `SoftSettingsScreen`, it will fail because that screen has no Language or Routines rows.

**Why:** Track test health so CI gaps are visible.
**How to apply:** Run `flutter test --no-pub` before every commit. If count drops below 83, check this file.
