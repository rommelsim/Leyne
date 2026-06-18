# Android Home-Screen Widgets — Implementation Spec

**Status:** Not started. No `AppWidgetProvider`, no `home_widget` package, no widget XML layouts
exist in the repo as of 2026-06-18.

**iOS source of truth:**
- `ios-native/LeyneWidgets/LeyneStopWidget.swift`
- `ios-native/LeyneWidgets/LeyneNearbyWidget.swift`
- `ios-native/LeyneWidgets/LeyneFavServiceWidget.swift`
- `ios-native/LeyneWidgets/WidgetShared.swift` (palette, App Group readers, LTA client, shared atoms)

> Note: iOS `LeyneWidgetBundle` currently parks the three home-screen widgets and ships only
> `LeyneLiveActivity`. The widget code is complete and correct — they are simply commented-out in
> the bundle. This spec targets re-enabling parity on Android.

---

## 1. Scope & Parity

### 1.1 Widgets to ship

| Widget | iOS name | iOS sizes | Android sizes |
|---|---|---|---|
| Pinned Stop | `LeyneStopWidget` | Small / Medium / Large | 2×2 (small) / 4×2 (medium) |
| Nearest Stop | `LeyneNearbyWidget` | Small | 2×2 (small) |
| Favourite Service | `LeyneFavServiceWidget` | Medium | 4×2 (medium) |

**Live Activity (Lock Screen / Dynamic Island)** is out of scope. Android has no equivalent that
maps cleanly to a home-screen widget; the ongoing notification in `AppModel._refreshOngoing()` is
already the Android analog.

### 1.2 Per-widget content

#### Pinned Stop (small — 2×2)
Mirrors `SmallStopView` in `LeyneStopWidget.swift`:
- Stop name (header, single line)
- First service's bus number (large hero text)
- First service's ETA in minutes ("Arr" if ≤0) with "then Xm" follow-up
- "+N" chip for remaining services
- Tap → deep-link `lyne://stop/{stopCode}`

#### Pinned Stop (medium — 4×2)
Mirrors `MediumStopView`:
- Pin icon + stop name header, hairline divider
- Up to 3 service rows: ink-filled badge + bus number, ETA columns (eta1 / eta2 / eta3)
- "Arriving" row highlighted with a tinted background (`#EDEDED` light / `#242424` dark)
- "No live arrivals" empty state
- Tap → `lyne://stop/{stopCode}`

#### Pinned Stop configuration
iOS uses `AppIntentConfiguration` to let the user pick any pinned stop from a list. Android
equivalent: the widget's `onUpdate` reads the first pin by default; the user configures via the
standard `AppWidgetManager` `configure` Activity, which presents a list of pinned stops and stores
the chosen `stopCode` in `SharedPreferences` keyed by `appWidgetId`.

#### Nearest Stop (small — 2×2)
Mirrors `NearestWidgetView` in `LeyneNearbyWidget.swift`:
- "NEAREST STOP" eyebrow label + pin icon
- Stop name (bold, 2 lines max, scale-down for long names)
- "Stop XXXXX" stop code (secondary text)
- Tap → `lyne://stop/{stopCode}`
- No arrivals fetched here — the app pushes the nearest stop name + code; widget is static
- Empty state: "Open Leyne to find nearby stops"

#### Favourite Service (medium — 4×2)
Mirrors `FavWidgetView` in `LeyneFavServiceWidget.swift`:
- Header: ink-filled service badge + destination text + star icon
- Hairline divider + "NEAREST ARRIVAL" label
- Pin icon + stop name + hero ETA ("Arr" or "Xmin")
- Two follow-up arrival times ("then X min")
- Empty state: "Favourite a service in Leyne"
- Tap → `lyne://stop/{stopCode}` (or `lyne://service/{busNo}?stop={stopCode}`)

### 1.3 iOS features that do not translate directly

| iOS feature | Android adaptation |
|---|---|
| `WidgetKit` `TimelineProvider` — system pulls a full timeline and schedules redraws | `AppWidgetProvider.onUpdate()` + WorkManager periodic task; no automatic per-minute scheduling |
| `AppIntentConfiguration` — native picker in the system widget gallery | Custom `Activity` launched via `android:configure` in `AppWidgetProviderInfo` |
| `widgetAccentable()` — tinting for StandBy/Lock Screen | Not applicable on Android; ignore |
| `contentTransition(.numericText)` — animated digit countdown | Not possible in `RemoteViews`; use static text only |
| Large (2-stop commute layout) | Defer to a later pass; requires a 4×4 widget size and more configuration surface |
| Glance (Jetpack Compose for widgets) | **Recommended alternative to raw RemoteViews** — see §2.1 |

