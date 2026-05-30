---
name: known-issues
description: Confirmed code quality issues from 2026-05-30 audit with file:line citations
metadata:
  type: project
---

## P0 (Store exposure / user-visible correctness breakage)

- **Search chips fully decorative** — `lib/screens/v2/soft_search_screen.dart:104` — `_results()` calls `DataStore.shared.searchStops(q)` unconditionally regardless of `_filter`. Postal → OneMap geocode path, Bus # → `searchServices`, Stop ID → code-exact match, Place → text search: NONE of these are wired. `_filter` is only consumed by `_detected()` which renders the label caption. GeocodeService exists but is never imported in this file.

## P1 (Functional bugs, will confuse users)

- **`_liveService()` wrong bus fallback** — `lib/screens/v2/soft_bus_screen.dart:117` — `orElse: () => a.services.first` returns whatever the first service is when the intended `widget.svc` isn't in arrivals yet. The bus screen can silently display the wrong bus's ETA and trigger wrong notification scheduling.
- **Notification payload parse fragile: stop names with dots break alight routing** — `lib/main.dart:54` — payload is split on `.` (`parts = payload.split('.')`). `alight.<busNo>.<stopName>` where stopName contains a dot (e.g. "Opp Blk 211A" is fine, but any stop with a dot in its name would produce parts.length > 3 and parts[1] would be truncated). The code checks `parts.length < 3` but `alight` only needs 2 meaningful parts (kind + busNo); stopCode is recovered from AppModel. Low risk in practice (stop names rarely have dots) but structurally brittle.
- **`_scheduleMode()` called per-notification in loop** — `lib/services/notifications.dart:434` — `await _scheduleMode()` is inside the `for (final d in desired)` loop. Each call does `await Permission.scheduleExactAlarm.status` — a platform channel round-trip. With N pinned stops × M tracked services this fires N×M permission reads per reschedule cycle. On a device with 5 pinned stops and 3 buses each, that's 15 serial IPC calls per 10-second reschedule tick.
- **No `WidgetsBindingObserver` on any screen** — When the user revokes notification permission via Android Settings, returns to the app, and navigates to the home or bus screen (not NotificationsScreen), `refreshNotificationAuth()` is never called. The ongoing-tracking card and bell icons stay enabled until the user taps NotificationsScreen. `NotificationsScreen.initState` refreshes auth but no screen attaches `didChangeAppLifecycleState`.

## P2 (Quality / Material 3 gaps)

- **1-second global tick rebuilds all visible screens** — `lib/state/app_model.dart:448` — `notifyListeners()` called unconditionally every second inside `_onTick()`. `Listenable.merge([AppModel.shared, DataStore.shared, LocationService.shared])` in home/stop/bus screens means every screen rebuilds every second regardless of whether any data changed. No `shouldRepaint`-style guard.
- **`SoftToggle` instead of Material `Switch`** — `lib/widgets/v2/soft_components.dart:147` / `lib/screens/v2/soft_settings_screen.dart:147` — Custom toggle widget replaces the platform-native `Switch`. Loses: TalkBack labelling, system tint inheritance, correct touch target sizing (Material spec: 48×48dp, SoftToggle is 44×26).
- **`_haversine` duplicated in `soft_home_screen.dart`** — `lib/screens/v2/soft_home_screen.dart:201` — A private static `_haversine()` is reimplemented, while `lib/data/geo.dart:10` exports the identical `haversine()` function and `walkMinutesFor()`. The screen also reinvents the walk-minutes formula (`d / 80`). `AppModel._walkMin()` already delegates to geo.dart; `SoftHomeScreen._walkMinutes()` does not.
- **ETA fabrication in route timeline** — `lib/screens/v2/soft_bus_screen.dart:381` — `etaMin = baseMin + (idx - yIdx) * 2` — each upcoming stop gets the live ETA plus 2 minutes per stop. This is invented; LTA provides no intermediate ETA. Shows as clock times to the user via `_clockETA`. Confusing if the bus is stuck in traffic.
- **R8 disabled for wrong reason / no proguard rules attempted** — `android/app/build.gradle.kts:77` — `isMinifyEnabled = false`. The root cause (WorkDatabase_Impl obfuscation from Google Mobile Ads SDK) has a proper fix: add a `-keep class androidx.work.impl.** { *; }` rule. Disabling R8 entirely means the Android AAB ships with no dead-code elimination, resulting in a larger download size than necessary.
- **Nearby screen has no pull-to-refresh** — `lib/screens/v2/soft_nearby_screen.dart` — No `RefreshIndicator` or `AlwaysScrollableScrollPhysics`. Home, Stop, and Bus all have it. Nearby is the odd one out.
- **No foreground service for ongoing tracker** — `android/app/src/main/AndroidManifest.xml` — The live-tracking notification (`leyne.tracking` channel) is an `ongoing` notification served via `_plugin.show()`, but there is no `<service android:foregroundServiceType=...>` declaration or `startForeground()` call. On Android 8+ the OS can kill the notification when the app process is suspended. This is documented in CHANGELOG.md but produces a misleading UX: the notification appears active but stops updating silently.
- **`onlyAlertOnce` only suppresses sound/vibrate, not the content update itself** — `lib/services/notifications.dart:195` — On Android 12+ the notification content (ETA countdown) updates visually every 5 seconds via `_plugin.show()`. Because there is no foreground service, once the app process is killed these updates stop — but the notification remains pinned in the drawer showing a stale ETA. The user sees "3 min" forever.
