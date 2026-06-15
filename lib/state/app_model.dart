// AppModel — pin/tracked/recents state + a 1-second tick for live ETA
// countdowns.
//
// Ports legacy/ios-native/Lyne/AppModel.swift, minus the bits that belong
// to deferred tasks:
//   • Live Activity (ActivityKit) — Task #12, via MethodChannel bridge.
//   • App Group / WidgetKit mirror — Task #12.
//
// State management is plain ChangeNotifier; persistence is
// shared_preferences keyed under `lyne.*` (matches the legacy keys).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/alert_timing.dart';
import '../data/changelog.dart';
import '../data/data_store.dart';
import '../data/geo.dart';
import '../data/models.dart';
import '../data/mrt_geo.dart';
import '../data/weather_store.dart';
import '../services/location_service.dart';
import '../services/notifications.dart';
import 'bus_alert.dart';

/// Global ScaffoldMessenger key — lets AppModel surface in-app arrival
/// alerts as a banner from outside the widget tree. Wired into MaterialApp
/// in main.dart.
final GlobalKey<ScaffoldMessengerState> lyneMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

// Persistence keys — kept identical to the legacy ones in case a future
// data-portability tool needs to reconcile across platforms.
const _kPinsKey = 'lyne.pins';
const _kFavServicesKey = 'lyne.favServices'; // 2.4.0 service favourites
const _kRecentsKey = 'lyne.recents';
const _kOnboardingDoneKey = 'lyne.onboardingDone';
const _kUse24hKey = 'lyne.use24h';
const _kThemeModeKey = 'lyne.themeMode';
const _kLocaleKey = 'lyne.locale';
const _kNotifKey = 'lyne.notifications';
const _kSearchRadiusKey = 'lyne.searchRadiusM';
const _kLastSeenVersionKey = 'lyne.lastSeenVersion';
const _kAlightKey = 'lyne.alight'; // JSON-encoded ActiveAlight
const _kHapticsKey = 'lyne.haptics';
const _kAlertsKey = 'lyne.alerts'; // JSON list of BusAlert (notifs redesign)
const _kHiddenNearbyKey = 'lyne.hiddenNearby'; // stop codes hidden from Nearby
const _kSavedMrtKey = 'lyne.savedMrt'; // JSON list of MrtGeoStation
const _kSeenAlertIdsKey = 'lyne.seenAlertIds'; // alert-badge seen tracking

/// The currently-armed on-bus alert: which bus, where to alight, when
/// the heads-up notification fires. Single ride at a time — see
/// AppModel.setActiveAlight.
class ActiveAlight {
  ActiveAlight({
    required this.busNo,
    required this.stopCode,
    required this.stopName,
    required this.fireAt,
  });
  final String busNo;
  final String stopCode;
  final String stopName;
  final DateTime fireAt;

  Map<String, dynamic> toJson() => {
    'busNo': busNo,
    'stopCode': stopCode,
    'stopName': stopName,
    'fireAt': fireAt.millisecondsSinceEpoch,
  };
  factory ActiveAlight.fromJson(Map<String, dynamic> j) => ActiveAlight(
    busNo: j['busNo'] as String,
    stopCode: j['stopCode'] as String,
    stopName: j['stopName'] as String,
    fireAt: DateTime.fromMillisecondsSinceEpoch(j['fireAt'] as int),
  );
}

// ─── FavService (2.4.0) ────────────────────────────────────────────────────
/// A favourite service — a bus number the user wants to follow.
/// `stop == null` means "anywhere" (next arrival near the user);
/// `stop != null` means "at this specific stop".
/// Mirrors ios-native/Leyne/AppModel.swift FavService.
class FavService {
  FavService({required this.no, this.stop});

  /// Service number e.g. "88", "158", "21A".
  final String no;

  /// Stop code when saved "at stop"; null = "anywhere".
  final String? stop;

  /// Stable identity — matches iOS `id` computed var.
  String get id => stop != null ? '$no#$stop' : '$no#*';

  /// True when saved as "next arrival near me" (not stop-specific).
  bool get isAnywhere => stop == null;

  factory FavService.fromJson(Map<String, dynamic> j) =>
      FavService(no: j['no'] as String, stop: j['stop'] as String?);

  Map<String, dynamic> toJson() => {'no': no, if (stop != null) 'stop': stop};

  @override
  bool operator ==(Object other) => other is FavService && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// One user-pinned stop. Invariant: a Pin always tracks ≥1 bus — so
/// "pinned" ⟺ "has buses shown". `tracked == null` means *all* services
/// (default; correct even before arrivals load). A non-null list is an
/// explicit, non-empty subset. An empty selection is never stored — it
/// means "unpin" (the Pin is removed).
class Pin {
  Pin({required this.code, required this.nickname, this.tracked});

  final String code;
  String nickname;
  List<String>? tracked; // null = all

  factory Pin.fromJson(Map<String, dynamic> j) => Pin(
    code: j['code'] as String,
    nickname: (j['nickname'] as String?) ?? '',
    tracked: (j['tracked'] as List?)?.cast<String>(),
  );

  Map<String, dynamic> toJson() => {
    'code': code,
    'nickname': nickname,
    if (tracked != null) 'tracked': tracked,
  };
}

class AppModel extends ChangeNotifier {
  AppModel._();
  static final AppModel shared = AppModel._();

  /// Test-only factory. Identical to .shared semantically; named for
  /// clarity at the call site.
  @visibleForTesting
  factory AppModel.forTesting() => AppModel._();

  /// Start the 1-second tick that drives the live ETA countdown + keeps
  /// pinned-stop arrivals fresh. Called once from main() after load().
  /// Idempotent. Tests skip this so the test runner exits cleanly.
  void startTicker() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  final DataStore _ds = DataStore.shared;
  final LocationService _loc = LocationService.shared;
  Timer? _timer;

  /// Public tick counter; UI can listen via ChangeNotifier and re-render
  /// live ETA labels on each tick.
  int tick = 0;

  // ─── Onboarding (persisted) ───────────────────────────────
  // True once the user has either finished or skipped the intro flow.
  // Drives the boot routing in main.dart: first-run users see
  // OnboardingScreen and trigger UMP/ATT from its final step; returning
  // users skip straight to RootScaffold and AdConsent runs at startup.
  bool _onboardingDone = false;
  bool get onboardingDone => _onboardingDone;