---

## 2. Architecture

### 2.1 Rendering: RemoteViews vs Glance

**Recommendation: Jetpack Glance** (`androidx.glance:glance-appwidget`).

Glance lets the widget UI be written in Kotlin with a Compose-like DSL instead of XML
`RemoteViews` inflated at the provider level. It handles dark/light theming, sizes, and
`ColorProvider` tokens natively, which maps more cleanly to the iOS palette in `WidgetShared.swift`.
Glance compiles down to `RemoteViews` under the hood; it does not require the main app to use
Compose (the Flutter engine is unaffected).

**Minimum requirement:** Glance requires `compileSdk 33`, `minSdk 21`. Both are already met by this
project (current `minSdk` is 21, `targetSdk`/`compileSdk` 34+).

Add to `android/app/build.gradle`:
```kotlin
implementation("androidx.glance:glance-appwidget:1.1.1")
implementation("androidx.glance:glance-material3:1.1.1")
```

### 2.2 Data bridge: `home_widget` package

Add to `pubspec.yaml`:
```yaml
home_widget: ^0.6.0
```

`home_widget` provides:
- `HomeWidget.saveWidgetData<T>(id, data)` — writes a key→value into a plugin-managed
  `SharedPreferences` file (`FlutterHomeWidgetPlugin_<package>`) that is readable from the
  Kotlin/Glance side via `HomeWidgetGlanceState` or directly via `Context.getSharedPreferences`.
- `HomeWidget.updateWidget(name: ...)` — sends `ACTION_APPWIDGET_UPDATE` to the named provider.
- `HomeWidget.widgetClicked` stream — fires in Dart when a widget tap deep-link arrives.
- Background callback (`HomeWidget.registerBackgroundCallback`) — for refresh-on-tap scenarios.

### 2.3 Kotlin provider layer

Three `GlanceAppWidget` subclasses (one per widget kind) + three `GlanceAppWidgetReceiver`
subclasses. Each receiver is registered in `AndroidManifest.xml` with a corresponding
`AppWidgetProviderInfo` XML.

### 2.4 Refresh strategy

```
Primary refresh: Dart side (AppModel._onTick every 1 s, or after a pin/fav mutation)
  → HomeWidget.saveWidgetData(...)
  → HomeWidget.updateWidget(...)
  → Kotlin GlanceAppWidget.update() re-reads data and re-renders RemoteViews
```

```
Backstop refresh: WorkManager periodic task "leyne.widgetRefresh"
  → runs every 15 min (minimum enforced by OS; actual cadence varies by Doze state)
  → calls LTA v3/BusArrival directly from Kotlin (no Dart runtime needed)
  → updates SharedPreferences + calls AppWidgetManager.updateAppWidget(...)
```

**Rate limit awareness:** LTA DataMall allows 10 000 calls/day per API key. Three widgets each
polling every 15 min = 288 calls/day maximum from WorkManager alone. The Dart-driven update path
is bounded by the app's existing 60 s arrival poll gate in `DataStore._fetchArrivals`. No
additional rate limit concern.

**Location for Nearest Stop:** The widget does NOT read GPS. The app pushes the resolved nearest
stop code + name via `home_widget` after each location fix (in `LocationService`) or each
`DataStore.updateNearby()` call. If the app has never been opened, the widget shows the empty
state.

---

## 3. Data Flow

### 3.1 Shared-preferences keys (Dart → Kotlin bridge)

All keys are written by Dart via `HomeWidget.saveWidgetData` and read by Kotlin via
`Context.getSharedPreferences("FlutterHomeWidgetPlugin_<package>", Context.MODE_PRIVATE)`.

| Key | Type | Source in Dart | Widget(s) that read it |
|---|---|---|---|
| `leyne.widget.pins` | `String` (JSON array) | `AppModel._pins` — persisted at `lyne.pins` | Pinned Stop |
| `leyne.widget.nearby` | `String` (JSON object) | `DataStore._nearby.first` | Nearest Stop |
| `leyne.widget.favs` | `String` (JSON array) | `AppModel._favServices` | Favourite Service |
| `leyne.widget.arrivals.<stopCode>` | `String` (JSON object) | `DataStore._arrivals[stopCode]` | Pinned Stop, Fav Service |

