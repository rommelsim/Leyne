// 320x50 banner host. Reserves 50pt vertically regardless of fill state
// so the layout doesn't jump when an ad lands.
//
// Ad unit ID is gated by platform + explicit build flag, NOT by
// kDebugMode alone — TestFlight builds are release-mode, so a
// kDebugMode gate would silently serve real ads to internal testers.
// The matrix:
//
//   • iOS App Store (public release): build with NO flag. The iOS
//     production banner unit is requested. Real ads, real revenue.
//   • iOS TestFlight (closed beta): build with
//     --dart-define=LYNE_ADS_TEST=true. Google's universal test unit
//     is requested. Zero risk of testers tapping real ads.
//   • iOS debug (`flutter run`): test unit via the kDebugMode branch.
//   • Any Android build: ALWAYS test unit. Android distribution is
//     paused; configure a real AdMob unit and remove the platform
//     short-circuit in _bannerUnitId before re-shipping Android.
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
import 'dart:io';

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

/// Resolve the banner ad unit ID at runtime.
String _bannerUnitId() {
  // Android: always serve Google's universal test unit. Distribution
  // is paused, so a real unit would be dead code at best and a flagged
  // publisher ID at worst.
  if (Platform.isAndroid) {
    return 'ca-app-pub-3940256099942544/6300978111';
  }
  // iOS: test unit in debug / explicit test-flag builds; production
  // unit otherwise. A debug build can never reach the App Store, so
  // this can't leak test creatives into production.
  if (kLyneAdsTest || kDebugMode) {
    return 'ca-app-pub-3940256099942544/2934735716';
  }
  return 'ca-app-pub-6816620800052795/8532706109';
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
    if (kLyneScreenshotMode) return; // skip ad lifecycle entirely
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
    // Screenshot mode — no banner at all, no reservation. Bottom nav
    // sits flush against the screen edge for a cleaner marketing image.
    if (kLyneScreenshotMode) return const SizedBox.shrink();

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
