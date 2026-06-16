// AnalyticsService — thin, typed wrapper over Firebase Analytics for the app's
// high-signal product events. Centralising the FirebaseAnalytics import here
// means the rest of the app logs via a typed API and never touches the SDK
// directly, so event names + parameters have one source of truth. This mirrors
// the iOS AnalyticsService.swift one-to-one (same event names, same parameter
// keys) so GA4 reports both platforms together.
//
// `app_open` is logged automatically by the SDK, so it is deliberately not
// represented here.
//
// NOTE: ad revenue (`ad_impression`) is NOT logged here — the Google Mobile Ads
// SDK auto-logs it once the AdMob↔Firebase link is active. Do NOT add a manual
// OnPaidEvent / paidEventHandler logger, or impressions double-count in GA4.
// (Matches the iOS decision — see AnalyticsService.swift.)
//
// Firebase is configured at launch in main.dart, guarded on the presence of
// google-services.json (the file is git-ignored — forks / CI / pre-setup builds
// skip it). When Firebase isn't configured, [_ready] stays false and every call
// here degrades to a no-op — never a crash.

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

enum StopKind { bus, mrt }

enum FavKind { stop, service }

class AnalyticsService {
  AnalyticsService._();

  /// Flipped true by [markReady] once Firebase.initializeApp() has succeeded in
  /// main.dart. Until then (and forever, on a build without google-services.json)
  /// every log call no-ops. Mirrors iOS configure()-skipped behaviour.
  static bool _ready = false;

  static FirebaseAnalytics? _analytics;

  /// Called from main.dart after a successful Firebase.initializeApp(). Safe to
  /// call more than once.
  static void markReady() {
    if (_ready) return;
    _ready = true;
    _analytics = FirebaseAnalytics.instance;
  }

  // ─── Product events (mirror iOS AnalyticsService.Event) ───────────────────

  /// A stop / station detail was opened. [code] is the bus stop code or the
  /// station's first code; [kind] distinguishes bus vs MRT.
  static void stopViewed({required String code, required StopKind kind}) =>
      _log('stop_viewed', {'stop_code': code, 'kind': kind.name});

  /// A notification alert was set for a service.
  static void alertSet({required String kind, required String busNo}) =>
      _log('alert_set', {'kind': kind, 'bus_no': busNo});

  /// A stop or service was added to favourites/saved.
  static void favouriteAdded(FavKind kind) =>
      _log('favourite_added', {'kind': kind.name});

  /// A search was performed.
  static void searchPerformed() => _log('search_performed', null);

  /// Onboarding was completed (or skipped — same routing effect).
  static void onboardingCompleted() => _log('onboarding_completed', null);

  /// A notification was tapped (a strong value signal for retention analysis).
  static void notificationTapped(String kind) =>
      _log('notification_tapped', {'kind': kind.isEmpty ? 'unknown' : kind});

  // ─── Internal ─────────────────────────────────────────────────────────────

  /// Fire-and-forget. No-op before Firebase is ready; never throws into the
  /// caller (analytics must never break a user flow).
  static void _log(String name, Map<String, Object>? parameters) {
    final a = _analytics;
    if (!_ready || a == null) return;
    a.logEvent(name: name, parameters: parameters).catchError((Object e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[analytics] logEvent($name) failed: $e');
      }
    });
  }
}
