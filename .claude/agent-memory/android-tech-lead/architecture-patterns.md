---
name: architecture-patterns
description: State management, rebuild patterns, and DI conventions in the Flutter app
metadata:
  type: project
---

## State management

- **AppModel** (`lib/state/app_model.dart`): singleton ChangeNotifier. 27 `notifyListeners()` calls. Drives pins, settings, notifications, alight tracking, ongoing notification, and the 1-second countdown tick. All screens access it via `AppModel.shared`.
- **DataStore** (`lib/data/data_store.dart`): singleton ChangeNotifier. 9 `notifyListeners()` calls. Owns arrivals map, nearby stops, reference data (bus stops / services), routes, train alerts.
- **LocationService** (`lib/services/location_service.dart`): singleton ChangeNotifier. Wraps geolocator stream.

## Rebuild scope

V2 screens use `ListenableBuilder` with `Listenable.merge([AppModel.shared, DataStore.shared, ...])`. This means a single `tick++` increment from the 1-second timer forces a full rebuild of every visible screen. No selector/Consumer-style narrow rebuild is in use.

## Navigation

`SoftRoot` manages a nested `Navigator` with a `GlobalKey<NavigatorState>`. The root Navigator in `main.dart` (via `_navigatorKey`) handles notification-tap deep links and pushes SoftStopScreen/SoftBusScreen directly. This creates two separate Navigator stacks that can potentially conflict.

## DI

No DI framework. All singletons accessed via `.shared` static fields. `AppModel.forTesting()` factory for tests.

## Timer

`AppModel.startTicker()` → `Timer.periodic(1 second)` → `_onTick()` → `notifyListeners()` every second. Also calls `scheduleArrivalAlerts` every 10 ticks and `_refreshOngoing` every 5 ticks. No isolate offloading.
