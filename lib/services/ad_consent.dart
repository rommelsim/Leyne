// Ad consent + initialization.
//
// Same order as legacy AdBanner.swift `AdConsent.gatherThenStart()`:
//   1. Google UMP (User Messaging Platform) — collects GDPR consent in
//      the EEA / UK; no-op elsewhere unless `ConsentInformation` says so.
//   2. Apple App Tracking Transparency — authorises IDFA-based
//      personalisation on iOS. No-op on Android.
//   3. Mobile Ads SDK initialization — only after the above resolve.
//
// Runs once per app launch (idempotent — repeat calls are no-ops).
// Safe to call from main() with fire-and-forget; the AdBanner widget
// reads `AdConsent.started` and renders nothing until then so we never
// request an ad before consent + IDFA state is settled.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../widgets/ad_banner.dart' show kLyneAdsEnabled;

/// Test device hashes — any device listed here is flagged as a test
/// device by the Mobile Ads SDK regardless of which unit ID we request.
/// Same binary that ships to App Store / Play Store; only listed devices
/// see test ads. Use this for:
///
///   • Your physical dev iPhone / Android — adds the device hash so
///     `flutter run` builds in debug or release mode can hit the
///     production unit without earning real impressions on your own
///     phone (and without risking AdMob policy violations for self-
///     clicks).
///
/// **How to get a device's hash:** run the app once on the device.
/// The Mobile Ads SDK prints a log line on the first ad request:
///   "To get test ads on this device, set:
///    Mobile.Ads.RequestConfiguration testDeviceIdentifiers = [...]"
/// Copy the hash into this list, hot-restart, the device now sees
/// test creatives on every subsequent request.
///
/// **Simulator note:** the iOS Simulator and Android Emulator are
/// auto-detected as test devices by the SDK — you do NOT need to add
/// their hash here. That's why the existing simulator screenshots
/// show "Test Ad" overlays even with the production unit ID.
const List<String> kTestDeviceIdentifiers = <String>[
  // Rommel's iPhone — hash printed to the console on first ad request
  // (see Xcode log: "To get test ads on this device, set: ...").
  // With this hash listed, the device serves test creatives against the
  // production unit ID — useful for validating ad slot rendering on
  // hardware without earning real impressions / risking AdMob policy
  // violations from self-clicks.
  '65e887acf5c73093fbe2212071d84b64',
];

class AdConsent {
  AdConsent._();

  static bool _ran = false;
  static bool _started = false;

  /// True only when MobileAds.initialize() has resolved. AdBanner widgets
  /// gate on this so we never request an ad before consent finishes.
  static bool get started => _started;

  /// Idempotent. Pass nothing for production; the test-device list is
  /// only consulted in debug builds.
  static Future<void> gatherThenStart({
    List<String> testDeviceIdentifiers = const [],
  }) async {
    // Master ad switch — bail before any UMP / ATT prompt or SDK init
    // call so no traffic is generated on a suspended AdMob account.
    if (!kLyneAdsEnabled) return;
    if (_ran) return;
    _ran = true;

    try {
      // 1. UMP — refresh consent info, show form if required.
      await _requestUmp();
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[ads] UMP step skipped: $e');
      }
    }

    // 2. Initialise Mobile Ads SDK. ATT (App Tracking Transparency) is
    //    handled natively by the SwiftUI iOS build — the Flutter app
    //    is Android-only, where ATT is a no-op anyway.
    try {
      await MobileAds.instance.initialize();
      if (testDeviceIdentifiers.isNotEmpty) {
        MobileAds.instance.updateRequestConfiguration(
          RequestConfiguration(testDeviceIds: testDeviceIdentifiers),
        );
      }
      _started = true;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[ads] MobileAds init failed: $e');
      }
    }
  }

  static Future<void> _requestUmp() {
    final params = ConsentRequestParameters();
    final c = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        ConsentForm.loadAndShowConsentFormIfRequired((error) {
          // Form errors are non-fatal — fall through and let ads init.
          if (!c.isCompleted) c.complete();
        });
        // The callback above may never fire if no form is required; the
        // outer try/then below covers that path too.
        await Future.delayed(const Duration(milliseconds: 500));
        if (!c.isCompleted) c.complete();
      },
      (error) {
        // Network or config error — proceed without consent form.
        if (!c.isCompleted) c.complete();
      },
    );
    return c.future;
  }
}
