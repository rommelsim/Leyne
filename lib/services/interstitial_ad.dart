// Google AdMob Interstitial ad — full-screen ad shown at a natural transition
// point: when the user backs OUT of a Stop or Bus detail view (a task just
// completed, before the next one starts). Never mid-task, never on entry.
//
// UX-first / policy-safe guards, all enforced in [maybeShowOnExit]:
//   • Respects the same master switches as the banner: kLyneAdsEnabled,
//     kLyneScreenshotMode, and AdConsent.started (UMP + SDK init done).
//   • NEVER during or before onboarding (AppModel.onboardingDone gate).
//   • Only fires every [_minExitsBeforeShow]-th qualifying exit, so a quick
//     in-and-out never triggers one — the user gets value first.
//   • At most once every [_minInterval] (interstitial-specific cap, persisted).
//   • Plus a shared cross-format gap (FullScreenAdGate) so an interstitial
//     never stacks right after an App Open ad (or vice versa).
//   • Only shows a creative that's actually loaded; otherwise it just reloads
//     for next time (the exit navigation always proceeds either way).
//
// Flutter powers the Android build only — iOS ships the SwiftUI equivalent in
// `ios-native/Leyne/InterstitialAd.swift`.

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/app_model.dart';
import '../widgets/ad_banner.dart'
    show kLyneAdsEnabled, kLyneScreenshotMode, kLyneAdsTest;
import 'ad_consent.dart';
import 'full_screen_ad_gate.dart';

/// Master switch for the Interstitial format. OFF for the current release.
///
/// Per the phased ad rollout (and AdMob's "start low, increase carefully to
/// protect retention" guidance), interstitials are a Phase 2 addition — added
/// after banners + App Open have a usage/retention baseline, since those two
/// carry the bulk of revenue while interstitials carry the most retention risk.
/// The implementation, wiring, and prod unit all stay in place; flip this to
/// `true` to enable. The back-exit placement is intentionally policy-aligned
/// (AdMob caps interstitials at one per two user actions, back press included).
const bool kLyneInterstitialEnabled = false;

class InterstitialAdManager {
  InterstitialAdManager._();
  static final InterstitialAdManager instance = InterstitialAdManager._();

  // Ad unit selection mirrors the banner (ad_banner.dart `_bannerUnitId`):
  //   • DEBUG or LYNE_ADS_TEST=true → Google's reserved Interstitial TEST unit.
  //   • RELEASE (public Play Store) → the real production Interstitial unit
  //     (Leyne AdMob account, leyne0000@gmail.com, ca-app-pub-5864511655536507,
  //     Android app id …~5685985257).
  static const String _testUnit = 'ca-app-pub-3940256099942544/1033173712';
  static const String _prodUnit =
      'ca-app-pub-5864511655536507/8982425954'; // leyne-acct prod Interstitial

  String get _unitId => (kDebugMode || kLyneAdsTest) ? _testUnit : _prodUnit;

  /// Interstitial-specific frequency cap — at most one per this window. Longer
  /// than the shared cross-format gap; this is the main pace control.
  static const Duration _minInterval = Duration(minutes: 3);

  /// Require this many qualifying exits since the last interstitial before
  /// showing another, so a rapid in-and-out never triggers one.
  static const int _minExitsBeforeShow = 2;

  static const String _lastShownKey = 'lyne.interstitialAd.lastShownMs';

  InterstitialAd? _ad;
  bool _isLoading = false;
  bool _isShowing = false;

  /// In-memory count of qualifying exits since the last shown interstitial.
  /// Not persisted — a fresh launch should let the user settle in before the
  /// first interstitial regardless of last session's count.
  int _exitsSinceShown = 0;

  /// True only when the format is enabled for this build AND a unit is wired
  /// (always in test builds). When false the manager is a complete no-op —
  /// gates preload, preloadWhenReady, and maybeShowOnExit.
  bool get _configured => kLyneInterstitialEnabled && _unitId.isNotEmpty;

  /// Load a single ad ahead of time if we don't already have one.
  void preload() {
    if (!kLyneAdsEnabled || kLyneScreenshotMode) return;
    if (!AdConsent.started) return; // consent + MobileAds.initialize must be done
    if (!_configured) return;
    if (_isLoading || _ad != null) return;
    _isLoading = true;
    InterstitialAd.load(
      adUnitId: _unitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _isLoading = false;
        },
        onAdFailedToLoad: (error) {
          _isLoading = false;
          if (kDebugMode) {
            // ignore: avoid_print
            print('[ads] interstitial load failed: ${error.message}');
          }
        },
      ),
    );
  }

  /// Preload once consent has resolved. Polls lightly (the banner / App Open
  /// use the same pattern) since consent fires fire-and-forget from main().
  /// Bounded so it never loops forever when ads are disabled or consent stalls.
  void preloadWhenReady([int attemptsLeft = 15]) {
    if (!kLyneAdsEnabled || kLyneScreenshotMode || !_configured) return;
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

  /// Call when the user exits a Stop or Bus detail view. Shows an interstitial
  /// IF every guard passes; otherwise counts the exit and makes sure one is
  /// loading for next time. Safe to call on every back-exit — the navigation
  /// has already happened, so this never blocks the user.
  Future<void> maybeShowOnExit() async {
    if (!kLyneAdsEnabled || kLyneScreenshotMode || !_configured) return;
    if (!AdConsent.started) {
      preload();
      return;
    }
    // Never during/before onboarding.
    if (!AppModel.shared.onboardingDone) return;
    if (_isShowing) return;

    _exitsSinceShown++;

    // Hold the first few exits so the user gets value before any interstitial.
    if (_exitsSinceShown < _minExitsBeforeShow) {
      preload();
      return;
    }

    // Interstitial-specific frequency cap.
    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_lastShownKey) ?? 0;
    final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
    if (DateTime.now().difference(last) < _minInterval) {
      preload();
      return;
    }

    // Shared cross-format gap — don't stack on a recent App Open ad.
    if (!await FullScreenAdGate.gapElapsed()) {
      preload();
      return;
    }

    // No ad ready — load for next time; the exit already happened.
    final ad = _ad;
    if (ad == null) {
      preload();
      return;
    }

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
          print('[ads] interstitial show failed: ${error.message}');
        }
      },
    );

    // Record BEFORE showing so a present-failure still counts against the caps
    // (don't hammer the user with retries). Reset the exit counter and stamp
    // both the interstitial cap and the shared cross-format gate.
    _exitsSinceShown = 0;
    await prefs.setInt(_lastShownKey, DateTime.now().millisecondsSinceEpoch);
    await FullScreenAdGate.markShown();
    _ad = null; // hand ownership to the show() lifecycle
    ad.show();
  }
}
