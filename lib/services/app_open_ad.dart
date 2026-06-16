// Google AdMob App Open ad — full-screen ad shown when the app is launched or
// returns to the foreground. The single highest-value format for a
// high-frequency utility app like a bus tracker (opened many times a day).
// AdMob: "apps with frequent opens (>once every 4h) see the best performance."
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
//   • Never stacks with the Interstitial (shared FullScreenAdGate) — AdMob
//     disallows an ad immediately before/after an app-open ad.
//
// Fires on BOTH a cold launch ([showOnColdLaunch], for returning users — never
// the very first launch) and warm foreground (AppLifecycleListener onResume).
// The 24h cap means brief in-and-out app-switching won't trigger one; only a
// genuine new session (a return after a long break) can, at most once a day.

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

  /// When false, NO App Open ad is shown on a cold launch — opening the app
  /// never greets the user with a full-screen ad. Set false on tester feedback
  /// that launch ads were too aggressive (QOL: "reduce advertisement esp upon
  /// app launch"). Warm foreground returns after the [_minInterval] window can
  /// still show one (rare), so some revenue is preserved. Flip to true to
  /// restore cold-launch presentation.
  static const bool _coldLaunchEnabled = false;

  /// Frequency cap — at most one App Open ad per this window. Raised 4h → 6h →
  /// 24h as tester feedback kept flagging the warm-return launch ad as annoying
  /// (a bus app is opened many times a day; an ad on re-entry interrupts exactly
  /// when the user wants arrivals). At 24h it shows at most once per day, on a
  /// genuine new session after a long break. Cold-launch stays disabled
  /// ([_coldLaunchEnabled]); banners + the interstitial-on-exit carry the rest.
  static const Duration _minInterval = Duration(hours: 24);

  /// App Open creatives expire 4h after load (AdMob). Drop + reload past this.
  static const Duration _maxCacheAge = Duration(hours: 4);

  static const String _lastShownKey = 'lyne.appOpenAd.lastShownMs';

  /// Set true after the first launch into the main UI, so the cold-launch ad
  /// never greets a brand-new user on their very first open (AdMob guidance).
  static const String _coldLaunchedKey = 'lyne.appOpenAd.coldLaunchedBefore';

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

  /// Cold-launch presentation: on a genuine app launch (not a warm resume),
  /// show one App Open ad once it's loaded — bounded to a short window after
  /// launch so a late creative never covers content the user is already using.
  /// Skipped on the very first launch into the app (AdMob guidance: don't greet
  /// a brand-new user with an ad). All the usual guards (4h cap, onboarding,
  /// deep-link suppression, cross-format gap) still apply inside
  /// [showIfAvailable].
  Future<void> showOnColdLaunch() async {
    if (!kLyneAdsEnabled || kLyneScreenshotMode) return;
    // Cold-launch App Open ads are disabled (see [_coldLaunchEnabled]) so the
    // app never opens straight into an ad. We still mark the first-launch flag
    // below so flipping the toggle back on later behaves correctly.
    if (!_coldLaunchEnabled) return;
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_coldLaunchedKey) ?? false)) {
      await prefs.setBool(_coldLaunchedKey, true); // first launch — no ad
      return;
    }
    // Wait briefly for consent + a loaded creative, then present. Bounded
    // (~5s) so we never show over content the user has already started using.
    for (var i = 0; i < 10; i++) {
      if (AdConsent.started && _ad != null && !_isExpired) {
        await showIfAvailable();
        return;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
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
