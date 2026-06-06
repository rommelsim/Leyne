// Anchored-adaptive banner host. Reserves the SDK-reported adaptive height
// (~50–60pt on phones) regardless of fill state so the layout doesn't jump
// when an ad lands. Adaptive banners fill the device width — better fill +
// eCPM than a fixed 320×50 — at a COMPACT height: we deliberately use the
// standard, not the taller "Large", variant for a lighter footprint on every
// screen. Falls back to the standard 320×50 banner if the size can't resolve.
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

/// True when this build should serve Google's universal TEST ad unit instead
/// of the production banner.
///
/// Defaults to `false` so the source contract matches the build scripts and
/// this file's header: a plain `flutter build appbundle --release`
/// (build-android-prod.sh, no flag) serves the REAL production unit and earns
/// revenue. Safe-by-default — an accidental no-flag release can never silently
/// ship $0 test ads to the Play Store.
///
/// The closed-testing track opts IN explicitly: build-android-closed-test.sh
/// passes `--dart-define=LYNE_ADS_TEST=true`, so alpha/beta testers still see
/// "Test Ad" creatives and can never trigger AdMob invalid-traffic detection
/// on the live unit. (DEBUG builds force the test unit regardless, below.)
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
///   • RELEASE (public Play Store): production banner unit (Leyne
///     Google AdMob account, leyne0000@gmail.com, ca-app-pub-5864511655536507)
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
  // Adaptive size, resolved once before the first request. Drives the
  // reserved slot height so it matches the creative the SDK returns.
  AnchoredAdaptiveBannerAdSize? _size;

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
    unawaited(_load());
  }

  Future<void> _load() async {
    // Resolve the anchored adaptive size for the screen width first, then
    // request. Adaptive fills the width and lets AdMob choose the height —
    // higher fill + eCPM than a fixed 320×50. Width comes from the view
    // (no BuildContext needed, so this stays callable from initState/timer).
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final widthDip = (view.physicalSize.width / view.devicePixelRatio).round();
    // Standard anchored adaptive — compact, width-filling banner (~50–60pt),
    // chosen over the taller "Large" variant for a lighter footprint on every
    // screen: the width fill is the main eCPM win over a fixed 320×50; the
    // extra Large height is the smaller increment, traded here for content
    // space. google_mobile_ads 8 deprecates this getter in favour of Large —
    // intentional, hence the ignore. Matches the iOS portraitAnchoredAdaptiveBanner.
    // ignore: deprecated_member_use
    final adaptive = await AdSize.getAnchoredAdaptiveBannerAdSize(
      Orientation.portrait,
      widthDip,
    );
    if (!mounted) return;
    if (adaptive != null) {
      // Reserve the adaptive height up front so the slot doesn't jump when
      // the creative lands.
      setState(() => _size = adaptive);
    }

    final ad = BannerAd(
      adUnitId: _bannerUnitId(),
      // Fall back to the standard banner if the adaptive size is unavailable
      // (e.g. width not yet known) — still serves, just non-adaptive.
      size: adaptive ?? AdSize.banner,
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
    // navigation bar. Height tracks the adaptive size once resolved, falling
    // back to 50 before then.
    final h = (_size?.height ?? 50).toDouble();
    return Container(
      height: h,
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
