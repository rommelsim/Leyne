// AppModel — pin/tracked/recents state + a 1-second tick for live ETA
// countdowns.
//
// Ports legacy/ios-native/Lyne/AppModel.swift, minus the bits that belong
// to deferred tasks:
//   • Live Activity (ActivityKit) — Task #12, via MethodChannel bridge.
//   • Onboarding flow — Task #9 (Settings).
//   • App Group / WidgetKit mirror — Task #12.
//
// State management is plain ChangeNotifier; persistence is
// shared_preferences keyed under `lyne.*` (matches the legacy keys).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/data_store.dart';
import '../data/geo.dart';
import '../data/models.dart';
import '../services/location_service.dart';

// Persistence keys — kept identical to the legacy ones in case a future
// data-portability tool needs to reconcile across platforms.
const _kPinsKey = 'lyne.pins';
const _kRecentsKey = 'lyne.recents';
const _kSoundKey = 'lyne.sound';
const _kHapticKey = 'lyne.haptic';

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

  // ─── Settings (persisted) ─────────────────────────────────
  bool _sound = true;
  bool get sound => _sound;
  set sound(bool v) {
    _sound = v;
    _prefs?.setBool(_kSoundKey, v);
    notifyListeners();
  }

  bool _haptic = true;
  bool get haptic => _haptic;
  set haptic(bool v) {
    _haptic = v;
    _prefs?.setBool(_kHapticKey, v);
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
    _sound = _prefs!.getBool(_kSoundKey) ?? true;
    _haptic = _prefs!.getBool(_kHapticKey) ?? true;

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
