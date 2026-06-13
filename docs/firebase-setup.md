# Firebase setup — unblock DAU/retention measurement (Phase 0)

**Why:** the app currently has ZERO analytics or crash reporting (confirmed by
code inspection — no Firebase/GA/Crashlytics/Sentry on either platform). You
can't grow DAU you can't see. This is a ~1-day wiring job, but it needs config
files only you can generate. Do the **console steps below**, drop the two files
in, and I'll wire the SDKs + events + ad-revenue attribution.

App identifiers (you'll need these in the console):
- **iOS bundle ID:** `com.leyne.Leyne`
- **Android package:** `com.leyne.leyne`

---

## What YOU do (console, ~15 min)

1. Go to <https://console.firebase.google.com> → **Add project** (name it
   "Leyne"). Enable Google Analytics when prompted (free).
2. **Add an iOS app** → bundle ID `com.leyne.Leyne` → download
   **`GoogleService-Info.plist`**. Send it to me / drop it at
   `ios-native/Leyne/GoogleService-Info.plist` (it'll be git-ignored).
3. **Add an Android app** → package `com.leyne.leyne` → download
   **`google-services.json`**. Drop it at `android/app/google-services.json`
   (git-ignored).
4. In Firebase → **Analytics → enable**. Then link **AdMob ↔ Firebase**: in the
   AdMob console (pub-5864511655536507) → app → "Link to Firebase", and enable
   **user metrics + Impression-Level Ad Revenue (ILRD)**. This is what lets us
   attribute ad revenue to user cohorts.
5. (Optional but recommended) enable **Crashlytics** and **Remote Config** in
   the Firebase console — both free, no extra setup on your side.

> The two config files are low-sensitivity but kept out of git for cleanliness —
> I'll add them to `.gitignore` and document where they live.

## What I do once the files are in (~1 day)

- Add SDKs: iOS SPM (`FirebaseAnalytics`, `FirebaseCrashlytics`), Flutter
  (`firebase_core`, `firebase_analytics`, `firebase_crashlytics`).
- `FirebaseApp.configure()` / `Firebase.initializeApp()` at launch.
- Instrument **7 high-signal events only** (not every tap):
  `app_open` (auto), `stop_viewed`, `alert_set`, `favourite_added`,
  `notification_tapped`, `search_performed`, `onboarding_completed`.
- Wire **ILRD**: add a `paidEventHandler` (iOS `AdBanner.swift` / `AppOpenAd`)
  and the Flutter `onPaidEvent` equivalent → logs `ad_impression` with value +
  currency, so AdMob revenue shows up per user segment.
- (Optional) **Remote Config** flags so we can A/B ad placements (MREC vs
  banner) and toggle features without an app update.

## What this unlocks
- Real DAU, D1/D7/D30 retention cohorts, and the install→pin→habit funnel.
- Revenue-per-cohort (are commuters who pin worth 3× casual users?).
- The data needed to decide the **backend** question — only build server push
  once D7 retention > 20% and DAU > ~500 (see growth review).

---

## Execution plan — confirmed 2026-06-14

**Decision:** full Phase 0 scope (Analytics + 7 events + ILRD + Crashlytics),
**iOS first**, Android in a follow-up.

### iOS manual steps (you, in Xcode — blocks everything else)
The Xcode project uses **file-system synchronized groups**, so:
- Dropping `GoogleService-Info.plist` into `ios-native/Leyne/` auto-adds it to
  the target — no "add to target" step.
- BUT any `.swift` file is auto-compiled too, so the **Firebase SPM package must
  be added before any wiring**, or the build breaks on `import FirebaseAnalytics`.

Steps:
1. Xcode → **File → Add Package Dependencies…** →
   `https://github.com/firebase/firebase-ios-sdk` → add products
   **FirebaseAnalytics** + **FirebaseCrashlytics** to the `Leyne` target.
2. Drop `GoogleService-Info.plist` into `ios-native/Leyne/`.
3. Tell Claude "package + plist are in" → wiring applied in one pass.

### iOS wiring map (Claude applies once package + plist exist)
- **New file** `Leyne/AnalyticsService.swift` — thin enum-based wrapper
  (`AnalyticsService.log(.stopViewed(...))`) + `record(adValue:currency:precision:)`
  for ILRD.
- `Leyne/LeyneApp.swift` — `FirebaseApp.configure()` at launch; the notification
  delegate (`didReceive response`) → `notification_tapped`.
- `Leyne/AppModel.swift` — central hub for `favourite_added`, `alert_set`,
  `onboarding_completed` at the model mutation points.
- `Leyne/V2/SoftStopView.swift` + `Leyne/SoftMrtStationView.swift` — `stop_viewed`
  on appear.
- `Leyne/V2/SoftSearchView.swift` — `search_performed` on submit.
- `Leyne/AdBanner.swift`, `AppOpenAd.swift`, `InterstitialAd.swift` —
  `paidEventHandler` → ILRD `ad_impression` (value + currency).
- `app_open` is auto-logged by Firebase; no code.

### AdMob app IDs to link in console (per-app "Link to Firebase" + ILRD)
- iOS  → `ca-app-pub-5864511655536507~6330743279`
- Android → `ca-app-pub-5864511655536507~5685985257`
