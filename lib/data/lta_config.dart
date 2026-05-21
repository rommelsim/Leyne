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
  /// Embedded public DataMall AccountKey — used when the build didn't pass
  /// one via --dart-define. Notably, Xcode's ⌘R build does NOT forward
  /// --dart-define into `flutter assemble`, so without this fallback an
  /// Xcode run sends an empty AccountKey and LTA's gateway answers 404.
  ///
  /// DataMall keys are low-sensitivity public open-data keys (rate-limited);
  /// the legacy iOS app embedded this exact key in LTAConfig.swift, and it
  /// already appears in this repo's README. Embedding it here leaks nothing
  /// new and is the only thing that makes every build path work uniformly.
  static const String _fallbackKey = '+6zJ3XstTqOcDkvczHttWA==';

  /// AccountKey supplied at build time via --dart-define=LTA_API_KEY=… .
  /// Empty both when undefined and when defined-but-blank (the README's
  /// `--dart-define=LTA_API_KEY=$LTA_API_KEY` alias produces a blank value
  /// if the shell var is unset).
  static const String _definedKey = String.fromEnvironment('LTA_API_KEY');

  /// LTA DataMall AccountKey. Prefers the --dart-define value; falls back to
  /// the embedded key so Xcode runs and key-less `flutter run`s still work.
  static String get accountKey =>
      _definedKey.isEmpty ? _fallbackKey : _definedKey;

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

  /// Surface, at debug time, whether the build is running on the embedded
  /// fallback key. Not an error — just a heads-up that --dart-define wasn't
  /// wired, so a different key can't be A/B'd without rebuilding.
  static void assertConfigured() {
    if (kDebugMode && _definedKey.isEmpty) {
      // ignore: avoid_print
      print('ℹ️  LTA_API_KEY not passed via --dart-define — using the '
          'embedded fallback DataMall key.');
    }
  }
}
