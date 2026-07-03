---
name: android-widgets
description: Kotlin/Glance widget layer implementation details — file locations, data contract, key decisions
metadata:
  type: project
---

Android home-screen widgets are implemented in Kotlin/Glance 1.1.1 under `android/app/src/main/kotlin/com/leyne/leyne/widget/`. Three widgets ship: Saved Stop (`LeyneStopWidget.kt`), Nearest Stop (`LeyneNearbyWidget.kt`, no config), Favourite Service (`LeyneFavServiceWidget.kt`).

## History (avoid re-deriving this from git blame)
`LeyneStopWidget.kt`/`Receiver`/`StopPickerActivity` + its XML/drawable were added 2026-06-19 (commit c22ed6f), then REMOVED same day (commit f26597a, "removed old widget from ios" — the iOS pinned-stop widget was pulled at the time). The shared helpers it defined (`ArrivalDisplayState`, `arrivalsState()`, `fmtEta()`, `etaTextColor()`, `InkServiceBadge`) were extracted into `WidgetCommon.kt` in that same removal commit so `LeyneFavServiceWidget.kt` kept working standalone. **2026-07-03: LeyneStopWidget.kt was RECREATED** (iOS re-added its Saved Stop widget — see `ios-native/LeyneWidgets/LeyneStopWidget.swift`) — restored near-verbatim from c22ed6f, but this time it consumes the shared helpers from `WidgetCommon.kt` rather than redefining them; only `StopEtaColumns` (row-level hero+2-followups layout) lives back in `LeyneStopWidget.kt` since only that widget uses it. Ships single-stop 2x2/4x2 only (small hero card / medium 3-row list) — the iOS Large two-stop AM/PM commute layout is explicitly NOT ported; flagged as future work in the file header.

## Data flow
Dart `WidgetBridge` → `HomeWidgetPlugin` SharedPreferences → `WidgetDataRepository` → `provideGlance`.
Worker path: `WidgetRefreshWorker` → `LtaApiClient` (HttpURLConnection) → `WidgetDataRepository.writeArrivals()` → `updateAll()`.
`leyne.widget.pins` (Dart `WidgetBridge._writePins()`, called from `AppModel._persistPins()` — the single funnel every pin mutation goes through, so `pushPins()` needed exactly one call site) resolves each pin's display name the same way iOS `AppModel.mirrorPinsToWidget` does: trimmed nickname, else resolved stop name, else the raw code as last resort.

## Key decisions
- `ArrivalDisplayState` sealed interface (Fresh/Stale/Expired/None), `arrivalsState()`, `fmtEta()`, `etaTextColor()`, `InkServiceBadge` live in `WidgetCommon.kt` (internal, same package) — shared by `LeyneStopWidget.kt` and `LeyneFavServiceWidget.kt`. Don't redefine these in a widget file; a past version had them in `LeyneStopWidget.kt` and that file no longer exists in some git history windows — always grep before assuming.
- `StopEtaColumns` (hero ETA + up to two follow-up columns) is `internal` in `LeyneStopWidget.kt` only — `LeyneFavServiceWidget.kt` inlines its own equivalent Row rather than sharing it.
- `ColorProvider` tokens (`wFg`, `wDim` etc., in `LeyneWidgetTheme.kt`) are used directly in `TextStyle.color` and `background()` — never re-wrapped as `ColorProvider(day=wFg.day, night=wFg.night)` (DayNightColorProvider's `.day`/`.night` are not public API in Glance 1.1.1). These are monochrome w_* tokens (unchanged by the 2026-07-02 Material You / dynamic-colour pass, which targeted the Flutter app, not the native widget layer — see [[design_identity_pass]]/[[material-you-implementation]] in the ios/android shared memory for the app-level colour decision; widgets still intentionally monochrome, matching all three siblings).
- `cornerRadius()` comes from `androidx.glance.appwidget` (star-imported via `androidx.glance.appwidget.*`).
- `updateAll()` is an extension function in `androidx.glance.appwidget` — must be explicitly imported wherever called outside a file that already star-imports that package.
- Worker lifecycle: `WidgetRefreshWorker.enqueue()` called from `LeyneStopWidgetReceiver.onEnabled` AND `LeyneFavServiceWidgetReceiver.onEnabled`; cancel from both `onDisabled`. KEEP policy makes redundant enqueues safe. The worker also collects stop codes from placed Stop-widget instances (`repo.getConfiguredStopCode(widgetId) ?: pins.firstOrNull()?.code`) in addition to Fav instances, and calls `LeyneStopWidget().updateAll(context)` alongside the Fav one.
- `java.time.OffsetDateTime` used in LtaApiClient — requires core library desugaring (already enabled in build.gradle.kts).
- Emoji glyphs used for map-pin (📍) and star (★) in place of vector drawables — avoids adding drawable assets.
- `WidgetDataRepository.getPins()`/`getConfiguredStopCode()`/`saveConfiguredStopCode()` already existed (untouched by the widget's removal/recreation) — always check that file before assuming a repository method needs adding.
- `flutter build apk --debug` / `./gradlew :app:compileDebugKotlin` both depend on the `:app:compileFlutterBuildDebug` Gradle task, which runs the full Dart kernel compile first — a broken file ANYWHERE in `lib/` (even one this task doesn't touch) blocks Kotlin-only verification. There is no way to compile-check just the Kotlin widget layer in isolation in this project.

**Why:** See [[android-no-map]] for why maps are absent from Android.
**How to apply:** When adding or modifying widgets, keep provideGlance network-free; all I/O goes through WidgetRefreshWorker. Before adding a shared Glance helper, grep `WidgetCommon.kt` and `WidgetDataRepository.kt` first — this layer has been added/removed/re-added and it's easy to duplicate something that already exists.