**Shape of `leyne.widget.pins`** (JSON array, mirrors `WPinnedStop` in iOS `WidgetShared.swift`):
```json
[{"code":"53061","name":"Bef Bishan Stn"},{"code":"53241","name":"Opp Blk 211"}]
```

**Shape of `leyne.widget.nearby`** (mirrors `WNearbyStop`):
```json
{"code":"83139","name":"Opp Blk 512","walkMin":3}
```

**Shape of `leyne.widget.favs`** (mirrors `WFavService` — destination resolved app-side):
```json
[{"no":"186","stopCode":"11389","stopName":"Farrer Rd Stn Exit B","dest":"St. Michael's Ter"}]
```

**Shape of `leyne.widget.arrivals.<stopCode>`** (condensed from `DataStore.servicesFor()`):
```json
{"fetchedAt":1718700000000,"rows":[
  {"no":"88","eta1":2,"eta2":9,"eta3":20,"mon1":true},
  {"no":"156","eta1":9,"eta2":19,"mon1":false}
]}
```
`mon1` = GPS-monitored (true) or scheduled-only (false). Maps to `WLTA.Row.mon1` in iOS.
`fetchedAt` = epoch ms for freshness labelling.

### 3.2 Push points in the Dart app lifecycle

| Event | Action |
|---|---|
| `AppModel.togglePin / reorderPins / rename` | Write `leyne.widget.pins` → `HomeWidget.updateWidget(LeyneStopWidgetReceiver)` |
| `AppModel.toggleFavService / reorderFavServices` | Write `leyne.widget.favs` → `HomeWidget.updateWidget(LeyneFavServiceWidgetReceiver)` |
| `DataStore.updateNearby()` (after location fix) | Write `leyne.widget.nearby` → `HomeWidget.updateWidget(LeyneNearbyWidgetReceiver)` |
| `DataStore._fetchArrivals(code)` resolves | Write `leyne.widget.arrivals.<code>` → `HomeWidget.updateWidget(...)` for widgets showing that stop |
| App cold start (`AppModel.load()` completes) | Write all three keys from persisted state + trigger full widget update |

### 3.3 Cold-start case

On first install or after a clear-data: all widget-data keys are absent. Each Glance widget checks
for the key's presence; if missing it renders the empty/prompt state (e.g. "Pin a stop in Leyne").
WorkManager fires its first refresh after the initial delay (approximately 15 min) and can hydrate
arrivals data even if the app is not opened — but pins/favs/nearby require the user to have opened
the app at least once.

### 3.4 Arrivals fetch from Kotlin (WorkManager path)

The WorkManager task calls `https://datamall2.mytransport.sg/ltaodataservice/v3/BusArrival` with
`BusStopCode={code}` and `AccountKey` read from `BuildConfig.LTA_API_KEY` (same key already used
in Dart via `LtaConfig`). Response parsing mirrors `WLTA.arrivals()` in `WidgetShared.swift`:
extract `ServiceNo`, `NextBus.EstimatedArrival`, `NextBus2.EstimatedArrival`, `NextBus3.EstimatedArrival`,
and `NextBus.Monitored`. Compute `eta = ceil((isoDate - now) / 60)`. Store as
`leyne.widget.arrivals.<code>`.

---

## 4. Deep Links

Widget taps must open the relevant screen in the app. The `lyne://` custom scheme is already
handled by `DeepLinkService` (see `lib/services/deep_link_service.dart`), which routes:

| URI | Destination |
|---|---|
| `lyne://stop/{stopCode}` | `SoftStopScreen(stopCode)` |
| `lyne://stop/{stopCode}/{busNo}` | `SoftStopScreen` + `SoftBusScreen` pushed on top |
| `lyne://service/{busNo}?stop={stopCode}` | Resolves origin then same pair |

### Widget tap → deep link mapping

| Widget | Tap target | URI |
|---|---|---|
| Pinned Stop (small/medium) | Whole widget | `lyne://stop/{stopCode}` |
| Nearest Stop | Whole widget | `lyne://stop/{stopCode}` (or `lyne://` root if no stop yet) |
| Favourite Service | Whole widget | `lyne://stop/{stopCode}` |

