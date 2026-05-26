# Building Leyne

Quick reference for the build modes that matter — specifically how each one
selects which AdMob unit to serve, so closed testers never tap real ads.

## Android (Flutter)

Two flags decide which AdMob unit gets served:
`kDebugMode` (set automatically by Flutter) and `kLyneAdsTest`
(passed via `--dart-define`). See `lib/widgets/ad_banner.dart`.

| Command | Mode | AdMob unit |
|---|---|---|
| `flutter run` | debug | Google test unit |
| `./scripts/build-android-closed-test.sh` | release + `LYNE_ADS_TEST=true` | Google test unit |
| `./scripts/build-android-prod.sh` | release | **Real leyne0000 unit** |

### Which one do I use?

- **Hot-reload development on a connected device:** `flutter run` — already serves test ads.
- **Uploading to a Play Store closed / internal testing track:**
  `./scripts/build-android-closed-test.sh`. Required: a closed-testing AAB
  built without this flag will serve the real ad unit to testers, which
  risks AdMob policy violations the moment a tester taps an ad.
- **Uploading the public production release:** `./scripts/build-android-prod.sh`.
  Real impressions, real revenue.

After the script finishes, upload the AAB at
`build/app/outputs/bundle/release/app-release.aab` to Play Console.

## iOS (native SwiftUI at `ios-native/`)

Unit ID is gated by the `DEBUG` macro plus a manual `forceTestUnitForRelease`
toggle for the TestFlight middle stage. See `ios-native/Leyne/AdBanner.swift`.

| Action | Config | Toggle | AdMob unit |
|---|---|---|---|
| Xcode → Run (`⌘R`) | Debug | n/a | Google test unit |
| Archive → TestFlight (pre-review) | Release | `forceTestUnitForRelease = true` | Google test unit |
| Archive → App Store (live) | Release | `forceTestUnitForRelease = false` | **Real leyne0000 unit** |

### Why the manual toggle?

Apple gives TestFlight and App Store distribution the **same Archive**
(both Release config). The `#if DEBUG` macro can't tell them apart, so
there's no automatic build-time signal that says "this Archive is
TestFlight-only." Hence the manual flip in `AdConfig`.

### The TestFlight flip — both lines together

In `ios-native/Leyne/AdBanner.swift`, find the `AdConfig` enum and flip
**both** lines together:

```swift
// For TestFlight pre-review (safe test ads):
static let forceTestUnitForRelease = true
#warning("forceTestUnitForRelease is ON — DO NOT submit this Archive to App Store")

// For App Store distribution (real ads, real revenue):
static let forceTestUnitForRelease = false
//#warning("forceTestUnitForRelease is ON — DO NOT submit this Archive to App Store")
```

The `#warning` surfaces a yellow build warning every compile while it's
uncommented — impossible to miss when archiving for App Store. The bool
is the actual switch; the `#warning` is the nag.

### Which one do I use?

- **Day-to-day development:** Xcode Run — test ads automatically.
- **TestFlight pre-review distribution:** flip both lines (bool to `true`,
  uncomment `#warning`), Archive, upload, distribute via TestFlight.
- **App Store submission:** flip both lines back (bool to `false`,
  re-comment `#warning`), Archive, upload, submit for review.
- **Skipping TestFlight + going straight to App Store review:** leave the
  toggle at `false`. The Archive serves the real unit, which is correct
  for App Store users.

If you'd rather not use the toggle and want individual TestFlight testers
to see test ads, add their IDFA to `AdConfig.testDeviceIdentifiers` in
`AdBanner.swift`. The hash prints to the Xcode console on first ad
request as `"To get test ads on this device, set: ..."` — but that
requires the tester to share their device with you, so the toggle is
usually faster.

## What about clicks?

- Google's reserved test unit serves the same fake creative everywhere.
  Tapping it is a no-op for AdMob's traffic detection — completely safe.
- Real-unit impressions and clicks from your own or known devices are not
  safe. If you build a test/dev variant against the real unit (e.g. to
  validate ad rendering on a physical phone), register that device's
  AdMob test hash:
  - Android: append it to `kTestDeviceIdentifiers` in
    `lib/services/ad_consent.dart`.
  - iOS: append it to `AdConfig.testDeviceIdentifiers` in
    `ios-native/Leyne/AdBanner.swift`.

  Listed devices serve test creatives regardless of which unit is requested.

## Master ad switch (emergency)

To ship a zero-ads build (e.g. during an AdMob account suspension), flip:

- Android: `kLyneAdsEnabled = false` in `lib/widgets/ad_banner.dart`
- iOS: `AdConfig.adsEnabled = false` in `ios-native/Leyne/AdBanner.swift`

Both short-circuit before the SDK is touched, so no traffic ever reaches
AdMob from that build.
