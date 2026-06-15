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
const bool kLyneAdsTest = bool.fromEnvironment(
  'LYNE_ADS_TEST',
  defaultValue: false,
);

/// True when this build was compiled with
/// `--dart-define=LYNE_SCREENSHOT_MODE=true`. Suppresses the ad banner
/// entirely (no 50pt reservation, no SDK request) so App Store / Play
/// Store marketing screenshots focus on the app's value, not on the
/// "Nice job! …" test ad creative. Use this only when capturing
/// screenshots — every other build path should leave the flag off so
/// the slot is reserved correctly.
const bool kLyneScreenshotMode = bool.fromEnvironment(
  'LYNE_SCREENSHOT_MODE',
  defaultValue: false,
);

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

/// Resolve the 300×250 MREC ad unit ID. Same gating as the banner.
///   • DEBUG or LYNE_ADS_TEST=true: Google's universal test unit (it serves a
///     test creative matching whatever AdSize is requested, including 300×250).
///   • RELEASE: reuses the production banner unit for now — an AdMob unit isn't
///     bound to one size, so it still serves a 300×250. Mirrors iOS, which
///     reuses its banner unit for the Stop-screen MREC.
///     TODO: create a dedicated 300×250 unit in AdMob and swap it in here (and
///     on iOS) so MREC vs banner performance can be reported separately.
String _mrecUnitId() {
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

/// Resolve the native ad unit ID. Same gating as the banner.
///   • DEBUG or LYNE_ADS_TEST=true: Google's Android native template test unit
///   • RELEASE (public Play Store): production native unit (Leyne AdMob account,
///     leyne0000@gmail.com, ca-app-pub-5864511655536507)
String _nativeUnitId() {
  if (kDebugMode || kLyneAdsTest) {
    return 'ca-app-pub-3940256099942544/2247696110';
  }
  return 'ca-app-pub-5864511655536507/3213886079';
}

/// Inline native ad card using NativeTemplateStyle (TemplateType.medium).
///
/// Uses the SDK's built-in native template — no NativeAdFactory registration
/// required. TemplateType.medium is chosen over small because it renders at a
/// height (≈120–160 pt) that naturally sits in the same visual rhythm as the
/// nearby-stop cards (~80–90 pt padded). The small template's intrinsic height
/// (~55–70 pt) is too short — even with a minHeight constraint the creative
/// sits in an empty shell that reads as a thin band next to full-height stops.
/// Medium fills to a richer, intentional size with both sparse and rich
/// creatives; it is capped at 200 pt so it never dominates the list.
///
/// The outer card frame mirrors _NearbyCard exactly:
///   • Material(color: t.surface, borderRadius: 18)
///   • 1 pt t.line border (same as a non-highlighted stop card)
///   • ClipAntiAlias so the SDK's platform view respects the rounded corners
///   • Horizontal margins come from the ListView padding (16 each side) —
///     no extra horizontal margin needed inside the widget.
///
/// NativeTemplateStyle tokens — monochrome, light/dark aware:
///   • mainBackgroundColor → t.surface  (transparent to the Material layer)
///   • CTA → accent background, onAccent text
///   • primary/secondary/tertiary text → fg/dim/faint at the app's type scale
///   • cornerRadius → 18 (matches the stop-card corner, applied to icon + CTA)
///
/// Consent gate and lifecycle rules mirror AdBanner:
///   • Load is deferred until AdConsent.started.
///   • On failure the widget shrinks to zero — no gap, no placeholder.
///   • NativeAd.dispose() is called in dispose() so the SDK cleans up the
///     platform view and native memory.
///   • Master switch (kLyneAdsEnabled) and screenshot mode are respected.
class NativeAdCard extends StatefulWidget {
  const NativeAdCard({super.key});

  @override
  State<NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends State<NativeAdCard> {
  NativeAd? _ad;
  bool _loaded = false;
  Timer? _retry;

  // The stop-card corner radius — 18 pt, matching _NearbyCard exactly.
  static const double _cardRadius = 18;

  @override
  void initState() {
    super.initState();
    if (!kLyneAdsEnabled || kLyneScreenshotMode) return;
    // Defer the first load to after the initial frame: _load() reads the theme
    // (context.t → dependOnInheritedWidgetOfExactType), which is illegal during
    // initState and throws "...was called before _NativeAdCardState.initState()
    // completed" when consent is already resolved (so _load would run
    // synchronously here). The load is async/consent-gated anyway, so a
    // one-frame delay is invisible. (The retry path already runs off a Timer.)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _attemptLoad();
    });
  }

  void _attemptLoad() {
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
    // Resolve theme colours at load time from the current context. If the
    // widget is not yet in a tree (edge case) fall back to the dark palette so
    // we still send a style object — the template renders something even if
    // the colours are slightly off the first frame.
    final t = context.mounted ? context.t : LyneTheme.dark;

    final ad = NativeAd(
      adUnitId: _nativeUnitId(),
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _ad = null;
          if (kDebugMode) {
            // ignore: avoid_print
            print('[ads] native failed: ${error.message}');
          }
        },
      ),
      nativeTemplateStyle: NativeTemplateStyle(
        // medium gives a richer, intentional height (≈120–160 pt) that sits
        // in the same visual rhythm as the nearby-stop cards. It also
        // exposes more creative surface (image slot), which improves eCPM.
        templateType: TemplateType.medium,
        // Surface background — matches the stop-card Material surface so the
        // ad reads as part of the list, not a foreign white box.
        mainBackgroundColor: t.surface,
        // cornerRadius: applies to the app icon and CTA button inside the
        // template. Use 18 to match the stop-card outer corner so internal
        // and external radii feel consistent.
        cornerRadius: _cardRadius,
        // CTA button: accent background (monochrome ink) + onAccent text.
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: t.onAccent,
          backgroundColor: t.accent,
          size: 13,
        ),
        // Headline — full-weight fg.
        primaryTextStyle: NativeTemplateTextStyle(textColor: t.fg, size: 14),
        // Body / rating line — dim (60 % opacity ink).
        secondaryTextStyle: NativeTemplateTextStyle(textColor: t.dim, size: 12),
        // Store / advertiser line — faint (35 % opacity ink).
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: t.faint,
          size: 11,
        ),
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
    // Hard short-circuit — no reservation, no gap.
    if (!kLyneAdsEnabled || kLyneScreenshotMode || !_loaded || _ad == null) {
      return const SizedBox.shrink();
    }

    final t = context.t;

    // Outer frame mirrors _NearbyCard: Material surface + 1 pt line border +
    // 18 pt corner radius + antiAlias clip so the SDK platform view is
    // contained inside the rounded rect.
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(_cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_cardRadius),
          border: Border.all(color: t.line),
        ),
        // TemplateType.medium renders at ≈120–160 pt; floor at 120 so a
        // sparse creative still fills a card-height slot, ceiling at 200 so
        // it never dominates the list on large-text devices.
        constraints: const BoxConstraints(minHeight: 120, maxHeight: 200),
        child: AdWidget(ad: _ad!),
      ),
    );
  }
}

