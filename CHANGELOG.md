# Changelog

Reverse-chronological log of every shipped build. Source of truth for
what landed in each AAB / Archive. Update this file whenever a new
version is built (see [BUILDING.md](BUILDING.md)).

Format: one section per version, tagged with the platform and build
artifact path. User-facing iOS releases should also have a matching
entry in `kChangelog` inside `ios-native/Leyne/AppModel.swift`.

## Unreleased — Leyne 2.0 "Soft" redesign · 2026-05-29

First execution pass of the Leyne 2.0 redesign from the Claude Design
handoff bundle (`~/Downloads/leyne-2-0/`, Soft direction). Both
platforms now carry the new palette and the V2 "Soft" UI is the
default (and only) path on iOS and Android — the original
`leyne.softUI` gate has been retired.

- **New Soft palette.** `ios-native/Leyne/Theme.swift` and
  `lib/theme.dart` updated in place with the warm dark (`#15201C`) /
  warm light (`#F4EFE7`) bg + mint accent
  (`#8EE6C0` dark / `#2D7A5A` light). Property names preserved so
  existing call sites compile against the new values.
- **iOS V2 screens behind `leyne.softUI` flag.** New
  `ios-native/Leyne/V2/` directory containing nine shared primitives
  (ServiceBadge, LabelPill, SortChipRow, IOSGlassPill, SoftTabBar,
  RouteTimeline, MapHandoffToast, SoftPrimitives) and six screens
  (Home / Nearby / Stop / Bus / Search / Settings) wired to real
  `DataStore` arrivals + `LocationManager` + LTA routes. Toggle with
  `defaults write com.leyne.Leyne leyne.softUI -bool true`.
- **MRT line palette.** New `MRTLine` enum + `LyneSignal` namespace
  (Flutter) / cross-mode `mrtNE` + `meBlue` colours (iOS) for transit
  overlays that don't change between dark and light.
- **Pull-to-refresh across the V2 stack (iOS).** New async
  `DataStore.refreshArrivals(stop:)` (always hits the network and is
  awaitable) wired to `.refreshable` on `SoftHomeView`, `SoftStopView`,
  and `SoftBusView`. Stop/Bus also reload route geometry on pull.
- **Onboarding parity + no Skip.** Flutter onboarding drops the `onDone`
  callback and the Skip button to match iOS — every user passes through
  the notification / location / ads priming steps; onboarding completes
  only by reaching the final step (`lib/main.dart`,
  `lib/screens/onboarding_screen.dart`, `OnboardingView.swift`).
- **Notifications default OFF (Flutter bugfix).** `AppModel.load()` was
  reading `lyne.notifications ?? true`, so a fresh install showed the
  toggle ON before `POST_NOTIFICATIONS` was ever granted — a lying
  toggle that fired no alerts. Now defaults to `false` (opt-in), the
  honest "persisted result of the permission flow".
- **UX honesty fixes (iOS).** Home cards suppress the empty "PIN" chip;
  the stop-header `figure.walk` icon (walk minutes were never populated)
  becomes `mappin.and.ellipse`; the master pill reads "Alert all / All
  alerts / N alerts" instead of the misleading "Track all".
- **Audio session fix (iOS).** `Feedback` no longer forces
  `setActive(true)`, which was interrupting background music on launch.
- **Live Activity entry point in V2 (iOS).** `SoftBusView` now shows a
  Start/Stop Live Activity row wired to the existing
  `AppModel.toggleLiveActivity(...)` engine (15 s LTA polling, stops-away,
  auto-end on arrival, relaunch restore — already used by V1
  `DetailView`). The previous comment claiming "ActivityKit isn't wired"
  was stale; the only missing piece was this surface. The row reflects
  live on/off state and is hidden when there's no arriving service or the
  user has disabled Live Activities system-wide, so it never dead-ends.
