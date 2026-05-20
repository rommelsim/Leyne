// LTA DataMall configuration.
//
// The AccountKey is supplied at build time via --dart-define:
//
//   flutter run --dart-define=LTA_API_KEY=<key>
//   flutter build ios --dart-define=LTA_API_KEY=<key>
//
// Locally, export it once in your shell profile so IDEs / `flutter run`
// pick it up:
//
//   export LTA_API_KEY=…   # ~/.zshrc
//   flutter run --dart-define=LTA_API_KEY=$LTA_API_KEY
//
// Never commit the key. The legacy iOS app (legacy/ios-native/Lyne/
// LTAConfig.swift) hardcoded it because DataMall keys are low-sensitivity
// (public open-data, rate-limited), but the Flutter rebuild keeps it out of
// source as good hygiene.

import 'package:flutter/foundation.dart';

class LtaConfig {
  /// LTA DataMall AccountKey. Required for all requests. Empty when the
  /// build forgot to pass --dart-define=LTA_API_KEY=… ; that surfaces fast
  /// as a 401 on the first request rather than silently using a stale key.
  static const String accountKey = String.fromEnvironment('LTA_API_KEY');

  /// LTA DataMall base URL — all endpoints are paths under this.
  static final Uri baseUrl =
      Uri.parse('https://datamall2.mytransport.sg/ltaodataservice');

  /// Records returned per page for bulk datasets ($skip pagination).
  static const int pageSize = 500;

  /// How often to re-poll a stop's live arrivals (LTA refresh is ~20s, we
  /// poll 25s to stay polite). Matches legacy iOS.
  static const Duration arrivalRefresh = Duration(seconds: 25);

  /// Bulk reference datasets (Bus Stops, Bus Services, Bus Routes) are
  /// "ad hoc" per LTA's guidance — cache on disk and refresh weekly.
  static const Duration referenceCacheMaxAge = Duration(days: 7);

  /// Assert the key is wired before any network call. Call from main()
  /// behind a debug-only guard so production never crashes here.
  static void assertConfigured() {
    if (kDebugMode && accountKey.isEmpty) {
      // ignore: avoid_print
      print('⚠️  LTA_API_KEY is empty. Pass it via --dart-define=LTA_API_KEY=… '
          'or set it in your IDE run configuration.');
    }
  }
}
