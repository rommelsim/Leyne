---
name: known-failing-tests
description: Tests that are currently broken due to code changes not being reflected in the test suite (as of 2026-05-29)
metadata:
  type: project
---

As of 2026-05-29 (confirmed by running `flutter test --no-pub`), 5 Flutter tests fail. All are hard failures, not flaky:

1. **`onboarding_test.dart` — entire file (compile/runtime error)**
   All tests fail because `OnboardingScreen` no longer accepts `onDone` parameter (removed in diff). Every test constructor still passes `onDone: () {}`. Also tests a `Skip` button that no longer exists. Requires a full rewrite of the file: remove `onDone` param, add missing `onRequestNotifications`, remove the "Skip calls onDone" test, and update the double-tap test to remove `onDone` from the widget constructor.

2. **`settings_features_test.dart:48` — "notifications toggle defaults off and persists"**
   `AppModel` loads `notificationsEnabled` with `?? true` default (line 377 of app_model.dart), so a fresh SharedPreferences mock returns `true`. Test expects `false`. Fix: change the test to expect `true`, or seed prefs with `false`.

3. **`settings_features_test.dart:144` — "Notifications row navigates and toggles the preference"**
   Same root cause — notification default is `true`, not `false`. Toggle assertion direction is inverted relative to actual starting state.

4. **`widget_test.dart:42` — "Root shell shows the four tabs"**
   Test expects `'No pinned stops yet'` but `SoftHomeScreen` (via `SoftEmptyState`) now renders `'No stops pinned'`. One-line fix: update the expected string.

**Why:** These are all caused by API/copy drift — code changed but tests were not updated in sync.
**How to apply:** All four must be fixed before any CI gate. They are not flaky.
