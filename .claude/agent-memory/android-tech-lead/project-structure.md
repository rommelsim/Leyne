---
name: project-structure
description: Android delivery via Flutter (lib/); android/ is thin wrapper only; V2 is shipping UI
metadata:
  type: project
---

Android is delivered entirely by the Flutter app in `lib/`. There is NO native Kotlin UI code.

- `android/app/src/main/kotlin/com/leyne/leyne/MainActivity.kt` — single-line FlutterActivity subclass, no channels
- `android/app/build.gradle.kts` — compileSdk/minSdk/targetSdk delegated to flutter.* variables; R8 disabled
- `android/app/src/main/AndroidManifest.xml` — permissions, notification receivers, App Links

**Shipping UI:** V2 "Soft" under `lib/screens/v2/` and `lib/widgets/v2/`. Confirmed LIVE by tracing `lib/main.dart` → `_AppRoot` → `SoftRoot` (routing root, not just a naming convention). `lib/widgets/atoms.dart` and `lib/widgets/ad_banner.dart` ARE live (used by `whats_new_screen.dart` and V2 screens respectively).

The old V1 tree (`lib/screens/{root_scaffold,home_screen,detail_screen,nearby_screen,search_screen,settings_screen,notifications_screen,about_screen}.dart` + the widgets only they used: `pinned_card`, `route_map`, `route_progress`, `service_row`, `stops_map`, `eta_pill`, `home_hero`) was confirmed dead (zero imports, 2026-07-02 grep) and then DELETED outright on 2026-07-02 as part of a Material You/modernization pass, along with its 4 now-orphaned test files (`test/{settings_features,eta_pill,screens,pinned_card}_test.dart`) — see [[material-you-implementation]]. These paths no longer exist; don't reference them.

**V2 screen inventory (current as of 2026-07-02):**
- `lib/screens/v2/soft_root.dart` — routing root; hand-rolled `PopScope` + `SystemNavigator.setFrameworkHandlesBack` for Android 13+ predictive-back correctness (see [[android-material-design]])
- `lib/screens/v2/soft_home_screen.dart`, `soft_stop_screen.dart`, `soft_bus_screen.dart`, `soft_search_screen.dart`, `soft_favourites_screen.dart` (saved/pinned tab — no separate "nearby" screen anymore), `soft_settings_screen.dart`, `soft_alerts_screen.dart`, `soft_mrt_screen.dart`, `soft_mrt_line_screen.dart`, `soft_mrt_station_screen.dart`, `mrt_map_screen.dart` (full-screen system map), `manage_alerts_screen.dart`, `hidden_stops_screen.dart`
- Tabs (per `soft_tab_bar.dart`): Bus(Home) · MRT · Saved · Search · Alerts — Settings is a gear-button sheet off Alerts, not a tab
- `lib/widgets/v2/soft_components.dart` — SortChipRow, ServiceBadge, SoftToggle, Eyebrow, LabelPill, WalkTile, MRTLineBar
- `lib/widgets/v2/soft_tab_bar.dart`, `route_timeline.dart`, `save_sheet.dart`, `weather_header.dart`, `confidence.dart`, `proximity.dart`, `alert_actions.dart`

**Services:** `lib/services/` — ad_consent, deep_link_service, geocode_service, location_service, notifications
**State:** `lib/state/app_model.dart` — singleton ChangeNotifier god-object
**Data:** `lib/data/data_store.dart` — singleton ChangeNotifier; `lib/data/lta_service.dart`, models, geo, search_logic
**Build:** pubspec.yaml — Flutter SDK ^3.12.0 (installed toolchain observed: Flutter 3.44.0 stable), app version 2.9.0+50. `android/local.properties` resolves `flutter.compileSdkVersion`/`targetSdkVersion` = 36, `minSdkVersion` = 24 (Flutter-managed, not pinned in this repo's Gradle files). AGP 9.0.1, Kotlin 2.3.20.