  /// Mark onboarding complete (or skipped — same effect for routing).
  void finishOnboarding() {
    if (_onboardingDone) return;
    _onboardingDone = true;
    _prefs?.setBool(_kOnboardingDoneKey, true);
    // A user who just finished onboarding is, by definition, current — pin
    // the running version so the What's New screen doesn't fire on their
    // very next launch for the version they just installed.
    _recordVersionSeen();
    notifyListeners();
  }

  // ─── What's New (changelog after an app update) ───────────
  // `_currentVersion` is the running build's marketing version, set once at
  // startup from package_info. `_lastSeenVersion` is the version the user
  // last acknowledged — persisted so an update is detected exactly once.
  String? _currentVersion;
  String? _lastSeenVersion;

  /// Record the running app version (from package_info). Called once in
  /// main() before the first frame so `whatsNewVersion` is stable.
  void setCurrentVersion(String version) {
    if (_currentVersion == version) return;
    _currentVersion = version;
    notifyListeners();
  }

  /// The version whose What's New screen should be shown now, or null.
  ///
  /// Shows when the running version has a changelog entry the user hasn't
  /// acknowledged. Fresh installs (still in onboarding) never see it — they
  /// have no prior version to have "updated" from; `finishOnboarding` pins
  /// their version so it stays that way.
  String? get whatsNewVersion {
    final cur = _currentVersion;
    if (cur == null || !kChangelog.containsKey(cur)) return null;
    if (_lastSeenVersion == cur) return null;
    if (!_onboardingDone) return null;
    return cur;
  }

  /// Acknowledge the current What's New screen — records the version so it
  /// won't show again, and routes the user on into the app.
  void markWhatsNewSeen() {
    _recordVersionSeen();
    notifyListeners();
  }

  void _recordVersionSeen() {
    final v = _currentVersion;
    if (v == null || v == _lastSeenVersion) return;
    _lastSeenVersion = v;
    _prefs?.setString(_kLastSeenVersionKey, v);
  }

  /// Clear the flag so the user can replay onboarding from Settings.
  void resetOnboarding() {
    _onboardingDone = false;
    _prefs?.setBool(_kOnboardingDoneKey, false);
    notifyListeners();
  }

  // ─── Preferences (persisted) ──────────────────────────────
  // 12-hour vs 24-hour clock. The in-app toggle was removed; the app uses a
  // 12-hour clock app-wide, so this defaults to false.
  bool _use24h = false;
  bool get use24h => _use24h;

  void setUse24h(bool v) {
    if (_use24h == v) return;
    _use24h = v;
    _prefs?.setBool(_kUse24hKey, v);
    notifyListeners();
  }

  // Appearance override. Defaults to `system` — follow the OS light/dark
  // setting — but the user can force light or dark from Settings.
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  void setThemeMode(ThemeMode m) {
    if (_themeMode == m) return;
    _themeMode = m;
    _prefs?.setString(_kThemeModeKey, m.name);
    notifyListeners();
  }

  // Language override. `null` = follow the device locale; a non-null value
  // is an explicit pick from Settings. Stored as a BCP-47-ish tag.
  Locale? _locale;
  Locale? get locale => _locale;

  void setLocale(Locale? l) {
    if (_locale?.languageCode == l?.languageCode) return;
    _locale = l;
    if (l == null) {
      _prefs?.remove(_kLocaleKey);
    } else {
      _prefs?.setString(_kLocaleKey, l.languageCode);
    }
    notifyListeners();
  }

  // Arrival-alert notifications. Real native Android system notifications
  // scheduled via flutter_local_notifications — they fire on the lock
  // screen / as a heads-up even when Leyne is backgrounded. Toggle the
  // intent through `setNotificationsEnabled(...)` so permission is
  // requested at the right moment; the raw storage flag below is the
  // persisted result of that flow.
  bool _notificationsEnabled = false;
  bool get notificationsEnabled => _notificationsEnabled;

  /// Last observed system permission state, refreshed on launch and
  /// whenever the user opens NotificationsScreen.
  NotifPermStatus _notificationAuth = NotifPermStatus.notDetermined;
  NotifPermStatus get notificationAuth => _notificationAuth;

  /// Toggle the user's intent. Turning on triggers the runtime POST_-
  /// NOTIFICATIONS prompt on Android 13+; if denied, the toggle snaps
  /// back to off. Turning off cancels any pending scheduled alerts.
  Future<void> setNotificationsEnabled(bool v) async {
    if (v) {
      final granted = await NotificationsService.shared.requestAuthorization();
      _notificationAuth = await NotificationsService.shared.currentStatus();
      if (granted) {
        // Best effort: ask for exact alarm permission too, so on
        // Android 14+ the heads-up fires at the intended second rather
        // than within Doze's batching window. Denial is fine — we fall
        // back to inexact in NotificationsService._scheduleMode().
        await NotificationsService.shared.requestExactAlarmAuthorization();
        _notificationsEnabled = true;
        _prefs?.setBool(_kNotifKey, true);
        await NotificationsService.shared.scheduleAlerts(_alerts, _ds.arrivals);
      } else {
        _notificationsEnabled = false;
        _prefs?.setBool(_kNotifKey, false);
      }
    } else {
      _notificationsEnabled = false;
      _prefs?.setBool(_kNotifKey, false);
      await NotificationsService.shared.clearAll();
      // Tear down the ongoing tracker too — it can't fire without the
      // permission, so leaving it (and its in-app "active" state) would lie.
      await _stopOngoingTracker();
    }
    notifyListeners();
  }

  /// Refreshes `_notificationAuth` from the system — call on
  /// NotificationsScreen `initState`. If the user revoked permission
  /// via system Settings while the app was alive, drops the in-app
  /// toggle so it reads honest.
  Future<void> refreshNotificationAuth() async {
    _notificationAuth = await NotificationsService.shared.currentStatus();
    // Only flip the toggle off when the system has an explicit "no"
    // (denied or permanentlyDenied). `.notDetermined` can appear
    // briefly during the boot-time prompt race, and treating it as
    // "no" would silently disable the user's intent before iOS/Android
    // even shows the dialog. Mirrors iOS AppModel.refreshNotificationAuth.
    final explicitlyDenied =
        _notificationAuth == NotifPermStatus.denied ||
        _notificationAuth == NotifPermStatus.permanentlyDenied;
    if (_notificationsEnabled && explicitlyDenied) {
      _notificationsEnabled = false;
      _prefs?.setBool(_kNotifKey, false);
      await NotificationsService.shared.clearAll();
      await _stopOngoingTracker();
    }
    notifyListeners();
  }