- **WidgetKit surfaces aligned to the Soft palette (iOS).** Both the Home
  Screen widget (`LeyneStopWidget`) and the Live Activity
  (`LeyneLiveActivity`) had inline palettes left over from the pre-Soft
  theme (bg `#0E0E0A`/`#F7F4ED`, mint `#5EE597`/`#2BAA67`). Repointed every
  token at the current `Theme.swift` Soft values (bg `#15201C`/`#F4EFE7`,
  accent `#8EE6C0`/`#2D7A5A`, solid `liveBg`), nudging `dim`/`faint` alpha
  up for small-text legibility on-glass. Per UX direction: `.continuous`
  corners throughout; `.widgetAccentable` on the semantic elements (arriving
  ETA, mint arriving pill, the pinned `bookmark` glyph, compact/minimal bus
  number) so meaning survives StandBy / Lock-Screen monochrome tint; a
  numeric content-transition on the Live Activity countdown; Small-widget
  stop name bumped 12→13pt. Deferred (P2): swapping the Unicode `→` for an
  SF Symbol arrow.
- **Android V2 parity pass (Flutter).** Closed several iOS↔Android gaps a
  cross-platform UX review surfaced: (1) **pull-to-refresh** on Home / Stop /
  Bus via a new awaitable `DataStore.refreshArrivals(code)` (Home refreshes
  all pins concurrently); (2) Home pin card hides the chip when there's no
  real nickname instead of showing a redundant "PIN" (matches iOS); (3)
  Settings **Notifications** row now pushes the real `NotificationsScreen`,
  and the dead **Routines** section + **Language** row (no destinations, not
  on iOS) were removed; (4) removed the dead "Track in notifications" Live
  Activity card and the no-op AppBar lock button on the Bus screen — the
  Android ongoing-notification equivalent isn't built yet, so no dead
  affordance; (5) the bus map drops the phantom "BUS N" legend entry (LTA
  never shares that coordinate) for the same honest caption iOS uses.
