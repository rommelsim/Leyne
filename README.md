# Leyne

Live Singapore bus arrival times — pin your stops, glance at the next bus.
Powered by [LTA DataMall](https://datamall.lta.gov.sg/).

> **Repo status (May 2026):** migrating from the shipping iOS-native app to a
> cross-platform **Flutter** rebuild targeting iOS + Android.
>
> | Branch | What it is |
> |---|---|
> | `main` | Shipping iOS-native app (SwiftUI, App Store v1.0). |
> | `flutter-dev` | **This branch.** Flutter rewrite in progress. iOS code preserved under [`legacy/ios-native/`](legacy/ios-native/) as the behavior spec. |
>
> The Flutter scaffold lands once Tasks #3–#4 of the migration plan are done.
> See [docs/](docs/) for the public/brand pages (App Store + support site).

## Legacy iOS app — `legacy/ios-native/`

The native SwiftUI implementation that shipped as Leyne v1.0 on the App Store.
Kept verbatim as:

1. **The behavior spec** for the Flutter port — ETA rounding, search
   variants, pin/reorder UX, route polyline rendering all match this code.
2. **A future starting point** for iOS-only features (Live Activity,
   Home-screen widget, CarPlay) once Flutter parity ships on Android. These
   come back via Flutter `MethodChannel` → existing Swift code.

### Build the legacy iOS app

This Mac has Xcode 26 installed. The Flutter toolchain set the active
developer dir to Xcode already; if not:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Then:

```sh
xcodebuild -project legacy/ios-native/Lyne.xcodeproj -scheme Lyne \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Tests (unit + live LTA integration):

```sh
xcodebuild test -project legacy/ios-native/Lyne.xcodeproj -scheme Lyne \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Last verified green: 15/15 on Xcode 26.4.1 / iOS 18 simulator with live LTA
DataMall data.

## Live data (LTA DataMall)

No mock data — everything comes from LTA DataMall:

- **Bus Arrival v3** — live ETA / load / type / WAB / position per stop,
  refreshed ~25 s; `<1 min` → "Arr".
- **Bus Stops** — full SG dataset, disk-cached weekly. Powers Nearby
  (device GPS + haversine) and Stop search.
- **Bus Services** — service search.
- **Bus Routes** — ordered route stops for the Detail map (lazy,
  disk-cached).
- API key + base URL: `legacy/ios-native/Lyne/LTAConfig.swift` today; the
  Flutter port moves the key to `--dart-define` and never commits it.

## What ships on iOS today

- Launch animation, 5-step onboarding (first-run gated).
- Home: pinned stops (persisted, start empty), long-press reorder, ✎ to
  rename, 3-service cap with "+N more", arriving-bus highlight, live
  countdown, pull-to-refresh, Add-a-stop sheet.
- Nearby: live nearest stops via GPS + LTA Bus Stops, sortable
  (Distance / Arrival / Service), expand for live arrivals.
- Detail: stop overview → bus → MapKit map (route polyline + stop pins +
  live bus position) + Start Live Activity.
- Live Activity: full lock-screen takeover, real countdown from live ETA.
- Search: Conservative & Ambitious variants with persisted recents.
- Settings: theme follow-system, sound/haptics, search style, replays.
- Light & dark themes, sensory feedback (audio + Core Haptics).

## Running the Flutter app

The two required secrets — LTA DataMall key and Google Maps Android key —
are **not committed**. Wire them locally once:

```sh
# ~/.zshrc (or ~/.bashrc)
export LTA_API_KEY='+6zJ3XstTqOcDkvczHttWA=='     # from LTA DataMall
export MAPS_API_KEY='AIza…'                        # Google Cloud → Maps SDK for Android
```

Then:

```sh
# iOS Simulator
open -a Simulator
flutter run -d "iPhone 17 Pro" --dart-define=LTA_API_KEY=$LTA_API_KEY

# Android
flutter emulators --launch <your-avd>
flutter run --dart-define=LTA_API_KEY=$LTA_API_KEY
```

Maps API key is consumed at build time by `android/app/build.gradle.kts` via
`System.getenv("MAPS_API_KEY")`; nothing more to pass on the command line.
Apple Maps on iOS needs no key.

For an IDE run config (VS Code / Android Studio), set the `--dart-define`
arg in the launch settings so you don't retype it each session.

## AdMob: which unit ID gets requested

The banner ad's unit ID flips on an **explicit build-time flag**, not on
`kDebugMode`, because TestFlight and Play Internal are *release* builds —
a `kDebugMode` gate would silently serve real ads to internal testers.

| Distribution channel | Build command | Unit ID requested |
|---|---|---|
| **Local `flutter run` (debug)** | `flutter run …` | Production unit. iOS Simulator / Android Emulator are auto-detected as test devices by the SDK, so you still see "Test Ad" creatives — never a real impression. |
| **TestFlight (iOS internal beta)** | `flutter build ios --release --dart-define=LYNE_ADS_TEST=true --dart-define=LTA_API_KEY=$LTA_API_KEY` | Google's universal test unit. Testers always see "Test Ad". Zero AdMob policy risk. |
| **Play Console Internal / Closed testing** | `flutter build appbundle --release --dart-define=LYNE_ADS_TEST=true --dart-define=LTA_API_KEY=$LTA_API_KEY` | Same — test unit. |
| **App Store (public release)** | `flutter build ios --release --dart-define=LTA_API_KEY=$LTA_API_KEY` *(no LYNE_ADS_TEST flag)* | Production unit `ca-app-pub-5864511655536507/8034707188`. Real ads, real revenue. |
| **Play Store (public release)** | `flutter build appbundle --release --dart-define=LTA_API_KEY=$LTA_API_KEY` | Same — production unit. |

The flag is `LYNE_ADS_TEST=true`. Omit it for production. The default
is **production**, so accidentally forgetting the flag on a public
release just means real ads — not the safer-but-worse failure mode of
accidentally shipping test ads to the App Store.

If you want a physical dev iPhone to see test ads against the
production unit (option 2 — "validate the production unit serves
without earning real impressions"), paste its hash into
`kTestDeviceIdentifiers` at the top of `lib/services/ad_consent.dart`.
The hash gets printed to the Xcode/`flutter run` console on the
device's first ad request.

## Deep links

The app handles two URL shapes:

| Path | Action |
|---|---|
| `lyne.sg/stop/{code}` | Open Detail for that stop |
| `lyne.sg/stop/{code}/{busNo}` | Open Detail drilled into a specific service |
| `lyne.sg/service/{busNo}` | Resolve origin stop, open Detail there |

**Testing without hosting anything** — the custom `lyne://` scheme is
wired on both platforms, so a Safari/Chrome address-bar tap works:

```
lyne://stop/83139
lyne://service/15
```

**Production Universal Links / App Links** require hosting two files at
`https://lyne.sg/.well-known/`:

- `apple-app-site-association` (no `.json` extension, served as
  `application/json`) — for iOS Universal Links. Plus enable
  "Associated Domains" capability on the Runner target in Xcode; the
  `ios/Runner/Runner.entitlements` file is already set up with
  `applinks:lyne.sg`.
- `assetlinks.json` — for Android App Links. The AndroidManifest
  intent-filter has `android:autoVerify="true"` already.

Format for both is documented at
[branch.io's universal links guide](https://help.branch.io/developers-hub/docs/ios-app-site-association-file)
and [developer.android.com App Links guide](https://developer.android.com/training/app-links/verify-android-applinks).

## Flutter migration

Migration plan, deferred iOS-only features, and task tracking live in
Claude's project memory. High-level port order:

1. ~~Install Flutter toolchain~~ ✅
2. ~~Move Swift to `legacy/ios-native/`~~ ✅
3. ~~Scaffold Flutter at repo root~~ ✅
4. ~~Wire pubspec + platform manifests~~ ✅
5. ~~Port LTA data layer to Dart~~ ✅
6. ~~Skeleton screens + bottom tab bar~~ ✅
7. ~~Home + Nearby with live data~~ ✅
8. ~~Detail screen with split map (Apple Maps iOS / Google Maps Android)~~ ✅
9. ~~Search + Settings~~ ✅
10. ~~AdMob + ATT consent~~ ✅
11. ~~Universal Links / App Links~~ ✅
12. *(Deferred — post-Android-launch)* Re-add Live Activity + Widget on
    iOS via MethodChannel, reusing Swift code from `legacy/`.

## Implementation notes (legacy)

- **Fonts:** legacy iOS uses system monospaced (SF Mono) in place of
  JetBrains Mono. Flutter port will inherit the same.
- **Launch-argument seam:** `-lyne.onboarded 1`, `-lyne.startTab nearby`,
  `-lyne.theme dark` via NSArgumentDomain.
- **PrivacyInfo.xcprivacy** at `legacy/ios-native/Lyne/PrivacyInfo.xcprivacy`
  is the iOS privacy manifest; Flutter iOS build will re-add it. Android
  uses the Play Console Data Safety form (filled in console).
