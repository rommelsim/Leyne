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
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

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

    // 2. ATT — iOS only. requestTrackingAuthorization is a no-op on
    //    Android and on iOS versions < 14.5. The OS only presents the
    //    prompt once per install; subsequent calls return the stored
    //    status.
    try {
      if (Platform.isIOS) {
        await AppTrackingTransparency.requestTrackingAuthorization();
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[ads] ATT step skipped: $e');
      }
    }

    // 3. Initialise Mobile Ads SDK.
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
