---
name: project-weather-feature
description: NEA weather feature added to Flutter/Android — architecture, files, constraints
metadata:
  type: project
---

NEA/data.gov.sg weather feature shipped to the Flutter Android build in 2026-06.

**Files added:**
- `lib/data/nea_models.dart` — DTOs for 2-hour forecast, air temperature, 24h forecast + `WeatherCondition` enum + `WeatherSnapshot` domain model
- `lib/data/nea_service.dart` — HTTP client (mirrors lta_service.dart, no API key)
- `lib/data/weather_store.dart` — ChangeNotifier cache (15 min freshness, 3 parallel NEA fetches, nearest-area/station via haversine)
- `lib/widgets/v2/weather_header.dart` — StatefulWidget: greeting + HH:mm clock (minute ticker) + temp/condition/hint row + monochrome weather icon
- `test/weather_test.dart` — 31 unit tests (all pass); no network calls

**Files modified:**
- `lib/state/app_model.dart` — imports `weather_store.dart`; calls `WeatherStore.shared.refreshIfStale` every 60 ticks in `_onTick()`
- `lib/screens/v2/soft_home_screen.dart` — adds `_WeatherItem` sealed class; adds `WeatherStore.shared` to `Listenable.merge`; `WidgetsBindingObserver` for resume-refresh; `WeatherHeader` renders above greeting when snapshot non-null

**Design constraints:**
- Fully monochrome — uses `t.fg / t.dim / t.faint / t.surface` only. No hardcoded colours.
- Gradient backdrop: opacity-only on white/black tint (dark/light), varies by condition bucket (clear/cloudy/rain/night)
- Graceful: `snapshot == null` → `SizedBox.shrink()`, zero layout impact
- No touch on MRT/notification/alert code

**Why:** Timely weather context directly on the Home screen using free Singapore NEA APIs. [[platform-weather-ios]] may add iOS parity via WeatherKit in future.
