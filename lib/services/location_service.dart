// CoreLocation/Geolocator wrapper — When-In-Use, for the Nearby tab.
//
// Mirrors legacy/ios-native/Lyne/LocationManager.swift: requests permission,
// pushes updates into DataStore.updateNearby, and exposes a ChangeNotifier
// for the permission-prompt UI to react to.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../data/data_store.dart';

enum LocAuth { notDetermined, denied, deniedForever, authorized }

class LocationService extends ChangeNotifier {
  LocationService._();
  static final LocationService shared = LocationService._();

  LocAuth _auth = LocAuth.notDetermined;
  LocAuth get auth => _auth;

  bool get authorized => _auth == LocAuth.authorized;

  ({double lat, double lon})? _lastLocation;
  ({double lat, double lon})? get lastLocation => _lastLocation;

  StreamSubscription<Position>? _sub;

  /// Read current permission status without prompting. Safe to call from
  /// initState; doesn't trigger the OS dialog.
  Future<void> refreshStatus() async {
    final p = await Geolocator.checkPermission();
    _auth = _toAuth(p);
    notifyListeners();
  }

  /// Prompt the user (if `notDetermined`) and start the stream if granted.
  /// On `deniedForever` the UI should offer to open system settings.
  Future<void> requestAndStart() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _auth = LocAuth.denied;
      notifyListeners();
      return;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    _auth = _toAuth(p);
    notifyListeners();
    if (authorized) await _start();
  }

  /// Open the OS app-settings page (for `deniedForever` recovery).
  Future<void> openAppSettings() => Geolocator.openAppSettings();

  Future<void> _start() async {
    await _sub?.cancel();
    // One-shot last-known to warm Nearby instantly, then a stream for live
    // updates. distanceFilter = 50m matches the iOS ~100m accuracy.
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) _ingest(last);
    } catch (_) {/* ignore */}
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 50,
      ),
    ).listen(_ingest, onError: (_) {/* keep last */});
  }

  void _ingest(Position p) {
    _lastLocation = (lat: p.latitude, lon: p.longitude);
    DataStore.shared.updateNearby(p.latitude, p.longitude);
    notifyListeners();
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  static LocAuth _toAuth(LocationPermission p) {
    switch (p) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocAuth.authorized;
      case LocationPermission.denied:
        return LocAuth.denied;
      case LocationPermission.deniedForever:
        return LocAuth.deniedForever;
      case LocationPermission.unableToDetermine:
        return LocAuth.notDetermined;
    }
  }
}
