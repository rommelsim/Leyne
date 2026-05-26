# Changelog

Reverse-chronological log of every shipped build. Source of truth for
what landed in each AAB / Archive. Update this file whenever a new
version is built (see [BUILDING.md](BUILDING.md)).

Format: one section per version, tagged with the platform and build
artifact path. User-facing iOS releases should also have a matching
entry in `kChangelog` inside `ios-native/Leyne/AppModel.swift`.

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
