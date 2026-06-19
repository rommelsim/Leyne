# Android "Bus-coming alerts" — geofence feature + Play compliance

**Status:** Built 2026-06-19 (branch `retention-ux`). Opt-in, OFF by default.

From the user's "smart tracking" idea: when you're near a stop you've favourited
a bus at, Leyne checks that bus's live arrivals and notifies you if it's within a
few minutes — even when the app is closed.

## How it works
- **Geofences** (~250 m, `GeofencingClient`) are registered around every stop the
  user has favourited a service at. Re-registered when favourites change, when
  reference data (coords) loads, and after reboot.
- **On region ENTER** → `GeofenceBroadcastReceiver` fetches that stop's arrivals
  (reusing the widget `LtaApiClient`), looks up the favourited services there
  (`WidgetDataRepository.getFavs()`), and posts a local notification to the
  existing `leyne.arrivals` channel if a favourited bus is ≤ 6 min away. A
  per-(stop, service) cooldown prevents spam.
- **No continuous GPS** — geofences are OS-managed and battery-efficient. The
  fetch + notify happen entirely in Kotlin; no Dart background isolate.
- Tapping the notification opens the stop via `lyne://stop/<code>/<no>`.

## Permissions
- `ACCESS_FINE_LOCATION` (already declared) + **`ACCESS_BACKGROUND_LOCATION`** (new).
- Requested ONLY after the user accepts the in-app **prominent-disclosure primer**
  (`_BusComingPrimer` in `lib/screens/notifications_screen.dart`), which states
  what is collected (location, incl. background), why, and that it's never shared.
- On Android 11+ "Allow all the time" is granted from Settings, not inline — the
  UI nudges the user there if background isn't granted.

## Google Play submission checklist (MUST do before release)
1. **Data safety form** → Location → declare: *Approximate location* + *Precise
   location*, collected, **used in background**, **NOT shared**, **optional**
   (user can disable). Purpose: *App functionality*.
2. **Background location declaration** (Play Console → App content → Sensitive
   permissions): submit the form + a short video showing the in-app primer and
   the feature, justifying why background location is core to the alert.
3. **Prominent disclosure**: the in-app primer dialog satisfies this; keep it
   shown BEFORE the runtime request (already wired).
4. Expect extended review time for the background-location declaration.

## Files
- Dart: `lib/services/geofence_service.dart` (MethodChannel `com.leyne.leyne/geofence`),
  toggle + primer in `lib/screens/notifications_screen.dart`,
  `AppModel.busComingAlertsEnabled` (key `lyne.busComingAlerts`).
- Kotlin: `android/app/src/main/kotlin/com/leyne/leyne/geofence/` +
  `MainActivity.configureFlutterEngine` channel handler.
- Manifest: `ACCESS_BACKGROUND_LOCATION` + `GeofenceBroadcastReceiver` +
  `GeofenceBootReceiver`. Gradle: `play-services-location`.

## Deferred (phase 2)
- Pinned-stop alerts (needs `Pin.tracked` services pushed to the native store).
- Configurable threshold minutes + quiet hours.
- iOS equivalent (CLLocationManager region monitoring).