  // ─── Haptics (persisted) ─────────────────────────────────
  // Whether the device vibrates when arrival alerts fire.
  // Default ON — matches the iOS defaults.

  bool _hapticsEnabled = true;
  bool get hapticsEnabled => _hapticsEnabled;

  void setHaptics(bool v) {
    if (_hapticsEnabled == v) return;
    _hapticsEnabled = v;
    _prefs?.setBool(_kHapticsKey, v);
    notifyListeners();
  }

  // ─── Active alight ride (persisted) ─────────────────────
  ActiveAlight? _activeAlight;
  ActiveAlight? get activeAlight => _activeAlight;

  /// True iff there's an armed alight matching this exact bus + stop —
  /// DetailScreen uses it to drive the picker highlight and the
  /// "Buzz me" card's active state.
  bool isActiveAlight({required String busNo, required String stopCode}) =>
      _activeAlight != null &&
      _activeAlight!.busNo == busNo &&
      _activeAlight!.stopCode == stopCode;

  /// Arm the alight alert. Replaces any prior ride (one at a time).
  /// `fireAt` is computed by DetailScreen from RouteInfo as the moment
  /// the bus should be ~2 stops out — see _computeAlightFireAt there.
  Future<void> setActiveAlight({
    required String busNo,
    required String stopCode,
    required String stopName,
    required DateTime fireAt,
  }) async {
    _activeAlight = ActiveAlight(
      busNo: busNo,
      stopCode: stopCode,
      stopName: stopName,
      fireAt: fireAt,
    );
    _prefs?.setString(_kAlightKey, jsonEncode(_activeAlight!.toJson()));
    await NotificationsService.shared.scheduleAlightAlert(
      busNo: busNo,
      alightStopCode: stopCode,
      alightStopName: stopName,
      fireAt: fireAt,
    );
    notifyListeners();
  }

  /// Disarm the active alight ride + cancel its pending notification.
  Future<void> clearActiveAlight() async {
    _activeAlight = null;
    _prefs?.remove(_kAlightKey);
    await NotificationsService.shared.cancelAlightAlerts();
    notifyListeners();
  }

  // Postal-code search radius in metres. When the user searches a 6-digit
  // postal code, bus stops within this distance of that address are listed.
  int _searchRadiusM = 500;
  int get searchRadiusM => _searchRadiusM;

  void setSearchRadiusM(int v) {
    if (_searchRadiusM == v) return;
    _searchRadiusM = v;
    _prefs?.setInt(_kSearchRadiusKey, v);
    notifyListeners();
  }

  // ─── Hidden-from-Nearby stops (persisted) ────────────────────
  // Stop codes the user has hidden from the Home/Nearby list via the
  // long-press "Hide from Nearby" action. Restored from Settings → Hidden
  // stops. Mirrors iOS AppModel.hiddenNearby. Independent of pins — a hidden
  // stop can still be saved (it just won't surface in Nearby).
  Set<String> _hiddenNearby = <String>{};
  Set<String> get hiddenNearby => Set.unmodifiable(_hiddenNearby);

  bool isHiddenNearby(String code) => _hiddenNearby.contains(code);

  void _persistHiddenNearby() {
    _prefs?.setStringList(_kHiddenNearbyKey, _hiddenNearby.toList());
  }

  /// Hide a stop from the Nearby list. No-op if already hidden.
  void hideFromNearby(String code) {
    if (!_hiddenNearby.add(code)) return;
    _persistHiddenNearby();
    notifyListeners();
  }

  /// Restore a previously hidden stop (Settings → Hidden stops).
  void unhideNearby(String code) {
    if (!_hiddenNearby.remove(code)) return;
    _persistHiddenNearby();
    notifyListeners();
  }

  // ─── FavServices (persisted, 2.4.0) ──────────────────────────
  List<FavService> _favServices = const [];
  List<FavService> get favServices => List.unmodifiable(_favServices);

  void _persistFavServices() {
    _prefs?.setString(
      _kFavServicesKey,
      jsonEncode(_favServices.map((f) => f.toJson()).toList()),
    );
  }

  /// True if this (no, stop) pair is already saved.
  bool isFavService({required String no, String? stop}) =>
      _favServices.any((f) => f.no == no && f.stop == stop);

  /// Add or remove the favourite. Call with stop=null for "anywhere",
  /// stop=code for "at this stop".
  void toggleFavService({required String no, String? stop}) {
    final idx = _favServices.indexWhere((f) => f.no == no && f.stop == stop);
    if (idx >= 0) {
      _favServices = [..._favServices]..removeAt(idx);
    } else {
      _favServices = [..._favServices, FavService(no: no, stop: stop)];
    }
    _persistFavServices();
    notifyListeners();
  }

  void removeFavService(FavService fav) {
    _favServices = _favServices.where((f) => f.id != fav.id).toList();
    _persistFavServices();
    notifyListeners();
  }

  // ─── Saved MRT stations (persisted) ──────────────────────────
  // Mirrors favServices/pins. Persisted as JSON under lyne.savedMrt. Pure local
  // state — the MRT station detail toggles membership; the Saved tab and the
  // MRT tab surface the list. Mirrors iOS AppModel.savedMrtStations.
  List<MrtGeoStation> _savedMrtStations = const [];
  List<MrtGeoStation> get savedMrtStations =>
      List.unmodifiable(_savedMrtStations);

  void _persistSavedMrt() {
    _prefs?.setString(
      _kSavedMrtKey,
      jsonEncode(_savedMrtStations.map((s) => s.toJson()).toList()),
    );
  }

  /// True if this station is already saved (matched by stable id).
  bool isMrtSaved(MrtGeoStation station) =>
      _savedMrtStations.any((s) => s.id == station.id);

