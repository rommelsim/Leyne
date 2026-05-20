# Leyne

Live Singapore bus arrival times — pin your stops, glance at the next bus.
Powered by [LTA DataMall](https://datamall.lta.gov.sg/).

> **Repo status (May 2026):** the Flutter rewrite targeting iOS + Android
> has landed. All 11 ready migration tasks complete; one task
> (re-adding Live Activity via MethodChannel) is deferred until after
> Android ships.
>
> | Branch | What it is |
> |---|---|
> | `main` | Shipping iOS-native app (SwiftUI, App Store v1.0). Frozen. |
> | `flutter-dev` | **This branch.** Cross-platform Flutter build. iOS code preserved under [`legacy/ios-native/`](legacy/ios-native/) as the behavior spec and a future starting point for the Live Activity bridge. |

---

## Quick start — daily development

### 1. One-time setup (already done if you've been working in this repo)

```sh
# ~/.zshrc
export LYNE_DIR="$HOME/Desktop/Lyne/Lyne"
export LTA_API_KEY='+6zJ3XstTqOcDkvczHttWA=='     # from LTA DataMall
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"   # adb on PATH
```

> The Detail screen's map uses Apple Maps on iOS and OpenStreetMap (via
> `flutter_map`) on Android — both free, no key, no billing required.

`flutter doctor` should show ✓ for both iOS and Android. Reload with
`source ~/.zshrc`.

### 2. Run commands (debug mode + hot reload)

```sh
cd "$LYNE_DIR"

# iPhone (Rommel's iPhone, UDID hard-coded for reliability)
flutter run -d 00008150-0011248E0C88401C \
  --dart-define=LTA_API_KEY=$LTA_API_KEY \
  --dart-define=LYNE_ADS_TEST=true

# Android (Galaxy S24 Ultra)
flutter run -d R5CX209EPSZ \
  --dart-define=LTA_API_KEY=$LTA_API_KEY \
  --dart-define=LYNE_ADS_TEST=true

# iOS Simulator (no physical device needed)
open -a Simulator
flutter run -d "iPhone 17" \
  --dart-define=LTA_API_KEY=$LTA_API_KEY \
  --dart-define=LYNE_ADS_TEST=true
```

