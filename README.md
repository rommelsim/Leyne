# Leyne — ships as **Departly**

Live Singapore bus and MRT arrivals — save your stops, watch your bus move
along its route, get a nudge one stop before yours.
Powered by [LTA DataMall](https://datamall.lta.gov.sg/).

> **Repo status (July 2026):** two native apps, one repo.
>
> | App | Where | Stack / design |
> |---|---|---|
> | **iOS** | [`ios-native/`](ios-native/) | Native SwiftUI ("WhereSia" departure-board design, Liquid Glass) + `LeyneWidgets` extension (widgets, Live Activity) |
> | **Android** | repo root (`lib/`) | Flutter, Material 3 / Material You (`lib/screens/v2/soft_*`) |
>
> The public, on-device, store-listing name is **Departly** (renamed
> 2026-07-04). The repo, bundle IDs (`com.leyne.leyne` / `com.leyne.Leyne`),
> and internal code names keep **Leyne**; the iOS design module keeps
> **WhereSia** (`WS*` types). `main` is the shipping branch; active design
> work happens on feature branches (currently `design-remake`).
>
> History: v1.0 shipped as native SwiftUI (frozen at
> [`legacy/ios-native/`](legacy/ios-native/)), was rewritten in Flutter for
> the Android launch, then iOS was rewritten *back* to native SwiftUI at
> [`ios-native/`](ios-native/). Flutter now ships Android only — there is no
> `ios/` runner anymore.

---

## Quick start

### Android (Flutter, repo root)

```sh
# ~/.zshrc (one-time)
export LTA_API_KEY='+6zJ3XstTqOcDkvczHttWA=='   # from LTA DataMall
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"

# Run on the Galaxy S24 Ultra with hot reload (test ads forced)
flutter run -d R5CX209EPSZ \
  --dart-define=LTA_API_KEY=$LTA_API_KEY \
  --dart-define=LYNE_ADS_TEST=true
```

Hot-reload keys while attached: `r` reload · `R` restart · `o` DevTools ·
`p` paint bounds · `q` quit.

Fresh device one-time setup: enable Developer options (tap Build number
7×) → USB debugging → `adb devices` shows `device` → `flutter devices`
for the serial.

### iOS (native SwiftUI, `ios-native/`)

```sh
open ios-native/Leyne.xcodeproj
```

Run with ⌘R (Debug builds serve Google's test ad unit automatically).
The LTA API key seam lives in `ios-native/Leyne/LTAConfig.swift`.
Simulator builds from the CLI:

```sh
xcodebuild -project ios-native/Leyne.xcodeproj -scheme Leyne \
  -destination 'generic/platform=iOS Simulator' build
```

---

## Building for distribution + AdMob

**See [`BUILDING.md`](BUILDING.md)** — it is the canonical reference for
which build mode serves which AdMob unit. The one rule that matters:

- **Android closed testing:** `./scripts/build-android-closed-test.sh`
  (forces the test unit — a plain release AAB would serve real ads to
  testers, an AdMob policy risk).
- **Android production:** `./scripts/build-android-prod.sh`.
- **iOS TestFlight vs App Store:** same Archive, so flip
  `forceTestUnitForRelease` in `ios-native/Leyne/AdBanner.swift`
  (`true` for TestFlight, `false` for App Store) — details in BUILDING.md.

**Every build updates the changelog** — `CHANGELOG.md` at the repo root,
plus the user-facing What's New (`kChangelog` in
`ios-native/Leyne/AppModel.swift`, `lib/data/changelog.dart`).

---

## Live data (LTA DataMall)

No mock data — everything comes from LTA DataMall:

- **Bus Arrival v3** — live ETA / load / type / WAB / position per stop,
  refreshed ~25 s; `<1 min` → "Arr"/ARRIVING.
- **Bus Stops / Services / Routes** — full SG dataset, disk-cached; powers
  Nearby (GPS + haversine), search, and the route timeline.
- **PCDRealTime** — live MRT station crowd levels.
- **PCDForecast** — today's station crowd forecast (half-hour slots; the
  windowing logic lives in `lib/data/forecast_window.dart` and mirrors
  `WSMrtStationView.swift`).
- **TrainServiceAlerts + FacilitiesMaintenance v2** — line status and
  station lift outages for the Alerts tab.

API key wiring: never committed — `--dart-define=LTA_API_KEY=…` on
Android, `LTAConfig.swift` on iOS. The data layer retries 5xx with
2s+4s backoff and caps parallel pagination at 4 (LTA's
maxBurstMessageCount=4 spike-arrest policy).

Platform note: the Android bus view intentionally has **no map** (owner
decision 2026-06-08); iOS keeps native MapKit.

---

## Features (shipping)

3-tab structure on both platforms — **Home (Nearby) · Saved · Alerts** —
plus search (stop / bus / MRT / postal code), MRT station screens with
live crowd + forecast, route tracking with "Alert me 1 stop before",
two-tier arrival notifications, Home Screen widgets on both platforms
(iOS: Pinned Stop / Nearby / Favourite Service; Android: Stop / Nearby,
Glance), and on iOS a route-progress Live Activity with Dynamic Island.
Design is platform-native by rule: iOS Liquid Glass, Android Material
You incl. dynamic colour — feature parity, no idiom bleed.

