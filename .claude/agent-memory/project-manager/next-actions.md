---
name: next-actions
description: "Recommended next highest-value tasks for the Leyne project as of 2026-05-30, ordered by priority."
metadata:
  type: project
---

## Immediate (do before anything else)

1. **Commit in-flight work — in 3 logical splits:**
   - Commit A: iOS widget/LA palette + Live Activity CTA wiring (`SoftBusView.swift`, `LeyneLiveActivity.swift`, `LeyneStopWidget.swift`)
   - Commit B: Android parity pass — stop alerts, home PIN chip, settings wiring (`soft_stop_screen.dart`, `soft_home_screen.dart`, `soft_settings_screen.dart`, `app_model.dart`, `data_store.dart`)
   - Commit C: Android bus notify + ongoing notification (`soft_bus_screen.dart`, `notifications.dart`, `main.dart`)
   Update `CHANGELOG.md` before each commit (or in one final commit). See [[feedback_changelog]].

2. **Bump versions before any build:**
   - iOS: increment MARKETING_VERSION (2.2.3 → 2.3.0 recommended given scope) + CURRENT_PROJECT_VERSION in `project.pbxproj` (6 blocks)
   - Flutter: bump `pubspec.yaml` version string

## Next session — pre-ship polish (highest value remaining)

3. **Fix `SoftBusView.scheduleAlight`** — replace raw UserDefaults write with `m.setActiveAlight(busNo:stopCode:stopName:fireAt:)`. ~5 lines. P1 iOS correctness.

4. **Fix `kChangelog` in `AppModel.swift`** — add 2.1.0 / 2.2.x / 2.3.x entries so What's New works for upgraders.

5. **Add pull-to-refresh on Android** (Home, Stop, Bus) — wrap Flutter `ListView` in `RefreshIndicator` calling `DataStore.shared.refreshArrivals`. GAP 6/9/15. The `refreshArrivals` method already exists in the uncommitted diff.

6. **Fix GAP 14** — delete `etaMin` fabrication in `_SoftBusScreenState._timelineStops`. One-liner. iOS removed this; Android is inventing per-stop minutes.

## Near-term (next iOS archive)

7. **iOS Archive for new version.** Once commits + version bump are done: cut Archive in Xcode, distribute via TestFlight, then App Store. Verify `forceTestUnitForRelease` is false before App Store submission.

8. **Android AAB.** Run `scripts/build-android-closed-test.sh`, upload to Play closed testing. Verify `SCHEDULE_EXACT_ALARM` in manifest.

## Deferred / not blocking ship

9. **Android true background tracking** via foreground service. Current ongoing notification is foreground-only — document the limitation in release notes. Full fix is a significant Android `Service` implementation.

10. **iOS CI for `ios-native/`** — add `xcodebuild` job to CI. Zero coverage today.

11. **`SoftBusView` live bus map marker** — `DataStore.route()` hard-codes `busCoord: nil`; call `liveBus(service:stopCode:)` after route resolves and merge coordinate. P2.

12. **Dynamic Type on iOS** — `Theme.swift` `sans`/`mono` missing `relativeTo:`. One-file fix.

13. **iOS `SoftToggle` → native `Toggle`** — a11y, size, system tint. P2.

**Why:** Commits must precede any build. Version bumps must precede commits if a build follows. The rest is ordered by value-to-effort ratio.
**How to apply:** Start every session with git status. If uncommitted work remains, that is action #1.

Related: [[project-status]], [[project-risks]]