- **Android stop alert controls (Flutter).** Closed the largest parity gap:
  the V2 stop screen now lets you choose which buses alert you, matching iOS
  in capability via Material-native controls. Per-bus **bell** `IconButton`
  on each row + primary card (tracked rows get a `liveBg` tint + left accent
  rule — two non-colour cues), an AppBar **master bell** (alert-all / clear),
  a `SegmentedButton` Soonest/Bus-no. sort, a discovery hint, and a
  `warnBg` banner with an "Enable" action when notifications are globally
  off. The FAB is gone — pinning is now implicit (first bell pins, last
  untap unpins), matching iOS's `pinned ⟺ ≥1 tracked bus` invariant. This
  reuses the existing `toggleTracked` / `setAllTracked` / `isTracked` APIs
  (so it also drives the Home card's tracked subset — by design) plus one
  new `AppModel.rescheduleIfNeeded()` that re-arms the scheduler immediately
  after a toggle. Per UX, the per-bus model was chosen over iOS-style
  independent alerts because both platforms already share the same
  `Pin.tracked` data model — iOS just had the UI wired first.
- **Android bus notify button + ongoing live-tracking notification
  (Flutter).** The bus screen gains a full-width arrival-alert toggle
  (same `toggleTracked` mechanism as the stop bells), closing the last
  notify-button parity gap. And the Android stand-in for the iOS Live
  Activity is now built: a silent, ongoing notification (new low-importance
  `leyne.tracking` channel) that follows one bus's ETA, started from a
  "Track in notifications" card on the bus screen (shown only when
  notifications are enabled, so it never dead-ends). `AppModel.toggleOngoing`
  manages a single tracker; the 1 s tick pushes ETA updates every ~5 s and
  finalises to a dismissable "Arriving now" when the bus arrives; tapping it
  deep-links back to the bus (new `track.<stop>.<bus>` payload). **Known
  limit:** updates run while the app process is alive — a fully background
  tracker needs a native foreground service (not built yet); the `ongoing`
  flag still pins it in the shade until arrival/stop.
- **Post-review hardening (team review fixes).** Ongoing-tracker leak fixed:
  it's now torn down when notifications are disabled/denied and on cold start
  (it was in-memory only, so the OS could otherwise keep showing a stale,
  frozen notification). `_refreshOngoing` finalises after ~15 s of the
  service being absent instead of pinning a frozen ETA forever; starting a
  tracker for a different bus now explicitly replaces the prior one.
  `clearAll`/`cancelAlightAlerts` gained `_initialized` guards (mirroring
  `scheduleArrivalAlerts`) so a pre-init toggle can't crash. iOS: the two
  missed `.widgetAccentable` modifiers (Large widget `bookmark`, service-row
  ETA numeral) added so the arriving signal survives StandBy tinting. The
  stop screen's master bell now reflects all-tracked vs partial honestly, and
  the ongoing-tracking card copy states updates run "while the app is open".
- **iOS-native CI + tests.** Added a third CI job (`ios-native`) that
  `xcodebuild`s the SwiftUI app + LeyneWidgets extension on every push —
  previously the iOS CI job only built the Flutter wrapper, so Swift/widget/
  Live-Activity errors were invisible until Xcode. Added
  `test/ongoing_tracking_test.dart` covering the ongoing-tracker lifecycle
  (activate/replace/disable-clears), `setAllTracked` edge cases, and
  `rescheduleIfNeeded` (Flutter suite now 91 passing).
- **Tests realigned.** Flutter suite green (83 passing): onboarding
  tests follow the 6-step no-Skip flow, the empty-state and settings
  copy match V2, and the notification toggle path mocks the
  permission / local-notification platform channels.
- See `specs/leyne-2.0-plan.md` for the full plan, sequencing, and
  open decisions.

## 2.2.9+21 — Android (closed testing) · 2026-05-27

Code-review polish pass — bugs/correctness + platform-design alignment.

- **RouteProgress no longer crashes on empty `route.stops`.** Defensive
  early-return in `lib/widgets/route_progress.dart` (and iOS sibling
  in `DetailView.swift`) — `int.clamp(0, -1)` was throwing
  `ArgumentError` in the unlikely case where a RouteInfo arrived with
  zero stops (malformed LTA response or bootstrap race). Now renders
  an empty `SizedBox` instead of taking down the screen.
- **`refreshNotificationAuth` no longer flips the toggle on
  `.notDetermined`.** `lib/state/app_model.dart` was treating "the
  system hasn't been asked yet" the same as "user said no", silently
  disabling the user's intent during boot-time prompt races. Now only
  flips off on explicit `.denied` / `.permanentlyDenied`. Mirrors the
  iOS guard.
- **Alight notification identifier uses the stop CODE, not the
  user-facing name.** `lib/services/notifications.dart` was building
  `alight.<busNo>.<stopName>` — names like "Opp Blk 211" contain
  spaces and punctuation that would make the payload awkward to parse
  if it ever became load-bearing for routing. Now uses
  `alight.<busNo>.<stopCode>`. iOS `AppModel.swift` got the same fix.
- **Onboarding Back button works on the final (ATT) step.**
  `lib/screens/onboarding_screen.dart` was leaving `_busy = true`
  after the ATT Continue tap (the caller drives dismissal), trapping
  the user with no Back if `AdConsent.gatherThenStart()` stalled. Now
  matches iOS — Back stays enabled on the final step.
- **On-bus alert card uses a Material `Switch` instead of a
  hand-drawn iOS-style sliding pill.** `lib/screens/detail_screen.dart`
  `_onBusAlertCard` is now a proper Material `Card` + `Switch` row —
  Android chrome on Android, per platform-design memory. iOS keeps
  its `TogglePill`.
- **"BOARD HERE" replaces "YOUR STOP" in iOS RouteProgress.** Both
  platforms now use the same vocabulary for the three trailing badges
  (BUS / BOARD HERE / ALIGHT). iOS DetailView also got a small badge
  for the user's stop, matching Flutter's filled-accent style.
- **Redundant "VIEWING BUS X → Y" heading row removed (iOS).** The
  hero card right below shows the same bus number and destination in
  much larger type — the meta row was duplicate ink.
- **Arrival notification body drops "head down to the stop" when
  `walkMin == 0`.** That suffix assumed "user is at the stop", but
  `walkMin == 0` means "no location fix yet" — read wrong when the
  user was actually elsewhere. Now just shows the stop label in that
  case. Both platforms.

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
