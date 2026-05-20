// 320x50 banner host. Reserves 50pt vertically regardless of fill state
// so the layout doesn't jump when an ad lands.
//
// Ad unit IDs are gated by build configuration (matches legacy AdConfig):
//   • Debug: Google's official test banner units (always safe to render,
//     zero AdMob policy risk on any device).
//   • Release: the production ad unit registered to this AdMob account
//     (iOS: ca-app-pub-1910837226291536/6928301192; Android: needs to be
//     created when the Android app is registered).
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

/// Resolve the banner ad unit ID at runtime. Debug builds get Google's
/// always-test unit; release builds get the production unit.
String _bannerUnitId() {
  if (kDebugMode) {
    // Google's official test unit — same ID for both platforms.
    return Platform.isAndroid
        ? 'ca-app-pub-3940256099942544/6300978111'
        : 'ca-app-pub-3940256099942544/2934735716';
  }
  // Release.
  if (Platform.isIOS) return 'ca-app-pub-1910837226291536/6928301192';
  // Android production: TODO — replace with the real unit ID once the
  // Android app is registered in the AdMob console. Falls back to the
  // test unit so a release Android build still renders an ad (test
  // creative) instead of being broken.
  return 'ca-app-pub-3940256099942544/6300978111';
}

class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  Timer? _retry;

  @override
  void initState() {
    super.initState();
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