/// Fixed 300×250 medium rectangle (MREC) for an inline content placement — the
/// Stop screen shows one of these instead of the bottom anchored banner, so the
/// screen carries exactly one ad (iOS parity). Mirrors the iOS `MediumRectAd`.
///
/// Renders nothing (zero-size) until both AdConsent.started AND the ad loads —
/// it sits at the end of the scroll content, so deferring keeps an empty 250pt
/// gap from ever showing when fill fails or while consent is still resolving.
/// Self-suppresses when ads are off (master switch) or in screenshot mode.
class MediumRectAd extends StatefulWidget {
  const MediumRectAd({super.key});

  @override
  State<MediumRectAd> createState() => _MediumRectAdState();
}

class _MediumRectAdState extends State<MediumRectAd> {
  BannerAd? _ad;
  bool _loaded = false;
  Timer? _retry;

  @override
  void initState() {
    super.initState();
    if (!kLyneAdsEnabled || kLyneScreenshotMode) return;
    _attemptLoad();
  }

  void _attemptLoad() {
    if (!AdConsent.started) {
      _retry?.cancel();
      _retry = Timer(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        _attemptLoad();
      });
      return;
    }
    final ad = BannerAd(
      adUnitId: _mrecUnitId(),
      size: AdSize.mediumRectangle, // 300×250
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
            print('[ads] MREC failed: ${error.message}');
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
    if (!kLyneAdsEnabled || kLyneScreenshotMode || !_loaded || _ad == null) {
      return const SizedBox.shrink();
    }
    // Centre the fixed 300×250 block with breathing room above it.
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Center(
        child: SizedBox(
          width: _ad!.size.width.toDouble(),
          height: _ad!.size.height.toDouble(),
          child: AdWidget(ad: _ad!),
        ),
      ),
    );
  }
}
