---
name: next-actions
description: "Recommended next highest-value tasks for the Leyne project as of 2026-05-30, ordered by priority."
metadata:
  type: project
---

## ANDROID SPRINT 0 — do before cutting any new AAB (audit findings 2026-05-30)

0-A. **Wire search filter chips** (`soft_search_screen.dart:104`) — branch `_results()` on `_filter`: postal→GeocodeService, Bus#→searchServices, StopID/Place→searchStops. iOS reference: `SoftSearchView.swift`. **LAUNCH BLOCKER / store-rejection risk. 5/6 agents.** Size: L.
0-B. **Wire alight alert** (`soft_bus_screen.dart:32,101`) — call `AppModel.setActiveAlight()`; clear on dispose. Port from `detail_screen.dart:61-79`. Size: M.
0-C. **Stop fabricating route ETAs** (`soft_bus_screen.dart:381-383`) — pass null, label "est." or omit. Size: S.
0-D. **CI: build release AAB not debug APK** (`ci.yml:41`) — `flutter build appbundle --release`. Size: S.
0-E. **Pin Flutter SDK in CI** (`ci.yml`) — `flutter-version: 3.44.0`. Size: S.
0-F. **Drop Gradle heap to 4G** (`android/gradle.properties`) — was `-Xmx8G`, > runner RAM. Size: S.
0-G. **Project-relative key.properties path** — replace absolute `/Users/rommel/...jks`. Size: S.
0-H. **Clean up CHANGELOG stale Unreleased blocks**. Size: S.

Full Android roadmap (Sprint 0–3 + native XL items) in [[android-quality-roadmap]].

## Immediate — do before cutting the builds

1. **Fix `kChangelog` in `AppModel.swift`** — add 2.1.0 / 2.2.x / 2.3.0 entries so What's New shows for upgraders. ~20 lines. P1 iOS pre-archive. File: `ios-native/Leyne/AppModel.swift` around line 64.

2. **Move CHANGELOG.md "Unreleased 2.3.0" → versioned block** — required by feedback_changelog rule before every Archive/AAB. File: `CHANGELOG.md`.

## Ship actions (after above)

3. **iOS Archive 2.3.0+13 → TestFlight → App Store resubmit.** Verify `forceTestUnitForRelease = false` in `AdBanner.swift` before submitting to App Store (may be true for TestFlight). Scheme: `Lyne`, destination: `Any iOS Device`. Organizer → Distribute.

4. **Android AAB: `scripts/build-android-prod.sh` → Play upload.** Confirm `SCHEDULE_EXACT_ALARM` in `AndroidManifest.xml`. Upload to closed testing or production depending on review status.

## Next session — pre-ship polish

5. **Port Android search chip logic from iOS** (`soft_search_screen.dart`): wire postal geocode via OneMap HTTP, Bus# → `searchServices`, Stop ID → `searchStops`. iOS reference: `SoftSearchView.swift`. Closes Guideline 2.2 exposure on Android.

6. **Fix `SoftBusView.scheduleAlight`** — replace raw UserDefaults write with `m.setActiveAlight(busNo:stopCode:stopName:fireAt:)`. ~5 lines. P1 iOS correctness. File: `ios-native/Leyne/V2/SoftBusView.swift`.

7. **Android pull-to-refresh** (GAP 6/9/15) — wrap `ListView` in `RefreshIndicator` calling `DataStore.shared.refreshArrivals(code)` in `soft_home_screen.dart`, `soft_stop_screen.dart`, `soft_bus_screen.dart`. Method already exists.

## Deferred / not blocking ship

8. **Dynamic Type on iOS** — `Theme.swift` `sans`/`mono` missing `relativeTo:`. One-file cascades everywhere. P2.

9. **Live bus map marker** — `DataStore.route()` hard-codes `busCoord: nil`; call `liveBus(service:stopCode:)` after route resolves. P2.

10. **iOS `SoftToggle` → native `Toggle`** — a11y, size, system tint. P2.

11. **Delete dead V1 iOS files** — `HomeView.swift`, `SettingsView.swift` are unreferenced. Needs Xcode UI delete (pbxproj update). P2 cleanup.

12. **Android true background tracking** — foreground service. Significant effort. Post-launch fast-follow.

**Why:** Working tree is clean (d3980e2). The only gate is builds. Fix kChangelog first — What's New is broken for all upgraders and it's 20 lines.
**How to apply:** Start every session with git status. If clean, jump to item #1 above.

Related: [[project-status]], [[project-risks]]
