// WidgetBridge — Dart → Android home-screen widget data publisher.
//
// The Android home-screen widgets (Pinned Stop / Nearest Stop / Favourite
// Service) are written in Kotlin/Glance and CANNOT call into the Dart runtime.
// This bridge mirrors the app's live state into a plugin-managed
// SharedPreferences file (via the `home_widget` package) that the Glance
// widgets read on every redraw. It is the Android analog of the iOS App Group
// mirror (AppModel.mirrorNearbyToWidget / mirrorFavServicesToWidget +
// WidgetCenter.reloadAllTimelines) — see ios-native/Leyne/AppModel.swift.
//
// CONTRACT (Dart writes these keys; Kotlin WidgetDataRepository reads them):
//
//   leyne.widget.pins      String  JSON array
//       [{"code":"53061","name":"Bef Bishan Stn"}]
//   leyne.widget.nearby    String  JSON object (or absent)
//       {"code":"83139","name":"Opp Blk 512","walkMin":3}
//   leyne.widget.favs      String  JSON array (stopName + dest resolved here,
//                                  because FavService stores only {no, stop})
//       [{"no":"186","stopCode":"11389","stopName":"Farrer Rd Stn","dest":"St Michael's Ter"}]
//   leyne.widget.arrivals.<stopCode>   String  JSON object
//       {"fetchedAt":1718700000000,"rows":[
//         {"no":"88","eta1":2,"eta2":9,"eta3":20,"mon1":true}]}
//
// ETA fields (eta1/eta2/eta3) are MINUTES (0 ⇒ "Arr"); the Dart Service model
// stores seconds (etaSec) + DateTime, so the conversion happens here so the
// Kotlin side never has to. `mon1` mirrors Service.monitored (false ⇒ the
// faint "~" scheduled prefix, per the feedback_timely_over_honest rule).
//
// Widget taps are NOT handled here: each Glance widget launches MainActivity
// with an `ACTION_VIEW lyne://…` intent, which flows through the existing
// app_links → DeepLinkService pipeline (scheme-agnostic, path-only). No
// home_widget click-stream wiring is needed.
//
// iOS is a no-op: WidgetKit handles iOS natively, so every method early-returns
// off Android.

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../data/data_store.dart';
import '../data/models.dart';
import '../state/app_model.dart';

class WidgetBridge {
  WidgetBridge._();
  static final WidgetBridge instance = WidgetBridge._();

  // SharedPreferences keys — must match WidgetDataRepository.kt.
  static const _kNearby = 'leyne.widget.nearby';
  static const _kFavs = 'leyne.widget.favs';
  static String _arrivalsKey(String code) => 'leyne.widget.arrivals.$code';

  // Fully-qualified Glance receivers — must match AndroidManifest.xml.
  static const _pkg = 'com.leyne.leyne.widget';
  static const _nearbyReceiver = '$_pkg.LeyneNearbyWidgetReceiver';
  static const _favReceiver = '$_pkg.LeyneFavServiceWidgetReceiver';

  bool get _enabled => !kIsWeb && Platform.isAndroid;

  AppModel get _app => AppModel.shared;
  DataStore get _ds => DataStore.shared;

  /// Cold-start / bulk seed — pushes every key from current state and refreshes
  /// the widgets. Safe to call repeatedly (e.g. once after AppModel.load() and
  /// again once reference data resolves, so fav stop names fill in).
  Future<void> pushAll() async {
    if (!_enabled) return;
    await _writeFavs();
    await _writeNearby();
    await _updateAll();
  }

  /// Favourite services changed — re-publish (resolving stop name + dest) +
  /// redraw the favourite-service widget.
  Future<void> pushFavs() async {
    if (!_enabled) return;
    await _writeFavs();
    await _update(_favReceiver);
  }

  /// The nearest stop was re-resolved after a location fix — re-publish.
  Future<void> pushNearby() async {
    if (!_enabled) return;
    await _writeNearby();
    await _update(_nearbyReceiver);
  }

  /// A stop's live arrivals settled — mirror them and nudge the favourite-
  /// service widget (it may be showing this stop). Throttled naturally by the
  /// 25s arrival-refresh gate in DataStore, so this fires at most ~once/25s
  /// per active stop.
  Future<void> pushArrivals(String code, List<Service> services) async {
    if (!_enabled) return;
    await _writeArrivals(code, services);
    await _update(_favReceiver);
  }

  // ─── Writers ──────────────────────────────────────────────────────────

  Future<void> _writeFavs() async {
    final arr = <Map<String, dynamic>>[];
    for (final f in _app.favServices) {
      final stopCode = f.stop ?? '';
      final stopName = stopCode.isEmpty ? '' : _ds.stopName(stopCode);
      // Destination isn't stored on FavService — resolve it from the loaded
      // arrivals for this stop (the matching service's dest), else leave blank.
      var dest = '';
      if (stopCode.isNotEmpty) {
        for (final s in _ds.servicesFor(stopCode)) {
          if (s.no == f.no) {
            dest = s.dest;
            break;
          }
        }
        await _writeArrivals(stopCode, _ds.servicesFor(stopCode));
      }
      arr.add({
        'no': f.no,
        'stopCode': stopCode,
        'stopName': stopName,
        'dest': dest,
      });
    }
    await _save(_kFavs, jsonEncode(arr));
  }

  Future<void> _writeNearby() async {
    final list = _ds.nearby;
    if (list.isEmpty) {
      await _save(_kNearby, ''); // absent ⇒ widget shows empty state
      return;
    }
    final n = list.first;
    await _save(
      _kNearby,
      jsonEncode({'code': n.stopCode, 'name': n.stopName, 'walkMin': n.walkMin}),
    );
  }

  Future<void> _writeArrivals(String code, List<Service> services) async {
    final rows = services.take(6).map((s) {
      return {
        'no': s.no,
        'eta1': _minutes(s.etaSec),
        'eta2': _minutes(s.followingSec),
        if (s.thirdDate != null) 'eta3': _minutesUntil(s.thirdDate!),
        'mon1': s.monitored,
      };
    }).toList();
    await _save(
      _arrivalsKey(code),
      jsonEncode({
        'fetchedAt': DateTime.now().millisecondsSinceEpoch,
        'rows': rows,
      }),
    );
  }

  // ─── home_widget plumbing (best-effort; never throws into the app) ──────

  Future<void> _save(String key, String value) async {
    try {
      await HomeWidget.saveWidgetData<String>(key, value);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[widget] save $key failed: $e');
      }
    }
  }

  Future<void> _update(String receiver) async {
    try {
      await HomeWidget.updateWidget(qualifiedAndroidName: receiver);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[widget] update $receiver failed: $e');
      }
    }
  }

  Future<void> _updateAll() async {
    await _update(_nearbyReceiver);
    await _update(_favReceiver);
  }

  /// Whole minutes until arrival; 0 for "Arr" (anything under a minute), so the
  /// widget matches the app's fmtEta semantics (models.dart).
  int _minutes(int seconds) => seconds <= 0 ? 0 : seconds ~/ 60;

  int _minutesUntil(DateTime when) =>
      _minutes(when.difference(DateTime.now()).inSeconds);
}
