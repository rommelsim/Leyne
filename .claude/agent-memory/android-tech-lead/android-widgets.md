---
name: android-widgets
description: Kotlin/Glance widget layer implementation details — file locations, data contract, key decisions
metadata:
  type: project
---

Android home-screen widgets are implemented in Kotlin/Glance 1.1.1 under `android/app/src/main/kotlin/com/leyne/leyne/widget/` (13 files created 2026-06-19).

## Data flow
Dart `WidgetBridge` → `HomeWidgetPlugin` SharedPreferences → `WidgetDataRepository` → `provideGlance`.
Worker path: `WidgetRefreshWorker` → `LtaApiClient` (HttpURLConnection) → `WidgetDataRepository.writeArrivals()` → `updateAll()`.

## Key decisions
- `ArrivalDisplayState` sealed interface (Fresh/Stale/Expired/None) defined in `LeyneStopWidget.kt` (internal), consumed by `LeyneFavServiceWidget.kt` from the same package — avoids a separate shared file.
- `InkServiceBadge`, `StopEtaColumns`, `fmtEta`, `arrivalsState`, `etaTextColor` are internal top-level functions in `LeyneStopWidget.kt` reused by the fav widget.
- `ColorProvider` tokens (`wFg`, `wDim` etc.) are used directly in `TextStyle.color` and `background()` — never re-wrapped as `ColorProvider(day=wFg.day, night=wFg.night)` (DayNightColorProvider's `.day`/`.night` are not public API in Glance 1.1.1).
- `cornerRadius()` comes from `androidx.glance.appwidget` (star-imported via `androidx.glance.appwidget.*`).
- `updateAll()` is an extension function in `androidx.glance.appwidget` — must be explicitly imported wherever called outside a file that already star-imports that package.
- Worker lifecycle: `WidgetRefreshWorker.enqueue()` called from both `LeyneStopWidgetReceiver.onEnabled` and `LeyneFavServiceWidgetReceiver.onEnabled`; cancel from both `onDisabled`. KEEP policy makes redundant enqueues safe.
- `java.time.OffsetDateTime` used in LtaApiClient — requires core library desugaring (already enabled in build.gradle.kts).
- Emoji glyphs used for map-pin (📍) and star (★) in place of vector drawables — avoids adding drawable assets.

**Why:** See [[android-no-map]] for why maps are absent from Android. Widget design is monochrome to match the 2.6.0+ identity.
**How to apply:** When adding or modifying widgets, keep provideGlance network-free; all I/O goes through WidgetRefreshWorker.