> The `LYNE_ADS_TEST=true` flag forces Google's universal test banner
> unit so dev never accidentally hits the production ad slot. See the
> [AdMob matrix](#admob-which-unit-id-gets-requested) below for which
> flag combos to use for TestFlight vs App Store.
>
> No `MAPS_API_KEY` is needed — Android uses OpenStreetMap, iOS uses
> Apple Maps. Both are free with no setup.

### 3. Optional — shell aliases

To avoid retyping:

```sh
# ~/.zshrc
alias leyne-iphone="cd \$LYNE_DIR && flutter run -d 00008150-0011248E0C88401C --dart-define=LTA_API_KEY=\$LTA_API_KEY --dart-define=LYNE_ADS_TEST=true"
alias leyne-android="cd \$LYNE_DIR && flutter run -d R5CX209EPSZ --dart-define=LTA_API_KEY=\$LTA_API_KEY --dart-define=LYNE_ADS_TEST=true"
alias leyne-sim="cd \$LYNE_DIR && open -a Simulator && sleep 3 && flutter run -d 'iPhone 17' --dart-define=LTA_API_KEY=\$LTA_API_KEY --dart-define=LYNE_ADS_TEST=true"
```

Then just `leyne-iphone`, `leyne-android`, or `leyne-sim`.

### 4. Hot reload keys (while `flutter run` is attached)

| Key | Action |
|---|---|
| `r` | Hot reload — apply Dart changes in <1s, app state preserved |
| `R` | Hot restart — re-runs `main()` (use after pubspec / native code changes) |
| `q` | Quit |
| `h` | Show all interactive command keys |
| `o` | Open DevTools (timeline, widget inspector, memory, network) in browser |
| `p` | Toggle widget paint bounds overlay (visual layout debugging) |
| `P` | Toggle performance overlay (frame rate graph) |

---

## Run on a fresh physical device (one-time setup)

### iPhone

1. **iPhone: Settings → Privacy & Security → Developer Mode → On** (reboot when prompted)
2. Plug in via USB-C → on the iPhone tap **Trust This Computer**
3. `open ios/Runner.xcworkspace` (use the workspace, NOT `Runner.xcodeproj`)
4. Xcode → Runner → Signing & Capabilities → check **Automatically manage signing**, pick Team `JFQKT254NR`
5. Same screen → **+ Capability → Associated Domains** (one click; wires up `applinks:lyne.sg`)
6. Close Xcode → `flutter devices` to find the UDID → use it in the `flutter run -d <udid>` command above
7. First launch: iOS says "Untrusted Developer" — Settings → General → VPN & Device Management → tap profile → **Trust**

### Android

1. **Phone: Settings → About phone → Build number (tap 7×)** to enable Developer options
2. **Developer options → USB debugging → On**
3. Plug in via USB → on the phone tap **Allow USB debugging** with **Always allow from this computer**
4. `adb devices` should show your phone as `device` (not `unauthorized` or `offline`)
5. `flutter devices` to find the serial → use it in the `flutter run -d <serial>` command above

---

## Build for distribution

| Channel | Command | Notes |
|---|---|---|
| **TestFlight (iOS beta)** | `flutter build ios --release --dart-define=LTA_API_KEY=$LTA_API_KEY --dart-define=LYNE_ADS_TEST=true` | The `LYNE_ADS_TEST=true` flag is **critical** — without it, internal testers would see real ads. |
| **Play Console Internal/Closed testing** | `flutter build appbundle --release --dart-define=LTA_API_KEY=$LTA_API_KEY --dart-define=LYNE_ADS_TEST=true` | Same — test unit. Upload the `.aab` from `build/app/outputs/bundle/release/`. |
| **App Store (public release)** | `flutter build ios --release --dart-define=LTA_API_KEY=$LTA_API_KEY` | **No** `LYNE_ADS_TEST` flag → production unit serves real ads. Archive in Xcode → Distribute → App Store Connect. |
| **Play Store (public release)** | `flutter build appbundle --release --dart-define=LTA_API_KEY=$LTA_API_KEY` | Same — production unit. Upload `.aab`. |

---

## AdMob: which unit ID gets requested

The banner ad unit flips on an **explicit build-time flag**, not on
`kDebugMode`. TestFlight and Play Internal are *release* builds — a
`kDebugMode` gate would silently serve real ads to internal testers.
**Wrong default.**

- `LYNE_ADS_TEST=true` → Google's universal test unit. "Test Ad"
  creative, zero policy risk.
- (no flag) → production unit
  `ca-app-pub-5864511655536507/8034707188`. Real ads, real revenue.

The default is **production**, so accidentally forgetting the flag on
a public release just means real ads — not the worse failure mode of
accidentally shipping test ads.

**App ID** (used by the SDK at init time, set in `Info.plist` +
`AndroidManifest.xml`): `ca-app-pub-5864511655536507~6330743279`. Same
on both platforms.

**To validate the production unit without earning real impressions** —
add the device's AdMob test hash to `kTestDeviceIdentifiers` at the
top of `lib/services/ad_consent.dart`. The hash gets printed to the
Xcode / `flutter run` console on the device's first ad request, e.g.:

```
<Google> To get test ads on this device, set:
GADMobileAds.sharedInstance.requestConfiguration.testDeviceIdentifiers = @[ @"abc123..." ];
```

Rommel's iPhone (`65e887acf5c73093fbe2212071d84b64`) is already in the
list. iOS Simulator + Android Emulator are auto-detected as test
devices — no need to add their hashes.

---

## Live data (LTA DataMall)

No mock data — everything comes from LTA DataMall:

- **Bus Arrival v3** — live ETA / load / type / WAB / position per stop,
  refreshed ~25 s; `<1 min` → "Arr".
- **Bus Stops** — full SG dataset, disk-cached weekly. Powers Nearby
  (device GPS + haversine) and Stop search.
- **Bus Services** — service search.
- **Bus Routes** — ordered route stops for the Detail map (lazy,
  disk-cached).

API key wiring: never committed — pass via `--dart-define=LTA_API_KEY=…`
at build/run. The data layer also retries 5xx responses with 2s+4s
backoff and caps parallel pagination at 4 to stay under LTA's
maxBurstMessageCount=4 spike-arrest policy.

---

## Privacy / policy disclosures

Each store has two layers of disclosure: declarations bundled inside
the app binary (covered in code), and forms in the developer console
(filled outside the repo).

### In the app — already wired

| File | What it declares |
|---|---|
| `ios/Runner/Info.plist` → `NSLocationWhenInUseUsageDescription` | "Leyne uses your location to show nearby bus stops and accurate arrival times." |
| `ios/Runner/Info.plist` → `NSUserTrackingUsageDescription` | The ATT prompt copy: "Leyne uses your device identifier to show ads relevant to you and to keep the app free." |
| `ios/Runner/Info.plist` → `SKAdNetworkItems` | 50 SKAdNetwork IDs for AdMob attribution (copied verbatim from legacy iOS). |
| **`ios/Runner/PrivacyInfo.xcprivacy`** | **iOS Privacy Manifest, required since May 2024.** Declares: tracking=false at app level (Google Mobile Ads SDK ships its own manifest declaring tracking=true with its tracking domains, and Apple aggregates); collected data = Device ID + Advertising Data (linked, tracking, for third-party ads) + Precise Location (not linked, not tracking, app-functionality); API access = NSUserDefaults (CA92.1 — shared_preferences). |
| `android/.../AndroidManifest.xml` → `INTERNET`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` | Network + GPS permissions. |
| `android/.../AndroidManifest.xml` → `com.google.android.gms.permission.AD_ID` | Required for AdMob to read the Advertising ID on Android 13+ (API 33+). |

> **iOS one-time setup:** the `PrivacyInfo.xcprivacy` file exists on
> disk but Xcode needs a file reference. Open
> `ios/Runner.xcworkspace`, drag `PrivacyInfo.xcprivacy` from Finder
> into the **Runner** group in Xcode's left sidebar, and tick **Runner**
> under "Add to targets" when prompted. Done once — survives
> subsequent `flutter clean` + `pod install`.

### In the developer consoles — needs to be filled before submission

**App Store Connect → Leyne → App Privacy:**

| Data type | Linked to user? | Used for tracking? | Purposes |
|---|---|---|---|
| Precise Location | No | No | App Functionality (Nearby ranks stops by walking distance) |
| Device ID | Yes | **Yes** | Third-Party Advertising (IDFA via AdMob, gated by ATT prompt) |
| Other Diagnostic Data | Yes | Yes | Third-Party Advertising (ad measurement / fill data via AdMob) |

These must match what `PrivacyInfo.xcprivacy` declares. App Store
review rejects mismatches.

**Play Console → Leyne → App content → Data Safety:**

| Data type | Collected? | Shared with third parties? | Purpose | Required? |
|---|---|---|---|---|
| Location → Approximate | Yes | No | App functionality | Required to opt out (location use is core to Nearby) |
| Location → Precise | Yes | No | App functionality | Same |
| Device or other IDs (Advertising ID) | Yes | **Yes (Google AdMob)** | Advertising / marketing | Optional — user can withhold via OS settings |
| App activity / interactions / search history | No | — | — | — |
| Personal info / financial info / health / contacts | No | — | — | — |

Also declare:
- **Data encrypted in transit:** Yes (HTTPS-only — LTA + AdMob)
- **Users can request data deletion:** Yes (uninstall = delete; no
  server-side data)

### Privacy policy URL — needs to be hosted

Both stores require a publicly accessible privacy policy URL. The
text already exists at `docs/privacy.md` + `docs/privacy.html` in this
repo — needs to be hosted somewhere stable (e.g. `lyne.sg/privacy`,
GitHub Pages on the repo's docs folder, or any static host) and the
URL pasted into:
- App Store Connect → Leyne → App Information → Privacy Policy URL
- Play Console → Leyne → Store presence → Main store listing → Privacy Policy

If you change the policy after launch, update the hosted page; both
stores fetch the URL fresh on review.

---

## Deep links

The app handles three URL shapes:

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

Format references:
[Apple — Supporting Associated Domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains),
[Android App Links guide](https://developer.android.com/training/app-links/verify-android-applinks).

---

## Tests

```sh
cd "$LYNE_DIR"
flutter test
```

31 tests covering: ETA rounding, query-kind detection, haversine,
LTA date parsing, Load/Deck mapping, full BusArrival v3 JSON parsing
+ `toService` mapper, BusStops/Routes parsing, `journeySegment` edge
cases, `fmtDistance`, all AppModel pin-logic invariants (toggle
symmetric, unchecking last bus unpins, reorder preserves order,
persistence round-trip), plus a widget-shell smoke test.

---

## Project layout

```
.
├── lib/
│   ├── main.dart                       Entry — bootstrap, themes, navigatorKey
│   ├── theme.dart                      LyneTheme light + dark palettes
│   ├── data/
│   │   ├── geo.dart                    haversine + walk-minutes
│   │   ├── models.dart                 Service / Load / Deck / CardModel / fmtEta / fmtDistance
│   │   ├── search_logic.dart           detectQueryKind
│   │   ├── lta_models.dart             LTA DTOs + LtaDate.parse + toService mapper
│   │   ├── lta_service.dart            HTTP client, paginated fetch, disk cache
│   │   ├── lta_config.dart             API key seam (--dart-define), constants
│   │   └── data_store.dart             ChangeNotifier repository (bootstrap, nearby, arrivals, routes)
│   ├── state/
│   │   └── app_model.dart              Pins, recents, tracked, 1-second tick
│   ├── services/
│   │   ├── location_service.dart       Geolocator wrapper, permission state
│   │   ├── ad_consent.dart             UMP → ATT → MobileAds.initialize
│   │   └── deep_link_service.dart      app_links subscription → router
│   ├── widgets/
│   │   ├── eta_pill.dart               "3 min" / "Arr" pill
│   │   ├── service_row.dart            One service in a card or expanded list
│   │   ├── pinned_card.dart            Home card with tap-rename + 3+more
│   │   ├── route_map.dart              Apple Maps iOS / OpenStreetMap Android split
│   │   ├── route_progress.dart         Vertical timeline with tap-to-alight
│   │   └── ad_banner.dart              320×50 banner with consent gating
│   └── screens/
│       ├── root_scaffold.dart          Bottom NavigationBar, IndexedStack
│       ├── home_screen.dart            ReorderableListView of PinnedCards
│       ├── nearby_screen.dart          Permission prompt, sort chips, expandable rows
│       ├── search_screen.dart          Live search, dual sections, recents
│       ├── settings_screen.dart        Feedback toggles, About, theme note
│       └── detail_screen.dart          Stop overview + service drill-in
├── test/
│   ├── data_layer_test.dart            19 tests — ETA / parse / geo / journeySegment
│   ├── app_model_test.dart             11 tests — pin logic + persistence
│   └── widget_test.dart                1 test — shell smoke
├── ios/                                Runner Xcode project (workspace integrates Pods)
├── android/                            Gradle project + Manifest
├── docs/                               Public/brand pages (privacy, support, index)
└── legacy/ios-native/                  Frozen SwiftUI v1.0 — behavior spec + future bridge source
```

---

## Migration history

1. ~~Install Flutter toolchain~~ ✅
2. ~~Move Swift to `legacy/ios-native/`~~ ✅
3. ~~Scaffold Flutter at repo root~~ ✅
4. ~~Wire pubspec + platform manifests~~ ✅
5. ~~Port LTA data layer to Dart~~ ✅
6. ~~Skeleton screens + bottom tab bar~~ ✅
7. ~~Home + Nearby with live data~~ ✅
8. ~~Detail screen with split map (Apple Maps iOS / OpenStreetMap Android)~~ ✅
9. ~~Search + Settings~~ ✅
10. ~~AdMob + ATT consent~~ ✅
11. ~~Universal Links / App Links~~ ✅
12. *(Deferred — post-Android-launch)* Re-add Live Activity + Widget on
    iOS via MethodChannel, reusing Swift code from `legacy/`.

---

## Common gotchas

| Problem | Fix |
|---|---|
| `Module 'app_tracking_transparency' not found` in Xcode | You opened `Runner.xcodeproj` instead of `Runner.xcworkspace`. Quit Xcode, `rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-*`, open `Runner.xcworkspace`. |
| `LTA_API_KEY is empty` warning at app launch | You ran from Xcode's ⌘R button. Xcode doesn't pass `--dart-define`. Use `flutter run` from terminal instead. |
| `No supported devices found with name or id matching 'Rommel's iPhone'` | The device name uses a curly apostrophe `’`. Use the UDID instead of the name. |
| Android map tiles grey / not loading | OSM tile server transient outage or no network. The bus stop pin + bus marker + polyline still draw on the empty canvas. Pull data via wifi and rebuild if persistent. |
| "Account not approved yet" in ad banner logs | AdMob is still verifying your account identity. Takes 1–7 business days. Until then, use `LYNE_ADS_TEST=true` to see the test creative. |
| App lands but Home shows "Couldn't load live data — LTA returned HTTP 500" | LTA DataMall transient outage (their server). Wait a few seconds and tap Retry. The data layer auto-retries 3× with 2s+4s backoff before surfacing this. |
| Android disk cache "Couldn't resolve native function 'DOBJC_initializeApi'" | iOS Simulator-only bug in `path_provider`. Doesn't affect real devices. Cosmetic — disk cache silently re-fetches from network. |
| `flutter clean` followed by pod install fails: "Generated.xcconfig must exist" | Run `flutter pub get` between them — it regenerates the file Podfile expects. |

---

## Legacy iOS app — `legacy/ios-native/`

The native SwiftUI implementation that shipped as Leyne v1.0 on the
App Store. Kept verbatim as:

1. **The behavior spec** for the Flutter port — ETA rounding, search
   variants, pin/reorder UX, route polyline rendering all match this code.
2. **A future starting point** for iOS-only features (Live Activity,
   Home-screen widget, CarPlay) once Flutter parity ships on Android.
   These come back via Flutter `MethodChannel` → existing Swift code.

### Build the legacy iOS app (for reference)

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -project legacy/ios-native/Lyne.xcodeproj -scheme Lyne \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Tests (unit + live LTA integration):

```sh
xcodebuild test -project legacy/ios-native/Lyne.xcodeproj -scheme Lyne \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Last verified green: 15/15 on Xcode 26.4.1 / iOS 18 simulator with
live LTA DataMall data.

### Implementation notes

- **Fonts:** legacy iOS uses system monospaced (SF Mono) in place of
  JetBrains Mono. Flutter port inherits the same.
- **Launch-argument seam:** `-lyne.onboarded 1`, `-lyne.startTab nearby`,
  `-lyne.theme dark` via `NSArgumentDomain`.
- **`PrivacyInfo.xcprivacy`** at `legacy/ios-native/Lyne/PrivacyInfo.xcprivacy`
  is the iOS privacy manifest; Flutter iOS build will re-add it for the
  App Store submission. Android uses the Play Console Data Safety form
  (filled in console, not in repo).
</content>