---

## Tests

```sh
flutter test        # Android/Dart — 227 tests
xcodebuild test -project ios-native/Leyne.xcodeproj -scheme Leyne \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'   # iOS
```

Flutter suite covers the data layer (LTA parsing, ETA rounding, geo,
forecast windowing), pin/AppModel invariants, and UI behavior tests for
the v2 screens (onboarding flow, route timeline taps, etc.).

---

## Project layout

```
.
├── lib/                        Flutter app (ANDROID ONLY)
│   ├── data/                   LTA client, models, DataStore, forecast window
│   ├── state/                  AppModel (pins, tracked, tick)
│   ├── services/               location, ads (banner/interstitial/app-open), deep links
│   ├── widgets/                shared widgets + v2/ components
│   └── screens/
│       ├── onboarding_screen.dart · launch_screen.dart · whats_new_screen.dart
│       └── v2/                 soft_* Material 3 screens (root, home, stop, bus,
│                               search, MRT line/station/map, alerts, settings…)
├── android/                    Gradle project, Glance widgets, launcher icons
├── ios-native/                 Native SwiftUI iOS app (SHIPPING)
│   ├── Leyne/                  app target; WhereSia/ design module (WS* views)
│   ├── LeyneWidgets/           widgets + Live Activity extension
│   └── LeyneTests/
├── assets/                     app data + icon sources (assets/icon/src/ = pin-clock SVGs)
├── docs/                       GitHub Pages site (index/support/privacy) + playbooks
│                               (aso.md, BUILDING is at repo root, analytics, specs)
├── scripts/                    build-android-*.sh, store-frame + icon generators
├── test/                       Flutter test suite
└── legacy/ios-native/          Frozen SwiftUI v1.0 — historical reference
```

---

## Deep links

| Path | Action |
|---|---|
| `lyne.sg/stop/{code}` | Open that stop |
| `lyne.sg/stop/{code}/{busNo}` | Open a specific service at the stop |
| `lyne.sg/service/{busNo}` | Resolve origin stop, open there |

The custom `lyne://` scheme (e.g. `lyne://stop/83139`) works without any
hosting on both platforms. Production Universal Links / App Links need
`apple-app-site-association` + `assetlinks.json` hosted at
`https://lyne.sg/.well-known/` (entitlements + `autoVerify` intent filter
are already wired).

---

## Store & privacy

- **Store metadata playbook:** [`docs/aso.md`](docs/aso.md) — paste-ready
  Departly name/subtitle/keywords/description for both stores, screenshot
  order + captions.
- **Public pages** (GitHub Pages from `docs/` on `main`):
  [index](https://rommelsim.github.io/Leyne/) ·
  [support](https://rommelsim.github.io/Leyne/support.html) ·
  [privacy](https://rommelsim.github.io/Leyne/privacy.html)
- **iOS privacy manifest:** `ios-native/Leyne/PrivacyInfo.xcprivacy` —
  tracking=false at app level; AdMob's SDK manifest declares its own
  tracking. App Store Connect App Privacy answers and the Play Data
  Safety form must match it (Location = app functionality, not linked;
  Device ID / Advertising = third-party ads, gated by ATT / AD_ID).
- Ads are AdMob under leyne0000@gmail.com (`pub-5864511655536507`);
  consent = Google UMP + ATT on iOS. Plus a Stripe "Buy me a coffee"
  donation link on iOS.

---

## Common gotchas

| Problem | Fix |
|---|---|
| `No supported devices found … 'Rommel's iPhone'` | The device name uses a curly apostrophe `’`. Use the UDID instead. |
| Home shows "Couldn't load live data — LTA returned HTTP 500" | LTA DataMall transient outage. The data layer auto-retries 3× with backoff; tap Retry. |
| Testers would see real ads | Wrong build mode — use `./scripts/build-android-closed-test.sh` / flip `forceTestUnitForRelease`. See BUILDING.md. |
| Ad banner logs "Account not approved yet" | AdMob identity verification (1–7 business days). Use test units meanwhile. |
| `flutter clean` → Android build fails on missing generated files | Run `flutter pub get` in between. |
| BACK button exits the Android app from a pushed screen | OnBackInvoked / `setFrameworkHandlesBack` signal issue — verify on a real device via logcat, not just widget tests (see 2.8.4 fix notes). |
| iOS build number ahead of git | Xcode archives bump the build number without committing — expected drift. |

---

## Legacy iOS app — `legacy/ios-native/`

The original SwiftUI v1.0 that shipped to the App Store, kept frozen as a
historical reference. It has been fully superseded by `ios-native/` (the
current native app) — nothing new should reference it. The behavior spec
role it once played for the Flutter port is over; today **iOS is the
source of truth and Android mirrors it** (see `.claude/skills/parity-audit`
and `port-ios-feature`).