  /// Add or remove the station from the saved list.
  void toggleMrtSaved(MrtGeoStation station) {
    if (isMrtSaved(station)) {
      _savedMrtStations = _savedMrtStations
          .where((s) => s.id != station.id)
          .toList();
    } else {
      _savedMrtStations = [..._savedMrtStations, station];
    }
    _persistSavedMrt();
    notifyListeners();
  }

  void removeMrtSaved(MrtGeoStation station) {
    _savedMrtStations = _savedMrtStations
        .where((s) => s.id != station.id)
        .toList();
    _persistSavedMrt();
    notifyListeners();
  }

  /// Reorder saved stations to [newIds] (list of MrtGeoStation.id). Any id not
  /// present is appended at the end (preserves concurrently-added items).
  /// Persists immediately. Mirrors [reorderFavServices].
  void reorderSavedMrt(List<String> newIds) {
    final byId = {for (final s in _savedMrtStations) s.id: s};
    final next = <MrtGeoStation>[];
    for (final id in newIds) {
      final s = byId.remove(id);
      if (s != null) next.add(s);
    }
    next.addAll(byId.values);
    _savedMrtStations = next;
    _persistSavedMrt();
    notifyListeners();
  }

  // ─── Alert-badge seen tracking (persisted) ───────────────────────────────
  // Mirrors iOS AppModel.seenAlertIds / unseenAlertCount / markAllAlertsSeen.
  // Stores the ids of TrainAlert + LiftMaintenance entries the user has already
  // seen (i.e. visited the Alerts tab while they were present). The badge on
  // the Alerts tab is the count of current alerts whose id is NOT in this set.
  Set<String> _seenAlertIds = <String>{};

  /// How many current service-status alerts (train disruptions + lift
  /// maintenance) the user has not yet seen on the Alerts tab.
  /// Read by SoftRoot to badge the Alerts tab item.
  int unseenAlertCount(List<String> currentAlertIds) {
    var count = 0;
    for (final id in currentAlertIds) {
      if (!_seenAlertIds.contains(id)) count++;
    }
    return count;
  }

  /// Mark every currently-known alert id as seen. Called whenever the Alerts
  /// tab is active and new data lands, so the badge reflects only NEW items.
  void markAllAlertsSeen(List<String> currentAlertIds) {
    var changed = false;
    for (final id in currentAlertIds) {
      if (_seenAlertIds.add(id)) changed = true;
    }
    if (!changed) return;
    _prefs?.setStringList(_kSeenAlertIdsKey, _seenAlertIds.toList());
    notifyListeners();
  }

  // ─── Configurable alerts (persisted, notifications redesign) ────────────
  // The single source of truth for notification alerts (both kinds). Arrival
  // alerts are re-armed from the live ETA each coarse tick; destination alerts
  // carry a fire time computed at set-time by the Bus view (see scheduleAlerts).
  // Independent of pin/`tracked` card visibility — set via upsertAlert/removeAlert.
  List<BusAlert> _alerts = [];
  List<BusAlert> get alerts => List.unmodifiable(_alerts);

  void _persistAlerts() {
    _prefs?.setString(
      _kAlertsKey,
      jsonEncode(_alerts.map((a) => a.toJson()).toList()),
    );
  }

  /// The alert matching this exact kind + bus + stop, or null.
  BusAlert? alertFor({
    required AlertKind kind,
    required String busNo,
    required String stopCode,
  }) {
    final id = BusAlert.makeId(kind, busNo, stopCode);
    for (final a in _alerts) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Add an alert, or replace the existing one with the same id. Persists,
  /// schedules (destination alerts compute their fire time at the call site
  /// and pass it; arrival alerts re-arm from the live ETA), then notifies.
  Future<void> upsertAlert(BusAlert a, {DateTime? destinationFireAt}) async {
    final idx = _alerts.indexWhere((e) => e.id == a.id);
    if (idx >= 0) {
      _alerts[idx] = a;
    } else {
      _alerts = [..._alerts, a];
    }
    _persistAlerts();
    // Setting an alert IS the opt-in to notifications. If they're not enabled
    // yet (e.g. the user skipped the onboarding prompt, or never visited
    // Settings ▸ Notifications), turn them on now — this requests
    // POST_NOTIFICATIONS + exact-alarm permission and schedules the pending
    // alerts. Without this the alert is stored but NEVER fires, which is
    // exactly the "Android notifications don't work" report: scheduling is
    // gated behind `_notificationsEnabled`, and it defaults to off.
    if (!_notificationsEnabled) {
      await setNotificationsEnabled(true);
    }
    if (a.kind == AlertKind.destination &&
        destinationFireAt != null &&
        _notificationsEnabled) {
      await NotificationsService.shared.scheduleDestinationAlert(
        a,
        destinationFireAt,
      );
    }
    await rescheduleIfNeeded();
    notifyListeners();
  }

  /// Remove an alert by id; cancel its pending notification, persist, reschedule.
  Future<void> removeAlert(String id) async {
    final idx = _alerts.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    final removed = _alerts[idx];
    _alerts = [..._alerts]..removeAt(idx);
    _persistAlerts();
    await NotificationsService.shared.cancelAlert(removed);
    // Arrival alerts are paired with the ongoing-tracking notification (the bus
    // view starts both together). Any removal path — including Manage alerts —
    // must end that companion too, or it lingers with no in-app way to stop it.
    if (removed.kind == AlertKind.arrival &&
        _ongoingKey == _liveKey(removed.busNo, removed.stopCode)) {
      await _stopOngoingTracker();
    }
    await rescheduleIfNeeded();
    notifyListeners();
  }

  /// Convenience: remove the alert matching kind + bus + stop, if any.
  Future<void> removeAlertsFor({
    required AlertKind kind,
    required String busNo,
    required String stopCode,
  }) => removeAlert(BusAlert.makeId(kind, busNo, stopCode));

  // ─── Pins / recents (persisted) ───────────────────────────
  List<Pin> _pins = const [];
  List<Pin> get pins => List.unmodifiable(_pins);

  List<String> _recents = const [];
  List<String> get recents => List.unmodifiable(_recents);

  // Recently-added pin highlight pulse — clears after ~1.4s.
  String? _recentlyAddedId;
  String? get recentlyAddedId => _recentlyAddedId;

  SharedPreferences? _prefs;

  /// Call once at startup (main.dart) before any UI binds.
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _onboardingDone = _prefs!.getBool(_kOnboardingDoneKey) ?? false;
    _use24h = _prefs!.getBool(_kUse24hKey) ?? false;
    final tm = _prefs!.getString(_kThemeModeKey);
    _themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == tm,
      orElse: () => ThemeMode.system,
    );
    final lc = _prefs!.getString(_kLocaleKey);
    _locale = (lc == null || lc.isEmpty) ? null : Locale(lc);
    // Default OFF: the flag is the persisted result of the permission
    // flow (see setNotificationsEnabled). Defaulting ON would show the
    // toggle enabled before POST_NOTIFICATIONS was ever granted, so no
    // alerts would actually fire — a lying toggle. Opt-in only.
    _notificationsEnabled = _prefs!.getBool(_kNotifKey) ?? false;
    _hapticsEnabled = _prefs!.getBool(_kHapticsKey) ?? true;
    _searchRadiusM = _prefs!.getInt(_kSearchRadiusKey) ?? 500;
    _lastSeenVersion = _prefs!.getString(_kLastSeenVersionKey);

