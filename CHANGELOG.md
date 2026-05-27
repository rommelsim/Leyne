# Changelog

Reverse-chronological log of every shipped build. Source of truth for
what landed in each AAB / Archive. Update this file whenever a new
version is built (see [BUILDING.md](BUILDING.md)).

Format: one section per version, tagged with the platform and build
artifact path. User-facing iOS releases should also have a matching
entry in `kChangelog` inside `ios-native/Leyne/AppModel.swift`.

## 2.2.3+12 — iOS (next archive) · 2026-05-26
## 2.2.8+20 — Android (closed testing) · 2026-05-26

Two QoL fixes, both platforms:

- **iOS DetailView top bar no longer paints a stray material band.**
  Removed `.background(t.glassSurface())` from `DetailView.topBar`
  (`DetailView.swift:187`). At scroll-zero with nothing scrolled
  beneath, the static glass material was visible as a rectangle band
  between the safe area and the page below — uncharacteristic of
  iOS-native chrome (system nav bars only paint material when content
  scrolls under them). Buttons now sit cleanly on `t.bg`.
- **Route Progress auto-extends to include the alight stop + adds a
  "Show all N stops" expander.** Previously the focused window was
  capped at `youIndex + 5`, so picking an alight 10 stops past the
  boarding stop was impossible (the picker couldn't reach the stop).
  Now: window auto-extends to `alightIdx + 1` when the user has set
  an alight, AND a bottom expander toggles between focused view and
  full route. Both platforms — `DetailView.swift` `RouteProgress`,
  `lib/widgets/route_progress.dart` (converted to StatefulWidget).

(Previous 2.2.2+11 iOS block content folded into this entry.)

## ~~2.2.2+11 — iOS (next archive) · 2026-05-26~~ (superseded by 2.2.3+12)

Project: `ios-native/Leyne.xcodeproj` — `MARKETING_VERSION = 2.2.2`,
`CURRENT_PROJECT_VERSION = 11` across all 3 targets (Leyne,
LeyneWidgets, LeyneTests).

The iOS-side companion to Android 2.2.7+17. Adds the same two
improvements landed in the Flutter codebase this turn:

- Default-on notifications + onboarding step 3 fires the system
  permission prompt (matches Location's pattern). Boot-time fallback
  in `RootView.task` covers existing users past onboarding so a fresh
  upgrade still gets prompted.
- Tap-to-open deep link: `LeyneAppDelegate.didReceive` broadcasts a
  `leyneOpenStopFromNotification` event with the notification's
  `userInfo`; `RootView.onReceive` reads `stopCode` + `busNo` and
  drills into the bus's DetailView. Alight notifications carry only
  `busNo`; the stopCode is sourced from the persisted `ActiveAlight`
  ride.

## 2.2.7+19 — Android (closed testing) · 2026-05-26

Build: `scripts/build-android-closed-test.sh` →
`build/app/outputs/bundle/release/app-release.aab`

versionCode-only rebumps after Play rejected +17 then +18 with
"Version code N has already been used" — both numbers were already
claimed by prior closed-testing uploads. Source identical to +17/+18.

## 2.2.7+17 — Android (closed testing) · 2026-05-26

Build: `scripts/build-android-closed-test.sh` →
`build/app/outputs/bundle/release/app-release.aab`

- **Notifications now opt-in at first launch.** Default switched to ON
  on both platforms; the onboarding "STAY PRESENT" step (3) now fires
  the system permission prompt directly, same pattern as the
  Location step. No more digging into Settings → Notifications to
  discover the feature.
- **Boot-time fallback** for existing users past onboarding: if the
  system has never asked for `POST_NOTIFICATIONS` and the intent flag
  is ON, the prompt fires once at next app launch. iOS uses the same
  flow via `RootView.task`. Idempotent — the OS only ever shows the
  dialog once.
- **Tap-to-open deep link.** Tapping an arrival or alight notification
  now opens the bus's detail view directly (previously, tapping just
  raised the app to whatever screen was last visible).
  - iOS: `LeyneAppDelegate.userNotificationCenter(didReceive:)` posts
    a `leyneOpenStopFromNotification` event with the userInfo
    (`kind`, `stopCode`, `busNo`); RootView's `.onReceive` calls
    `AppModel.open` to drill in.
  - Flutter: `NotificationsService.onNotificationTapped` parses the
    payload string (`arrival.<stopCode>.<busNo>` or
    `alight.<busNo>.<stopName>`) and pushes `DetailScreen` via the
    global navigator. `getNotificationAppLaunchDetails` replays the
    initial cold-start tap so a launch-from-notification lands too.
- iOS still pending an Archive; Android AAB ready to upload.

## 2.2.6+16 — Android (closed testing) · 2026-05-26

Build: `scripts/build-android-closed-test.sh` →
`build/app/outputs/bundle/release/app-release.aab`

- **Re-enabled exact alarm scheduling — Whatsapp-/SMS-like immediacy.**
  Bus arrival alerts now fire at the intended second, not within
  Android's Doze maintenance window. Previously inexact-only after the
  2.2.5+15 walk-back, which could delay an arrival heads-up by minutes.
- Declared `SCHEDULE_EXACT_ALARM` only (not `USE_EXACT_ALARM`). The
  former is the open-use permission that calendar reminders, ride-share
  pickup alerts, and transit apps commonly request; the latter is the
  alarm-clock/calendar-only restricted permission that Play rejected
  in 2.2.4+14.
- Auto-granted on Android 12–13. On Android 14+ the user is prompted
  once via the system's "Alarms & reminders" Settings screen at the
  moment Arrival alerts are toggled on. Denial degrades gracefully to
  inexact scheduling — the notification still fires, just batched.
- New `NotificationsService.requestExactAlarmAuthorization()` +
  internal `_scheduleMode()` resolver that picks exact vs inexact per
  the current permission state for both arrival and alight alerts.

## 2.2.5+15 — Android (closed testing) · 2026-05-26

Build: `scripts/build-android-closed-test.sh` →
`build/app/outputs/bundle/release/app-release.aab`

- **Removed `USE_EXACT_ALARM` and `SCHEDULE_EXACT_ALARM` permissions.**
  Play Console rejected 2.2.4+14 during release review — Google
  restricts these permissions to apps whose core functionality is
  calendar or alarm clock. Leyne is neither.
- Switched `flutter_local_notifications` `zonedSchedule` calls (both
  arrival and alight alerts) from `AndroidScheduleMode.exactAllow`
  `WhileIdle` to `inexactAllowWhileIdle`. Notifications still fire at
  approximately the right moment; the system may batch within its
  Doze maintenance window. Acceptable trade-off for a ~1-minute-out
  bus arrival heads-up.
- No code or UX changes beyond the permission + schedule-mode swap.

## 2.2.4+14 — Android (closed testing) · 2026-05-26

Build: `scripts/build-android-closed-test.sh` →
`build/app/outputs/bundle/release/app-release.aab`

- **On-bus alight alert wired end-to-end on both platforms.** Picking
  an alight stop in the route progress now arms a real notification
  that fires ~2 stops before the bus reaches the chosen stop. Previous
  builds only displayed the "Buzz me 2 stops before…" UI without
  actually scheduling anything.
- `ActiveAlight` model + persisted single-ride state in AppModel
  (Flutter) and equivalent `@AppStorage`-backed state on iOS native.
  One active ride at a time; persists across app restarts.
- `NotificationsService.scheduleAlightAlert` (Flutter) +
  `NotificationsManager.scheduleAlightAlert` (iOS) — fire 60 s before
  predicted alight time using a one-shot scheduled notification.
- Predicted fire time computed from RouteInfo: 90 s × max(0,
  stopsToAlight − 2) from now, using `busIndex` or `youIndex` as the
  starting reference. MVP estimate, accurate within a stop or two.
- Added the "Buzz me 2 stops before X" card to Flutter DetailScreen
  (previously iOS-only). Tappable to dismiss when active.

## 2.2.3+13 — Android (closed testing) · 2026-05-26

Build: `scripts/build-android-closed-test.sh` →
`build/app/outputs/bundle/release/app-release.aab`

- **Replaced in-app SnackBar arrival alerts with real native Android
  notifications.** Switched to `flutter_local_notifications` +
  `timezone` + `permission_handler` for system-level scheduling.
  Notifications fire ~60 s before each tracked bus's `arrivalDate` and
  appear on the lock screen / as a heads-up banner regardless of app
  lifecycle, matching the iOS-native behaviour.
- New `lib/services/notifications.dart` (`NotificationsService`):
  one-time tz database + Android channel init, per-service identifier
  (`arrival.<stopCode>.<busNo>`), idempotent reschedule that cancels
  orphans, `Importance.high` channel + `timeSensitive` interruption
  level on iOS targets.
- `AppModel.setNotificationsEnabled` is now `async` and requests the
  Android 13+ `POST_NOTIFICATIONS` runtime permission; the toggle
  snaps back to off if denied. Tick loop re-arms scheduled alerts
  every 10 s against live LTA data.
- `NotificationsScreen` dropped the "background alerts are on the
  roadmap" disclaimer; gained a denied-permission warning + **Open
  Android Settings** shortcut when iOS blocks the permission.
- `AndroidManifest.xml`: added `POST_NOTIFICATIONS`,
  `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`, `RECEIVE_BOOT_COMPLETED`;
  declared the `ScheduledNotificationReceiver` + boot receiver so
  scheduled alarms survive a reboot.

## 2.2.2+12 — Android (closed testing) · 2026-05-26

Build: `scripts/build-android-closed-test.sh` →
`build/app/outputs/bundle/release/app-release.aab`

- Swapped AdMob banner to Google's reserved test unit
  (`ca-app-pub-3940256099942544/6300978111`) so closed-testing tappers
  can't trigger invalid-traffic flags against the real leyne0000 unit.
  Toggle controlled by `--dart-define=LYNE_ADS_TEST=true` baked into
  the closed-test build script.
- Added `scripts/build-android-closed-test.sh` +
  `scripts/build-android-prod.sh` so each build path is a single
  command with the right flag.
- Added `BUILDING.md` at repo root documenting the dev/test/prod ad
  matrix for both platforms.

## 2.2.1+11 — Android · 2026-05-26 (re-ads-enabled)

Build: `flutter build appbundle --release` (legacy, before the scripts
existed). Served the real leyne0000 banner unit — superseded by
2.2.2+12 above because closed testers risked policy violations
on real-ad taps.

- Re-enabled ads after the AdMob suspension was resolved on
  `rommelsim@gmail.com`.
- Updated AdMob app + unit IDs back to leyne0000 (app ID
  `ca-app-pub-5864511655536507~5685985257`, banner unit
  `ca-app-pub-5864511655536507/6513878972`).

## 2.2.0+10 — Android · pre-2026-05-26

Bumped for release. See git commit `c7db613` for the diff.

## Pending — iOS (not yet archived)

Tracking unreleased iOS work currently in `ios-native/` working tree.
This section moves into a real version block on next Archive.

- **Real device notifications** — `UNUserNotificationCenter` schedules
  one-shot local notifications ~60 s before each tracked bus's
  `arrivalDate`. Time-sensitive interruption level on iOS 15+, threads
  by stop code, denied-permission warning + Open Settings shortcut in
  Settings ▸ Notifications. `LeyneAppDelegate` adopted as
  `UNUserNotificationCenterDelegate` so foreground alerts banner.
- **iOS-native edge-swipe-back** — `EdgeSwipeBack` ViewModifier in
  `RootView.swift` claims drags that start within 24 pt of the leading
  edge, drags DetailView / DetailPager 1:1 with the finger, commits on
  80 pt of travel or a flick. Coexists with DetailPager's TabView page
  swipes (those start further inboard).
- **iOS push animation switched to spring** — `RootView.swift`
  `.animation(.spring(response: 0.42, dampingFraction: 0.86), value:
  m.openCard)`, matching UIKit's `UINavigationController` curve. Pure
  slide transition (no opacity fade) on DetailView for crisper dismiss.
- **iOS TestFlight ad toggle** — `AdConfig.forceTestUnitForRelease` +
  paired `#warning` line in `AdBanner.swift`. Default `false` (App
  Store-safe). Flip both to `true` before TestFlight Archives; flip
  back before App Store-bound Archives. See BUILDING.md.