### Wiring in Glance (Kotlin)
```kotlin
// In the GlanceAppWidget's Content:
GlanceModifier.clickable(
    actionStartActivity<MainActivity>(
        actionParametersOf(UriIntentParameter to Uri.parse("lyne://stop/$stopCode"))
    )
)
```
`MainActivity` already handles the `lyne://` intent filter (declared in `AndroidManifest.xml`
lines 105-111). No additional intent filter is needed.

### HomeWidget tap callback (Dart)
When using `home_widget`'s `HomeWidget.widgetClicked`, it fires the URI as a Dart stream event and
`DeepLinkService` handles it via `_appLinks.uriLinkStream`. Ensure `DeepLinkService.start()` is
called before the first frame in `main.dart` (already done).

---

## 5. File-by-File Task List

All Kotlin paths are relative to `android/app/src/main/kotlin/com/leyne/leyne/`.
All XML paths are relative to `android/app/src/main/res/`.

### Gradle / pubspec

- [ ] **`pubspec.yaml`** — add `home_widget: ^0.6.0` under `dependencies`
- [ ] **`android/app/build.gradle.kts`** — add `implementation("androidx.glance:glance-appwidget:1.1.1")` and `implementation("androidx.glance:glance-material3:1.1.1")` under `dependencies`; add `buildConfigField("String", "LTA_API_KEY", "\"${System.getenv("LTA_API_KEY") ?: ""}\"")` in `defaultConfig`

### Widget provider info XML (widget metadata)

- [ ] **`xml/leyne_stop_widget_info.xml`** — `AppWidgetProviderInfo` for Pinned Stop: `minWidth="110dp"`, `minHeight="110dp"`, `targetCellWidth="2"`, `targetCellHeight="2"`, `maxResizeWidth="250dp"`, `maxResizeHeight="110dp"`, `resizeMode="horizontal"`, `updatePeriodMillis="0"` (WorkManager drives updates), `configure=".widget.StopPickerActivity"`, `widgetCategory="home_screen"`, `description="@string/widget_stop_desc"`, `previewImage="@drawable/widget_preview_stop"`
- [ ] **`xml/leyne_nearby_widget_info.xml`** — `AppWidgetProviderInfo` for Nearest Stop: `targetCellWidth="2"`, `targetCellHeight="2"`, `updatePeriodMillis="0"`, no `configure` activity
- [ ] **`xml/leyne_fav_widget_info.xml`** — `AppWidgetProviderInfo` for Favourite Service: `targetCellWidth="4"`, `targetCellHeight="2"`, `updatePeriodMillis="0"`, `configure=".widget.FavPickerActivity"`

### Kotlin — Glance widget implementations

