// 320x50 banner host. Reserves 50pt vertically regardless of fill state
// so the layout doesn't jump when an ad lands.
//
// Ad unit ID is gated by an explicit build flag, NOT by kDebugMode alone —
// TestFlight / Play Internal builds are release-mode, so a kDebugMode gate
// would silently serve real ads to internal testers. The matrix:
//
//   • Public release (Play / App Store): build with NO flag. The real
//     production banner unit is requested. Real ads, real revenue.
//   • Closed beta (TestFlight / Play Internal): build with
//     --dart-define=LYNE_ADS_TEST=true. Google's universal test unit
//     is requested. Zero risk of testers tapping real ads.
//   • `flutter run` (debug): test unit via the kDebugMode branch.
//
// iOS ships from the SwiftUI app at `ios-native/`; this widget powers
// the Android build only.
//
// To dev against the iOS production unit on a real device without
// earning fake impressions, add the device's AdMob test hash to
// kTestDeviceIdentifiers in lib/services/ad_consent.dart.
//
// Renders nothing (empty SizedBox of the same height) until both
// AdConsent.started AND the ad loads — that way:
//   1. We never request an ad before UMP + ATT have resolved.
//   2. We never fill the space with a half-loaded ad placeholder.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/ad_consent.dart';
import '../theme.dart';

/// True when this build was compiled with `--dart-define=LYNE_ADS_TEST=true`
/// (TestFlight / Play Internal). Defaults to `false`, so a regular
/// `flutter build ios --release` for the App Store uses the production
/// unit. See the file-level comment above for the full matrix.
const bool kLyneAdsTest =
    bool.fromEnvironment('LYNE_ADS_TEST', defaultValue: false);

/// True when this build was compiled with
/// `--dart-define=LYNE_SCREENSHOT_MODE=true`. Suppresses the ad banner
/// entirely (no 50pt reservation, no SDK request) so App Store / Play
/// Store marketing screenshots focus on the app's value, not on the
/// "Nice job! …" test ad creative. Use this only when capturing
/// screenshots — every other build path should leave the flag off so
/// the slot is reserved correctly.
const bool kLyneScreenshotMode =
    bool.fromEnvironment('LYNE_SCREENSHOT_MODE', defaultValue: false);

/// MASTER SWITCH for ads. Set to `false` to ship a no-ads build (e.g.
/// during an AdMob account suspension) — the banner widget short-circuits
/// to an empty SizedBox, no SDK request is ever made, and AdConsent stays
/// a no-op.
const bool kLyneAdsEnabled = true;

/// Resolve the banner ad unit ID at runtime. Flutter powers the Android
/// build only — iOS ships via the SwiftUI app at `ios-native/`.
///   • DEBUG or LYNE_ADS_TEST=true: Google's universal Android test unit
///   • RELEASE (public Play Store): leyne0000 production banner unit
String _bannerUnitId() {
  if (kDebugMode || kLyneAdsTest) {
    return 'ca-app-pub-3940256099942544/6300978111';
  }
  return 'ca-app-pub-5864511655536507/6513878972';
}

class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() {
    // In screenshot mode the widget returns a zero-size shrink at build
    // time; we still instantiate the State for type consistency but it
    // never requests an ad.
    return _AdBannerState();
  }
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  Timer? _retry;

  @override
  void initState() {
    super.initState();
    // Hard short-circuit when ads are disabled at the master switch OR
    // we're in screenshot-capture mode. No SDK call, no retries.
    if (!kLyneAdsEnabled || kLyneScreenshotMode) return;
    _attemptLoad();
  }

  void _attemptLoad() {
    // Wait for consent + MobileAds init before requesting. Poll lightly
    // — the consent flow lands within a couple of seconds in the worst
    // case, so 4×500ms checks is enough.
    if (!AdConsent.started) {
      _retry?.cancel();
      _retry = Timer(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        _attemptLoad();
      });
      return;
    }
    _load();
  }

  void _load() {
    final ad = BannerAd(
      adUnitId: _bannerUnitId(),
      size: AdSize.banner, // 320x50
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (kDebugMode) {
            // ignore: avoid_print
            print('[ads] banner failed: ${error.message}');
          }
        },
      ),
    );
    _ad = ad;
    ad.load();
  }

  @override
  void dispose() {
    _retry?.cancel();
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Master ad switch OR screenshot mode — no banner at all, no
    // reservation. Bottom nav sits flush against the screen edge.
    if (!kLyneAdsEnabled || kLyneScreenshotMode) {
      return const SizedBox.shrink();
    }

    final t = context.t;
    // Reserve the slot even when nothing is loaded so the layout doesn't
    // shift when an ad arrives. Thin hairline above to separate from the
    // navigation bar.
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.line)),
      ),
      child: Center(
        child: _loaded && _ad != null
            ? SizedBox(
                width: _ad!.size.width.toDouble(),
                height: _ad!.size.height.toDouble(),
                child: AdWidget(ad: _ad!),
              )
            : null,
      ),
    );
  }
}
