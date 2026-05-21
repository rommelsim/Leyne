// 320x50 banner host. Reserves 50pt vertically regardless of fill state
// so the layout doesn't jump when an ad lands.
//
// Ad unit ID is gated by an explicit build-time flag, NOT by
// kDebugMode — TestFlight and Play Internal builds are release-mode
// builds, so a kDebugMode gate would silently serve real ads to
// internal testers. Wrong default. Instead:
//
//   • App Store / Play Store (public release): build with NO flag.
//     The production unit ca-app-pub-5864511655536507/8034707188 is
//     requested. Real ads, real revenue.
//   • TestFlight / Play Internal (closed beta): build with
//     --dart-define=LYNE_ADS_TEST=true. Google's universal test unit is
//     requested instead. Zero risk of testers seeing/tapping real ads.
//   • Local `flutter run` (debug): also serves the production unit, but
//     the Mobile Ads SDK auto-treats the iOS Simulator (and Android
//     Emulator) as a test device, so the sim renders "Test Ad" creatives
//     anyway. To dev against the production unit on a real device
//     without earning fake impressions, add the device's AdMob test
//     hash to kTestDeviceIdentifiers in lib/services/ad_consent.dart.
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
  // Debug builds (`flutter run`, Xcode ⌘R) always use Google's universal
  // test units so a "Test Ad" creative shows on any device — including a
  // physical iPhone, which the SDK does NOT auto-treat as a test device.
  //
  // Release builds are unaffected: TestFlight / Play Internal still opt in
  // via --dart-define=LYNE_ADS_TEST=true, and a store build (release, no
  // flag) serves the production unit. A debug build can never reach a
  // store, so this can't leak test creatives into production.
  if (kLyneAdsTest || kDebugMode) {
    // Google's official test banner units — always serve "Test Ad"
    // creatives, never count as impressions for any account.
    return Platform.isAndroid
        ? 'ca-app-pub-3940256099942544/6300978111'
        : 'ca-app-pub-3940256099942544/2934735716';
  }
  // Production unit on both platforms (this app's AdMob console setup).
  return 'ca-app-pub-5864511655536507/8034707188';
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