- [ ] **`widget/LeyneWidgetTheme.kt`** — colour tokens mirroring `WidgetShared.swift` palette: `wBg` (`#FFFFFF` / `#1A1A1A`), `wFg` (`#111111` / `#FFFFFF`), `wDim` (fg @ 0.65 alpha), `wFaint` (fg @ 0.45 alpha), `wLine` (fg @ 0.10 alpha), `wLive` = `wFg`, `wLiveBg` (`#EDEDED` / `#242424`), `wOnLive` = inverse of `wFg`. Use `GlanceTheme` + `ColorProvider` for dynamic day/night.
- [ ] **`widget/WidgetDataRepository.kt`** — reads JSON keys from `home_widget`'s SharedPreferences file; deserialises `PinnedStop`, `NearbyStop`, `FavServiceItem`, `ArrivalRow` data classes; exposes `getPins()`, `getNearby()`, `getFavs()`, `getArrivals(stopCode)`. Also provides `getConfiguredStopCode(appWidgetId)` and `saveConfiguredStopCode(appWidgetId, stopCode)` for per-widget configuration.
- [ ] **`widget/LtaApiClient.kt`** — Kotlin HTTP client (OkHttp or `HttpURLConnection`) for `v3/BusArrival`; reads `BuildConfig.LTA_API_KEY`; returns `List<ArrivalRow>`; used by WorkManager task only (not from Glance `Content` — Glance cannot suspend on network in `provideGlance`). Mirrors `WLTA.arrivals()` in `WidgetShared.swift`.
- [ ] **`widget/WidgetRefreshWorker.kt`** — `CoroutineWorker` registered as `"leyne.widgetRefresh"` with `PeriodicWorkRequest` (15 min interval); fetches arrivals for each configured pin + each configured fav stop via `LtaApiClient`; writes results to SharedPreferences; calls `LeyneStopWidget().updateAll(context)` and `LeyneFavServiceWidget().updateAll(context)` to push new RemoteViews.
- [ ] **`widget/LeyneStopWidget.kt`** — `GlanceAppWidget` subclass; `Content()` reads `WidgetDataRepository` for the configured stop code and its arrivals; renders `SmallStopContent` or `MediumStopContent` based on `LocalSize.current`; provides `sizeMode = SizeMode.Responsive(setOf(DpSize(110.dp, 110.dp), DpSize(250.dp, 110.dp)))`.
- [ ] **`widget/LeyneStopWidgetReceiver.kt`** — `GlanceAppWidgetReceiver`; wires `LeyneStopWidget()`; schedules `WidgetRefreshWorker` on first `onEnabled`.
- [ ] **`widget/LeyneNearbyWidget.kt`** — `GlanceAppWidget`; `Content()` reads `WidgetDataRepository.getNearby()`; renders stop name + code, or empty state; `sizeMode = SizeMode.Single`.
- [ ] **`widget/LeyneNearbyWidgetReceiver.kt`** — `GlanceAppWidgetReceiver`; wires `LeyneNearbyWidget()`.
- [ ] **`widget/LeyneFavServiceWidget.kt`** — `GlanceAppWidget`; `Content()` reads configured fav id and its arrivals; renders service badge + destination + ETA; `sizeMode = SizeMode.Single`.
- [ ] **`widget/LeyneFavServiceWidgetReceiver.kt`** — `GlanceAppWidgetReceiver`; wires `LeyneFavServiceWidget()`.
- [ ] **`widget/StopPickerActivity.kt`** — `AppCompatActivity` shown as the configuration screen for Pinned Stop widget; lists `WidgetDataRepository.getPins()`; on tap saves `appWidgetId → stopCode` via `WidgetDataRepository.saveConfiguredStopCode(...)` and calls `LeyneStopWidget().updateAll(context)`; finishes with `RESULT_OK`. Displayed as a bottom-sheet style dialog (`Theme.MaterialComponents.Dialog` in manifest).
- [ ] **`widget/FavPickerActivity.kt`** — same pattern for Favourite Service widget; lists `WidgetDataRepository.getFavs()`.

### AndroidManifest.xml additions

In `/Users/rommel/Documents/Leyne/android/app/src/main/AndroidManifest.xml`, inside `<application>`:

- [ ] Three `<receiver>` entries for `LeyneStopWidgetReceiver`, `LeyneNearbyWidgetReceiver`, `LeyneFavServiceWidgetReceiver` — each with `android:exported="true"`, intent action `android.appwidget.action.APPWIDGET_UPDATE`, and `<meta-data android:name="android.appwidget.provider" android:resource="@xml/leyne_*_widget_info"/>`.
- [ ] Two `<activity>` entries for `StopPickerActivity` and `FavPickerActivity` — `android:exported="false"`, `android:theme="@style/Theme.AppCompat.Dialog"`.

### Dart glue

- [ ] **`lib/services/widget_bridge.dart`** — new file; singleton `WidgetBridge`; wraps `home_widget` calls; exposes `pushPins()`, `pushFavs()`, `pushNearby()`, `pushArrivals(stopCode, rows)`, `triggerUpdate()`. Called from `AppModel` and `DataStore` at the push points listed in §3.2. Background callback handler `_onWidgetTap(Uri uri)` forwards to `DeepLinkService`.
- [ ] **`lib/state/app_model.dart`** — add `WidgetBridge.shared.pushPins()` call at the end of `_persistPins()`, and `WidgetBridge.shared.pushFavs()` at the end of `_persistFavServices()`. Add `await WidgetBridge.shared.pushAll()` at the end of `load()`.
- [ ] **`lib/data/data_store.dart`** — add `WidgetBridge.shared.pushArrivals(code, rows)` at the end of `_fetchArrivals(code)` success path; add `WidgetBridge.shared.pushNearby(nearby.first)` at the end of `updateNearby()`.
- [ ] **`lib/main.dart`** — call `HomeWidget.registerBackgroundCallback(widgetBridgeBackgroundCallback)` before `runApp`; register `widgetBridgeBackgroundCallback` as a top-level function.

### String resources

- [ ] **`values/strings.xml`** — add `widget_stop_desc`, `widget_nearby_desc`, `widget_fav_desc`, `widget_no_pins`, `widget_no_nearby`, `widget_no_favs` string resources.