    final raw = _prefs!.getString(_kPinsKey);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        _pins = list.map(Pin.fromJson).toList();
      } catch (_) {
        /* corrupt — start empty */
      }
    }
    _recents = _prefs!.getStringList(_kRecentsKey) ?? const [];
    _hiddenNearby = (_prefs!.getStringList(_kHiddenNearbyKey) ?? const [])
        .toSet();
    // Load favourite services (2.4.0).
    final favRaw = _prefs!.getString(_kFavServicesKey);
    if (favRaw != null) {
      try {
        final list = (jsonDecode(favRaw) as List).cast<Map<String, dynamic>>();
        _favServices = list.map(FavService.fromJson).toList();
      } catch (_) {
        /* corrupt — start empty */
      }
    }
    // Load saved MRT stations.
    final savedMrtRaw = _prefs!.getString(_kSavedMrtKey);
    if (savedMrtRaw != null) {
      try {
        final list = (jsonDecode(savedMrtRaw) as List)
            .cast<Map<String, dynamic>>();
        _savedMrtStations = list.map(MrtGeoStation.fromJson).toList();
      } catch (_) {
        /* corrupt — start empty */
      }
    }
    // Seen alert ids for the Alerts tab badge.
    _seenAlertIds =
        (_prefs!.getStringList(_kSeenAlertIdsKey) ?? const []).toSet();

    // Restore any in-flight alight ride so the picker still shows the
    // armed stop on reopen. We don't re-schedule the notification — the
    // system already holds the AlarmManager registration from when we
    // first armed it; re-adding would just create a duplicate.
    final alightRaw = _prefs!.getString(_kAlightKey);
    if (alightRaw != null) {
      try {
        _activeAlight = ActiveAlight.fromJson(
          jsonDecode(alightRaw) as Map<String, dynamic>,
        );
      } catch (_) {
        /* corrupt — start empty */
      }
    }
    // Configurable alerts (notifications redesign). When the key is present we
    // load it verbatim; when it's absent we run a one-time, best-effort
    // migration that turns the legacy state into equivalent alerts so existing
    // users keep their behaviour:
    //   • each Pin.tracked service → an arrival alert (lead 1 = old 60 s)
    //   • the active alight ride    → a destination alert (lead 1)
    final alertsRaw = _prefs!.getString(_kAlertsKey);
    if (alertsRaw != null) {
      try {
        final list = (jsonDecode(alertsRaw) as List)
            .cast<Map<String, dynamic>>();
        _alerts = list.map(BusAlert.fromJson).toList();
      } catch (_) {
        /* corrupt — start empty */
      }
    } else {
      _migrateLegacyAlerts();
    }

    // An ongoing tracker is in-memory only (`_ongoingKey`), so after a cold
    // start there's nothing driving it — but the OS may still be showing a
    // stale, frozen notification from the killed session. Clear it.
    NotificationsService.shared.stopOngoing();

    // Wire the disruption-notification callback. Mirrors iOS DataStore
    // .fetchTrainAlerts → NotificationsManager.shared.notifyTrainDisruption,
    // gated on `notificationsEnabled`. Each new disruption line fires an
    // immediate heads-up notification keyed by line code.
    _ds.onNewDisruption = (alert) {
      if (!_notificationsEnabled) return;
      NotificationsService.shared.notifyTrainDisruption(
        lineCode: alert.lineCode,
        title: alert.title,
        detail: alert.detail,
      );
    };

    notifyListeners();
  }

  void _persistPins() {
    final p = _prefs;
    if (p == null) return;
    p.setString(_kPinsKey, jsonEncode(_pins.map((e) => e.toJson()).toList()));
  }

  /// One-time migration from legacy state → BusAlerts. Best-effort: preserves
  /// the old 60 s lead via lead=1 so a returning user's notifications behave
  /// the same. Persists the seeded list so it never runs twice.
  void _migrateLegacyAlerts() {
    final seeded = <BusAlert>[];
    // Each explicitly-tracked service became a 60 s arrival alert. Pins with
    // tracked == null (all) carry no per-service alert in the legacy model
    // (they only schedule for the services they show), so we can't enumerate
    // the bus numbers here without arrivals; those re-arm on demand once the
    // user re-toggles. Migrate only the explicit subsets.
    for (final p in _pins) {
      final tracked = p.tracked;
      if (tracked == null) continue;
      for (final no in tracked) {
        seeded.add(
          BusAlert(
            kind: AlertKind.arrival,
            busNo: no,
            stopCode: p.code,
            stopName: _ds.stopName(p.code),
            leadMinutes: 1,
          ),
        );
      }
    }
    // The active alight ride became a destination alert (lead 1).
    final a = _activeAlight;
    if (a != null) {
      seeded.add(
        BusAlert(
          kind: AlertKind.destination,
          busNo: a.busNo,
          stopCode: a.stopCode,
          stopName: a.stopName,
          leadMinutes: 1,
          boardStopCode: a.stopCode,
        ),
      );
    }
    _alerts = seeded;
    _persistAlerts();
  }

  void addRecent(String q) {
    final v = q.trim();
    if (v.isEmpty) return;
    final next = [
      v,
      ..._recents.where((r) => r.toLowerCase() != v.toLowerCase()),
    ];
    _recents = next.take(8).toList();
    _prefs?.setStringList(_kRecentsKey, _recents);
    notifyListeners();
  }

  void removeRecent(String q) {
    _recents = _recents
        .where((r) => r.toLowerCase() != q.toLowerCase())
        .toList();
    _prefs?.setStringList(_kRecentsKey, _recents);
    notifyListeners();
  }

  void clearRecents() {
    _recents = const [];
    _prefs?.setStringList(_kRecentsKey, _recents);
    notifyListeners();
  }

  // ─── Tick: smooth countdown + keep visible stops fresh ──
  /// Arrival-alert ids seen with the bus still inbound. Gate for
  /// [_clearFulfilledArrivalAlerts] so a freshly-set alert on a bus that's
  /// momentarily at the stop isn't cleared on the same tick it's created.
  final Set<String> _arrivalsSeenInbound = {};

  /// Arrival-alert ids already given the "1 minute away" buzz this approach, so
  /// the gentle haptic fires once per bus (not every tick) and re-arms for the
  /// next bus once this one has departed. See [_buzzApproachingBuses].
  final Set<String> _buzzedOneMin = {};

  /// Gently buzz once when a bus we're alerting on drops to ~1 minute away,
  /// while the app is in the foreground. Mirrors the lock-screen alert's lead
  /// with an in-app cue. Respects the haptics setting. The notification's own
  /// vibration covers the backgrounded case (the channel enables vibration).
  void _buzzApproachingBuses() {
    if (!_hapticsEnabled) return;
    for (final a in _alerts) {
      if (a.kind != AlertKind.arrival) continue;
      final matches = liveServices(a.stopCode, tracked: [a.busNo]);
      if (matches.isEmpty) continue; // not in the feed this tick — leave as-is
      final eta = matches.first.etaSec;
      if (eta > 90) {
        // Bus is comfortably away (or the next one has rolled in) — re-arm.
        _buzzedOneMin.remove(a.id);
      } else if (eta <= 60 && eta > 0 && !_buzzedOneMin.contains(a.id)) {
        _buzzedOneMin.add(a.id);
        HapticFeedback.mediumImpact();
      }
    }
  }

  /// Removes arrival alerts whose tracked bus has reached the stop. The bus's
  /// locally-computed ETA holds at 0 from arrival until the next feed refresh,
  /// so the per-second tick reliably catches the window. Only alerts seen
  /// inbound first are cleared. [removeAlert] also stops the paired ongoing
  /// tracker, keeping both surfaces in sync.
  void _clearFulfilledArrivalAlerts() {
    final fulfilled = <String>[];
    for (final a in _alerts) {
      if (a.kind != AlertKind.arrival) continue;
      final matches = liveServices(a.stopCode, tracked: [a.busNo]);
      if (matches.isEmpty) continue; // bus not in the feed this tick — wait
      if (matches.first.etaSec > 0) {
        _arrivalsSeenInbound.add(a.id);
      } else if (_arrivalsSeenInbound.contains(a.id)) {
        fulfilled.add(a.id);
      }
    }
    for (final id in fulfilled) {
      _arrivalsSeenInbound.remove(id);
      unawaited(removeAlert(id));
    }
  }

  void _onTick() {
    tick++;
    final codes = <String>{for (final p in _pins) p.code};
    for (final c in codes) {
      _ds.ensureArrivals(c);
    }
    // Keep every arrival-alert stop fresh (not just pinned ones) so the
    // scheduler and the one-shot clear below read current arrivalDates.
    for (final a in _alerts) {
      if (a.kind == AlertKind.arrival) _ds.ensureArrivals(a.stopCode);
    }
    // One-shot arrival alerts: once the tracked bus reaches the stop, the alert
    // has done its job — clear it (and its paired ongoing tracker, via
    // removeAlert) so it doesn't linger in Manage alerts or silently re-arm for
    // the next bus. Matches the ongoing tracker, which finalises on arrival.
    _clearFulfilledArrivalAlerts();
    // Gentle in-app buzz the moment an alerted bus reaches ~1 minute away.
    _buzzApproachingBuses();
    // Re-arm scheduled arrival alerts every ~10 s — LTA's arrivalDate
    // values drift, and a coarse cadence is enough because notification
    // fire times are absolute (zonedSchedule registers an exact alarm
    // with the system, which keeps firing regardless of app lifecycle).
    if (_notificationsEnabled && tick % 10 == 0) {
      NotificationsService.shared.scheduleAlerts(_alerts, _ds.arrivals);
    }
    // Pull MRT/LRT disruption alerts on a slow cadence. DataStore
    // enforces a 60 s gate internally so this call is cheap.
    _ds.refreshTrainAlertsIfStale();
    // Refresh weather on a slow cadence (~1 min tick, 15 min inner gate).
    // Passes the current location so the nearest-area/station resolution
    // stays accurate as the user moves. Silently no-ops when location is
    // absent or the cache is fresh.
    if (tick % 60 == 0) {
      final loc = _loc.lastLocation;
      WeatherStore.shared.refreshIfStale(lat: loc?.lat, lon: loc?.lon);
    }
    // Live tracker (single, automatic): point it at the soonest-arriving
    // alerted bus and push its ETA. A 5 s cadence is plenty (ETA shows whole
    // minutes) and avoids re-`show()`ing every second.
    if (_notificationsEnabled && tick % 5 == 0) {
      _autoTrackSoonestAlert();
      if (_ongoingKey != null) _refreshOngoing();
    }
    notifyListeners();
  }

  // ─── Live service composition ─────────────────────────────
  /// Returns the services for `code`, ETA-recomputed against `now` so the
  /// countdown is smooth between LTA polls.
  List<Service> liveServices(String code, {List<String> tracked = const []}) {
    final now = DateTime.now();
    final all = _ds.servicesFor(code);
    final filtered = tracked.isEmpty
        ? all
        : all.where((s) => tracked.contains(s.no)).toList();
    final out = filtered.map((s) {
      var etaSec = s.etaSec;
      var followingSec = s.followingSec;
      final a = s.arrivalDate;
      if (a != null) {
        etaSec = a.difference(now).inSeconds.clamp(0, 1 << 30);
      }
      final f = s.followingDate;
      if (f != null) {
        followingSec = f.difference(now).inSeconds.clamp(etaSec, 1 << 30);
      }
      return Service(
        no: s.no,
        dest: s.dest,
        etaSec: etaSec,
        followingSec: followingSec,
        load: s.load,
        wab: s.wab,
        deck: s.deck,
        monitored: s.monitored,
        arrivalDate: s.arrivalDate,
        followingDate: s.followingDate,
        thirdDate: s.thirdDate,
      );
    }).toList()..sort((a, b) => a.etaSec.compareTo(b.etaSec));
    return out;
  }

  int _walkMin(String code) {
    final loc = _loc.lastLocation;
    final stop = _ds.stopByCode[code];
    if (loc == null || stop == null) return 0;
    final d = haversine(loc.lat, loc.lon, stop.latitude, stop.longitude);
    return walkMinutesFor(d);
  }

  Pin? pinForCode(String code) {
    for (final p in _pins) {
      if (p.code == code) return p;
    }
    return null;
  }

  /// All pinned stops as Home cards (live).
  List<CardModel> get allPinnedCards => _pins.map(_cardFor).toList();

  CardModel _cardFor(Pin pin) {
    final name = _ds.stopName(pin.code);
    return CardModel(
      id: pin.code,
      label: pin.nickname.isEmpty ? name : pin.nickname,
      stopName: name,
      stopCode: pin.code,
      walkMin: _walkMin(pin.code),
      services: liveServices(pin.code),
    );
  }

  // ─── Pin mutations ────────────────────────────────────────
  bool isPinned(String code) => pinForCode(code) != null;

  /// Toggle a pin: pinned → unpinned (removed), unpinned → pinned (track all).
  void togglePin(String code) {
    final idx = _pins.indexWhere((p) => p.code == code);
    if (idx >= 0) {
      _pins = [..._pins]..removeAt(idx);
    } else {
      _pins = [..._pins, Pin(code: code, nickname: _ds.stopName(code))];
      _markRecentlyAdded(code);
    }
    _persistPins();
    notifyListeners();
  }

  /// Add a pin with an explicit tracked-subset. `tracked` must be non-empty;
  /// pass the full service list to track all (it normalises to `null`).
  void addPin(String code, List<String> tracked) {
    if (tracked.isEmpty) return; // empty subset means unpin — caller's bug
    final all = _ds.servicesFor(code).map((s) => s.no).toSet();
    final trackedSet = tracked.toSet();
    final normalised =
        trackedSet.containsAll(all) && all.containsAll(trackedSet)
        ? null
        : tracked.toList();

    final idx = _pins.indexWhere((p) => p.code == code);
    if (idx >= 0) {
      _pins[idx].tracked = normalised;
    } else {
      _pins = [
        ..._pins,
        Pin(code: code, nickname: _ds.stopName(code), tracked: normalised),
      ];
    }
    _markRecentlyAdded(code);
    _persistPins();
    notifyListeners();
  }

  void rename(String code, String newName) {
    final idx = _pins.indexWhere((p) => p.code == code);
    if (idx < 0) return;
    _pins[idx].nickname = newName.trim();
    _persistPins();
    notifyListeners();
  }

  /// True if `busNo` is shown on the Home card for this stop (pinned ⟺ ≥1 bus;
  /// nil `tracked` = all shown). Card VISIBILITY only — notification alerts are
  /// managed separately via `upsertAlert`/`removeAlert`.
  bool isTracked({required String code, required String busNo}) {
    final p = pinForCode(code);
    if (p == null) return false;
    final tr = p.tracked;
    if (tr == null) return true; // all
    return tr.contains(busNo);
  }

  /// Service numbers hidden from the Home card for this stop.
  Set<String> hiddenSet({
    required String code,
    List<String> allNos = const [],
  }) {
    final p = pinForCode(code);
    if (p == null) return allNos.toSet();
    final tr = p.tracked;
    if (tr == null) return const {}; // all shown
    return allNos.toSet().difference(tr.toSet());
  }

  /// Toggle a single service. Checking on an unpinned stop pins it tracking
  /// just that bus; unchecking the last tracked bus unpins (pinned ⟺ ≥1 bus).
  /// Card visibility only — notification alerts are managed separately via
  /// `upsertAlert`/`removeAlert`.
  void toggleTracked({
    required String code,
    required String busNo,
    List<String> allNos = const [],
  }) {
    final idx = _pins.indexWhere((p) => p.code == code);
    if (idx < 0) {
      _pins = [
        ..._pins,
        Pin(code: code, nickname: _ds.stopName(code), tracked: [busNo]),
      ];
      _persistPins();
      notifyListeners();
      return;
    }
    final p = _pins[idx];
    final shown = (p.tracked ?? allNos).toSet();
    if (shown.contains(busNo)) {
      shown.remove(busNo);
    } else {
      shown.add(busNo);
    }
    if (shown.isEmpty) {
      _pins = [..._pins]..removeAt(idx); // unchecked last → unpin
    } else if (shown.length == allNos.length && shown.containsAll(allNos)) {
      p.tracked = null; // back to "all"
    } else {
      p.tracked = shown.toList();
    }
    _persistPins();
    notifyListeners();
  }

  /// True iff the stop is pinned and tracking every service.
  bool allTracked(String code) {
    final p = pinForCode(code);
    return p != null && p.tracked == null;
  }

  /// Master toggle for "track everything at this stop". Untracking all
  /// equals unpinning (a stop with no buses isn't on Home).
  void setAllTracked({
    required String code,
    required List<String> allNos,
    required bool tracked,
  }) {
    final idx = _pins.indexWhere((p) => p.code == code);
    if (tracked) {
      if (idx >= 0) {
        _pins[idx].tracked = null; // all
      } else {
        _pins = [..._pins, Pin(code: code, nickname: _ds.stopName(code))];
        _markRecentlyAdded(code);
      }
    } else if (idx >= 0) {
      _pins = [..._pins]..removeAt(idx);
    }
    _persistPins();
    notifyListeners();
  }

  /// Re-arm scheduled arrival alerts after the tracked-set changes (e.g. a
  /// bell toggle on the stop screen), so it takes effect immediately instead
  /// of waiting for the next tick. No-op when notifications are globally off.
  Future<void> rescheduleIfNeeded() async {
    if (!_notificationsEnabled) return;
    await NotificationsService.shared.scheduleAlerts(_alerts, _ds.arrivals);
  }

  // ─── Ongoing "live tracking" notification (Android Live Activity analog)
  // One bus at a time, mirroring iOS's single Live Activity. `_ongoingKey`
  // is "<busNo>@<stopCode>"; the per-second tick pushes ETA updates.
  String? _ongoingKey;
  String? get ongoingKey => _ongoingKey;
  static String _liveKey(String busNo, String stopCode) => '$busNo@$stopCode';

  bool isOngoingActive({required String busNo, required String stopCode}) =>
      _ongoingKey == _liveKey(busNo, stopCode);

  // Consecutive ticks where the tracked service was absent from arrivals.
  // After [_ongoingMaxMisses] we finalise rather than show a frozen ETA
  // forever (the bus finished its trips, LTA stopped reporting it, etc.).
  int _ongoingMisses = 0;
  static const int _ongoingMaxMisses = 3; // ~15 s at the 5 s cadence

  /// Stops the ongoing tracker and clears its in-app state. Idempotent.
  Future<void> _stopOngoingTracker() async {
    if (_ongoingKey == null) return;
    _ongoingKey = null;
    _ongoingMisses = 0;
    await NotificationsService.shared.stopOngoing();
  }

  /// Automatically point the single live tracker at the soonest-arriving bus
  /// that has an arrival alert, handing off as the soonest changes. The
  /// lock-screen live view "just follows your next bus" — one at a time, to
  /// match the platform's single Live Activity — so the user never has to (and
  /// can't accidentally) pick it per-bus. Push alerts remain unlimited and
  /// independent of this.
  ///
  /// Driven from [_onTick]. Deliberately conservative about STOPPING: when no
  /// alerted bus is currently inbound it leaves any running tracker alone and
  /// lets [_refreshOngoing]'s miss-counter / the arrival finale finalise it, so
  /// a momentary feed gap doesn't kill the live view.
  void _autoTrackSoonestAlert() {
    if (!_notificationsEnabled) return;

    // If the current live bus is mid-finalise ("arriving now"), let
    // [_refreshOngoing] show that final state and clear the key before we hand
    // off to the next bus — don't preempt the finale.
    final current = _ongoingKey;
    if (current != null) {
      final at = current.indexOf('@');
      if (at > 0) {
        final cb = current.substring(0, at);
        final cs = current.substring(at + 1);
        final cur = liveServices(cs).where((s) => s.no == cb);
        if (cur.isNotEmpty && cur.first.etaSec <= 0) return;
      }
    }

    BusAlert? soonest;
    var soonestEta = 1 << 30;
    for (final a in _alerts) {
      if (a.kind != AlertKind.arrival) continue;
      final matches = liveServices(a.stopCode, tracked: [a.busNo]);
      if (matches.isEmpty) continue;
      final eta = matches.first.etaSec;
      if (eta <= 0) continue; // arrived — the arrival flow finalises this one
      if (eta < soonestEta) {
        soonestEta = eta;
        soonest = a;
      }
    }

    // No alerted bus inbound right now — leave any running tracker to the
    // miss-counter / removeAlert to tear down, rather than fighting them.
    if (soonest == null) return;

    final key = _liveKey(soonest.busNo, soonest.stopCode);
    if (_ongoingKey != key) {
      _ongoingKey = key;
      _ongoingMisses = 0;
      _ds.ensureArrivals(soonest.stopCode, force: true);
    }
  }

  /// Pushes the current ETA into the ongoing notification, or finalises it
  /// when the bus has arrived. Driven from [_onTick].
  Future<void> _refreshOngoing() async {
    final key = _ongoingKey;
    if (key == null) return;
    final at = key.indexOf('@');
    if (at < 0) return;
    final busNo = key.substring(0, at);
    final stopCode = key.substring(at + 1);
    final matches = liveServices(stopCode).where((s) => s.no == busNo).toList();
    if (matches.isEmpty) {
      // Data momentarily empty — keep the last shown state, but don't do it
      // forever: if the service has truly dropped out, finalise the tracker
      // instead of leaving a frozen ETA pinned indefinitely.
      _ongoingMisses++;
      if (_ongoingMisses >= _ongoingMaxMisses) {
        await NotificationsService.shared.stopOngoing();
        _ongoingKey = null;
        _ongoingMisses = 0;
        notifyListeners();
      }
      return;
    }
    _ongoingMisses = 0;
    final s = matches.first;
    if (s.etaSec <= 0) {
      await NotificationsService.shared.showOngoing(
        busNo: s.no,
        dest: s.dest,
        stopCode: stopCode,
        stopName: _ds.stopName(stopCode),
        etaSec: 0,
        finished: true,
      );
      _ongoingKey = null; // stop updating; leave the final "Arriving now"
      notifyListeners();
    } else {
      await NotificationsService.shared.showOngoing(
        busNo: s.no,
        dest: s.dest,
        stopCode: stopCode,
        stopName: _ds.stopName(stopCode),
        etaSec: s.etaSec,
      );
    }
  }

  void reorderPins(List<String> newCodes) {
    final byCode = {for (final p in _pins) p.code: p};
    final next = <Pin>[];
    for (final c in newCodes) {
      final p = byCode.remove(c);
      if (p != null) next.add(p);
    }
    next.addAll(byCode.values); // any not in newCodes preserved
    _pins = next;
    _persistPins();
    notifyListeners();
  }

  /// Reorder saved services to [newIds] (list of FavService.id). Any id not
  /// present in [newIds] is appended at the end (preserves items added
  /// concurrently). Persists immediately.
  void reorderFavServices(List<String> newIds) {
    final byId = {for (final f in _favServices) f.id: f};
    final next = <FavService>[];
    for (final id in newIds) {
      final f = byId.remove(id);
      if (f != null) next.add(f);
    }
    next.addAll(byId.values); // any not in newIds preserved
    _favServices = next;
    _persistFavServices();
    notifyListeners();
  }

  void _markRecentlyAdded(String code) {
    _recentlyAddedId = code;
    notifyListeners();
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (_recentlyAddedId == code) {
        _recentlyAddedId = null;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
