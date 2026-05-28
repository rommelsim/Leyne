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
import 'package:shared_preferences/shared_preferences.dart';

import '../data/changelog.dart';
import '../data/data_store.dart';
import '../data/geo.dart';
import '../data/models.dart';
import '../services/location_service.dart';
import '../services/notifications.dart';

/// Global ScaffoldMessenger key — lets AppModel surface in-app arrival
/// alerts as a banner from outside the widget tree. Wired into MaterialApp
/// in main.dart.
final GlobalKey<ScaffoldMessengerState> lyneMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

// Persistence keys — kept identical to the legacy ones in case a future
// data-portability tool needs to reconcile across platforms.
const _kPinsKey = 'lyne.pins';
const _kRecentsKey = 'lyne.recents';
const _kOnboardingDoneKey = 'lyne.onboardingDone';
const _kUse24hKey = 'lyne.use24h';
const _kThemeModeKey = 'lyne.themeMode';
const _kLocaleKey = 'lyne.locale';
const _kNotifKey = 'lyne.notifications';
const _kSearchRadiusKey = 'lyne.searchRadiusM';
const _kLastSeenVersionKey = 'lyne.lastSeenVersion';
const _kAlightKey = 'lyne.alight'; // JSON-encoded ActiveAlight

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
  // Display preference for 24-hour vs 12-hour clock in the LIVE header.
  // Defaults to true to match the SG locale convention.
  bool _use24h = true;
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
        await NotificationsService.shared.scheduleArrivalAlerts(
          pins: _pins, cards: allPinnedCards);
      } else {
        _notificationsEnabled = false;
        _prefs?.setBool(_kNotifKey, false);
      }
    } else {
      _notificationsEnabled = false;
      _prefs?.setBool(_kNotifKey, false);
      await NotificationsService.shared.clearAll();
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
    }
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
        busNo: busNo, stopCode: stopCode, stopName: stopName, fireAt: fireAt);
    _prefs?.setString(_kAlightKey, jsonEncode(_activeAlight!.toJson()));
    await NotificationsService.shared.scheduleAlightAlert(
      busNo: busNo, alightStopCode: stopCode,
      alightStopName: stopName, fireAt: fireAt);
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
    _use24h = _prefs!.getBool(_kUse24hKey) ?? true;
    final tm = _prefs!.getString(_kThemeModeKey);
    _themeMode = ThemeMode.values
        .firstWhere((m) => m.name == tm, orElse: () => ThemeMode.system);
    final lc = _prefs!.getString(_kLocaleKey);
    _locale = (lc == null || lc.isEmpty) ? null : Locale(lc);
    // Defaults to true on first run so onboarding's notification step +
    // the boot-time fallback can fire the system prompt without the user
    // having to discover Settings → Notifications first. Existing
    // installs that previously toggled this explicitly (true or false)
    // keep their stored value.
    _notificationsEnabled = _prefs!.getBool(_kNotifKey) ?? true;
    _searchRadiusM = _prefs!.getInt(_kSearchRadiusKey) ?? 500;
    _lastSeenVersion = _prefs!.getString(_kLastSeenVersionKey);

    final raw = _prefs!.getString(_kPinsKey);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        _pins = list.map(Pin.fromJson).toList();
      } catch (_) {/* corrupt — start empty */}
    }
    _recents = _prefs!.getStringList(_kRecentsKey) ?? const [];
    // Restore any in-flight alight ride so the picker still shows the
    // armed stop on reopen. We don't re-schedule the notification — the
    // system already holds the AlarmManager registration from when we
    // first armed it; re-adding would just create a duplicate.
    final alightRaw = _prefs!.getString(_kAlightKey);
    if (alightRaw != null) {
      try {
        _activeAlight = ActiveAlight.fromJson(
            jsonDecode(alightRaw) as Map<String, dynamic>);
      } catch (_) {/* corrupt — start empty */}
    }
    notifyListeners();
  }

  void _persistPins() {
    final p = _prefs;
    if (p == null) return;
    p.setString(_kPinsKey, jsonEncode(_pins.map((e) => e.toJson()).toList()));
  }

  void addRecent(String q) {
    final v = q.trim();
    if (v.isEmpty) return;
    final next = [v, ..._recents.where((r) => r.toLowerCase() != v.toLowerCase())];
    _recents = next.take(8).toList();
    _prefs?.setStringList(_kRecentsKey, _recents);
    notifyListeners();
  }

  // ─── Tick: smooth countdown + keep visible stops fresh ──
  void _onTick() {
    tick++;
    final codes = <String>{for (final p in _pins) p.code};
    for (final c in codes) {
      _ds.ensureArrivals(c);
    }
    // Re-arm scheduled arrival alerts every ~10 s — LTA's arrivalDate
    // values drift, and a coarse cadence is enough because notification
    // fire times are absolute (zonedSchedule registers an exact alarm
    // with the system, which keeps firing regardless of app lifecycle).
    if (_notificationsEnabled && tick % 10 == 0) {
      NotificationsService.shared.scheduleArrivalAlerts(
        pins: _pins, cards: allPinnedCards);
    }
    // Pull MRT/LRT disruption alerts on a slow cadence. DataStore
    // enforces a 60 s gate internally so this call is cheap.
    _ds.refreshTrainAlertsIfStale();
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
        followingSec = f
            .difference(now)
            .inSeconds
            .clamp(etaSec, 1 << 30);
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
    }).toList()
      ..sort((a, b) => a.etaSec.compareTo(b.etaSec));
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
      _pins = [
        ..._pins,
        Pin(code: code, nickname: _ds.stopName(code)),
      ];
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
    final normalised = trackedSet.containsAll(all) && all.containsAll(trackedSet)
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

  /// True if `busNo` is shown on Home for this stop. Not pinned → false.
  bool isTracked({required String code, required String busNo}) {
    final p = pinForCode(code);
    if (p == null) return false;
    final tr = p.tracked;
    if (tr == null) return true; // all
    return tr.contains(busNo);
  }

  /// Service numbers hidden from the Home card for this stop.
  Set<String> hiddenSet({required String code, List<String> allNos = const []}) {
    final p = pinForCode(code);
    if (p == null) return allNos.toSet();
    final tr = p.tracked;
    if (tr == null) return const {}; // all shown
    return allNos.toSet().difference(tr.toSet());
  }

  /// Toggle a single service. Checking on an unpinned stop pins it tracking
  /// just that bus; unchecking the last tracked bus unpins (pinned ⟺ ≥1 bus).
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
        _pins = [
          ..._pins,
          Pin(code: code, nickname: _ds.stopName(code)),
        ];
        _markRecentlyAdded(code);
      }
    } else if (idx >= 0) {
      _pins = [..._pins]..removeAt(idx);
    }
    _persistPins();
    notifyListeners();
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
