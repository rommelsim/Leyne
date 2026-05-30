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

**Shipping UI:** V2 "Soft" under `lib/screens/v2/` and `lib/widgets/v2/`. V1 files at `lib/screens/` top level are dead legacy — do not review them.

**V2 screen inventory:**
- `lib/screens/v2/soft_home_screen.dart`
- `lib/screens/v2/soft_stop_screen.dart`
- `lib/screens/v2/soft_bus_screen.dart`
- `lib/screens/v2/soft_search_screen.dart`
- `lib/screens/v2/soft_nearby_screen.dart`
- `lib/screens/v2/soft_settings_screen.dart`
- `lib/screens/v2/soft_root.dart`
- `lib/widgets/v2/soft_components.dart` — SortChipRow, ServiceBadge, SoftToggle, Eyebrow, etc.
- `lib/widgets/v2/route_timeline.dart`
- `lib/widgets/v2/soft_tab_bar.dart`

**Services:** `lib/services/` — ad_consent, deep_link_service, geocode_service, location_service, notifications
**State:** `lib/state/app_model.dart` — singleton ChangeNotifier god-object
**Data:** `lib/data/data_store.dart` — singleton ChangeNotifier; `lib/data/lta_service.dart`, models, geo, search_logic
**Build:** pubspec.yaml — Flutter SDK ^3.12.0, version 2.3.0+22