### Drawable resources

- [ ] **`drawable/widget_preview_stop.png`** (or vector) — static preview image shown in the widget gallery. Can be a screenshot of the rendered widget.
- [ ] **`drawable/widget_preview_nearby.png`**
- [ ] **`drawable/widget_preview_fav.png`**

---

## 6. Risks & Edge Cases

### Location off (Nearest Stop)

The widget never reads GPS itself — it only displays what the app last pushed. If the user denies
location, `DataStore.updateNearby()` never fires, the `leyne.widget.nearby` key stays absent, and
the widget shows the empty state ("Open Leyne to find nearby stops"). No permission is needed in
the widget or in the manifest beyond what the app already declares (`ACCESS_FINE_LOCATION`).

### No saved items (Pinned Stop / Favourite Service)

If `leyne.widget.pins` is absent or empty, `StopPickerActivity` shows an empty list with a prompt
to pin stops in the app. The Glance widget shows its empty state. Same pattern for favs. Do not
show a configuration activity on first add if the list is empty — instead render the empty state
directly (avoids a confusing activity with nothing to pick).

### Stale data labelling

The `fetchedAt` epoch ms in `leyne.widget.arrivals.<code>` lets the widget show a freshness cue.
Match the app's existing pattern: if data is older than 90 seconds, show a "·" or grey tint on ETA
figures. If older than 5 minutes, show "–" in place of each ETA (data is too stale to be useful).
This mirrors the iOS widget's implicit reliance on timeline refresh interval; on Android the
WorkManager 15-min interval can leave data staler than iOS's 1-min timeline.

### Scheduled-only ETA (non-monitored)

`ArrivalRow.mon1 == false` → prefix the ETA with a faint `~` (whisper-quiet, same as iOS `schedPrefix`
in `WidgetShared.swift` and the app's `feedback_timely_over_honest` memory). In Glance this is a
`Text("~$eta")` with a lower-alpha `ColorProvider`.

### Dark / light theming

Glance `ColorProvider` handles day/night automatically. Explicitly set `android:forceDarkAllowed="false"`
on the receiver meta-data to prevent legacy forced-dark from double-inverting the already-dark
palette. Test on API 31+ where Glance Material3 integration is most stable; also test on API 26
(minimum widget config activity).

### RemoteViews limitations (if falling back from Glance)

Should Glance prove incompatible with a specific OEM's launcher, the fallback is manual
`RemoteViews` inflation. Constraints to note: no arbitrary `View` subclasses, no `ConstraintLayout`
(use `LinearLayout`/`RelativeLayout` only), no `RippleDrawable` on API < 21, no custom fonts
(use `fontFamily="sans-serif-medium"` only). The Glance path avoids all of these.

### WorkManager constraints

On some OEMs (Xiaomi, Huawei) WorkManager periodic tasks are killed aggressively. The widget will
fall back to Dart-driven updates whenever the app is in the foreground. Accept that background
refresh may be unreliable on restricted OEMs; do not add `FOREGROUND_SERVICE` to the worker unless
strictly required (current manifest already has `FOREGROUND_SERVICE` declared but unused for
widgets). Advise users to add Leyne to "battery optimisation" exceptions if widgets appear stale.

### Widget IDs and multiple widget instances

A user may place the same widget type twice with different stops configured. `appWidgetId` is the
key in `WidgetDataRepository`; each instance stores its own configured stop code. `WidgetRefreshWorker`
must iterate all registered IDs for each provider and fetch arrivals for each configured stop (they
may overlap, so deduplicate fetch calls by stop code).

### App not installed / widget orphan

Standard Android behaviour: the widget is removed from the home screen when the app is uninstalled.
No special handling needed.

---

## 7. Not Included (Deferred)

- **Large (2-stop commute) widget** — maps to iOS `LargeCommuteView`; requires a 4×4 cell layout and a two-stop picker configuration activity. Straightforward to add once the Small/Medium sizes ship.
- **Pinned Stop medium widget with per-row tap** — iOS taps the whole widget via `widgetURL`; Android Glance supports per-row `clickable` but requires a `PendingIntent` per row. Defer to keep the initial scope tight.
- **Live Activity / ongoing notification** — already handled by `AppModel._refreshOngoing` + `NotificationsService.showOngoing`. Not a home-screen widget concern.
