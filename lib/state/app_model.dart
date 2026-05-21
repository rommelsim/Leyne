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

import '../data/data_store.dart';
import '../data/geo.dart';
import '../data/models.dart';
import '../services/location_service.dart';
import '../theme.dart';

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
    notifyListeners();
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

  // Arrival-alert notifications. When on, the 1-second tick fires a local
  // notification as a tracked pinned bus crosses the near threshold.
  bool _notificationsEnabled = false;
  bool get notificationsEnabled => _notificationsEnabled;

  void setNotificationsEnabled(bool v) {
    if (_notificationsEnabled == v) return;
    _notificationsEnabled = v;
    _prefs?.setBool(_kNotifKey, v);
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

  // Keys ('code|no') of services already alerted for their current bus.
  // Re-armed once the service's ETA climbs back above 5 min — i.e. the
  // next bus — so each bus alerts at most once.
  final Set<String> _alerted = {};

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
    _notificationsEnabled = _prefs!.getBool(_kNotifKey) ?? false;
    _searchRadiusM = _prefs!.getInt(_kSearchRadiusKey) ?? 500;

    final raw = _prefs!.getString(_kPinsKey);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        _pins = list.map(Pin.fromJson).toList();
      } catch (_) {/* corrupt — start empty */}
    }
    _recents = _prefs!.getStringList(_kRecentsKey) ?? const [];
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
    _checkArrivalAlerts();
    notifyListeners();
  }

  // Fire an in-app alert as a tracked pinned bus crosses the near
  // threshold. Foreground-only by design — see NotificationsScreen.
  void _checkArrivalAlerts() {
    if (!_notificationsEnabled) return;
    for (final p in _pins) {
      final tracked = p.tracked;
      for (final s in liveServices(p.code)) {
        if (tracked != null && !tracked.contains(s.no)) continue;
        final key = '${p.code}|${s.no}';
        if (s.etaSec > 300) {
          _alerted.remove(key); // next bus — re-arm
        } else if (s.etaSec <= 90 && _alerted.add(key)) {
          _fireArrivalAlert(p.code, s);
        }
      }
    }
  }

  void _fireArrivalAlert(String code, Service s) {
    final messenger = lyneMessengerKey.currentState;
    final ctx = lyneMessengerKey.currentContext;
    if (messenger == null || ctx == null) return;
    final t = ctx.t;
    final stopName = _ds.stopName(code);
    final mins = s.etaSec ~/ 60;
    final when = mins <= 0 ? 'arriving now' : 'in $mins min';
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(
        backgroundColor: t.surfaceHi,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        content: Row(
          children: [
            Icon(Icons.directions_bus, size: 18, color: t.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Bus ${s.no} $when — $stopName',
                  style: t.sans(13, color: t.fg)),
            ),
          ],
        ),
      ));
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
