// Google AdMob App Open ad — full-screen ad shown when the app returns to the
// foreground from the background. The single highest-value format for a
// high-frequency utility app like a bus tracker (opened many times a day).
//
// UX-first / policy-safe guards, all enforced in [showIfAvailable]:
//   • Respects the same master switches as the banner: kLyneAdsEnabled,
//     kLyneScreenshotMode, and AdConsent.started (UMP + SDK init done).
//   • NEVER during or before onboarding (AppModel.onboardingDone gate).
//   • NEVER when a notification / deep-link tap brought the user to the
//     foreground — they want their bus, not an ad ([suppressNext]).
//   • At most once every [_minInterval] (frequency cap, persisted).
//   • Only shows a fresh creative — App Open ads expire [_maxCacheAge] after
//     load (AdMob policy), so stale ones are dropped and reloaded.
//
// It is wired to fire on warm foreground only (Flutter's AppLifecycleListener
// onResume), NOT on cold launch — the cold-start listener is created after the
// initial resume, so the very first launch never shows one (least jarring).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/app_model.dart';
import '../widgets/ad_banner.dart'
    show kLyneAdsEnabled, kLyneScreenshotMode, kLyneAdsTest;
import 'ad_consent.dart';
import 'full_screen_ad_gate.dart';

class AppOpenAdManager {
  AppOpenAdManager._();
  static final AppOpenAdManager instance = AppOpenAdManager._();

  // Ad unit selection mirrors the banner (ad_banner.dart `_bannerUnitId`):
  //   • DEBUG or LYNE_ADS_TEST=true → Google's reserved App Open TEST unit.
  //   • RELEASE (public Play Store) → the real production App Open unit (Leyne
  //     AdMob account, leyne0000@gmail.com, ca-app-pub-5864511655536507,
  //     matching the Android app id …~5685985257).
  static const String _testUnit = 'ca-app-pub-3940256099942544/9257395921';
  static const String _prodUnit =
      'ca-app-pub-5864511655536507/1467053541'; // leyne-acct prod App Open

  String get _unitId => (kDebugMode || kLyneAdsTest) ? _testUnit : _prodUnit;

  /// Frequency cap — at most one App Open ad per this window.
  static const Duration _minInterval = Duration(minutes: 5);

  /// App Open creatives expire 4h after load (AdMob). Drop + reload past this.
  static const Duration _maxCacheAge = Duration(hours: 4);

  static const String _lastShownKey = 'lyne.appOpenAd.lastShownMs';

  AppOpenAd? _ad;
  DateTime? _loadTime;
  bool _isLoading = false;
  bool _isShowing = false;
  DateTime _suppressUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// Called by the notification-tap and deep-link handlers so the App Open ad
  /// is skipped on the foreground they triggered (short TTL covers the race
  /// between the lifecycle resume and the deep-link callback firing).
  void suppressNext() {
    _suppressUntil = DateTime.now().add(const Duration(seconds: 3));
  }

  bool get _isExpired =>
      _loadTime == null || DateTime.now().difference(_loadTime!) > _maxCacheAge;

  /// Load a single ad ahead of time if we don't already have a fresh one.
  void preload() {
    if (!kLyneAdsEnabled || kLyneScreenshotMode) return;
    if (!AdConsent.started) return; // consent + MobileAds.initialize must be done
    if (_isLoading || (_ad != null && !_isExpired)) return;
    _isLoading = true;
    AppOpenAd.load(
      adUnitId: _unitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loadTime = DateTime.now();
          _isLoading = false;
        },
        onAdFailedToLoad: (error) {
          _isLoading = false;
          if (kDebugMode) {
            // ignore: avoid_print
            print('[ads] app-open load failed: ${error.message}');
          }
        },
      ),
    );
  }

  /// Preload once consent has resolved. Polls lightly (the banner uses the same
  /// pattern) since consent is fired fire-and-forget from main(). Bounded so it
  /// never loops forever when ads are disabled or consent stalls.
  void preloadWhenReady([int attemptsLeft = 15]) {
    if (!kLyneAdsEnabled || kLyneScreenshotMode) return;
    if (AdConsent.started) {
      preload();
      return;
    }
    if (attemptsLeft <= 0) return;
    Future.delayed(
      const Duration(milliseconds: 800),
      () => preloadWhenReady(attemptsLeft - 1),
    );
  }

  /// Show the App Open ad on foreground IF every guard passes; otherwise make
  /// sure one is loading for next time. Safe to call on every resume.
  Future<void> showIfAvailable() async {
    if (!kLyneAdsEnabled || kLyneScreenshotMode) return;
    if (!AdConsent.started) {
      preload();
      return;
    }
    // Never during/before onboarding.
    if (!AppModel.shared.onboardingDone) return;
    // A notification / deep link brought us here — show content, not an ad.
    if (DateTime.now().isBefore(_suppressUntil)) return;

    // Frequency cap.
    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_lastShownKey) ?? 0;
    final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
    if (DateTime.now().difference(last) < _minInterval) return;

    // Shared cross-format gap — don't stack right after an Interstitial.
    if (!await FullScreenAdGate.gapElapsed()) return;

    if (_isShowing) return;
    // No fresh ad ready — drop any stale one and load for next time.
    if (_ad == null || _isExpired) {
      _ad?.dispose();
      _ad = null;
      preload();
      return;
    }

    final ad = _ad!;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => _isShowing = true,
      onAdDismissedFullScreenContent: (ad) {
        _isShowing = false;
        ad.dispose();
        _ad = null;
        preload(); // ready for next time
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        _isShowing = false;
        ad.dispose();
        _ad = null;
        preload();
        if (kDebugMode) {
          // ignore: avoid_print
          print('[ads] app-open show failed: ${error.message}');
        }
      },
    );
    // Record BEFORE showing so a present-failure still counts against the cap
    // (don't hammer the user with retries).
    await prefs.setInt(_lastShownKey, DateTime.now().millisecondsSinceEpoch);
    await FullScreenAdGate.markShown();
    _ad = null; // hand ownership to the show() lifecycle
    ad.show();
  }
}
