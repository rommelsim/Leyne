// ReviewPrompt — asks for a Play Store rating at the moment of proven value.
//
// Strategy (per the growth review): the strongest in-app signal that the app
// delivered value is the user TAPPING a useful arrival/alight notification —
// the alert fired, it was helpful, they acted on it. We count those "value
// moments" and, on the 2nd one, fire the Google Play In-App Review flow once
// per install. Asking at a high-sentiment moment maximises 4–5★ responses and
// minimises low-star "why are you nagging me" reviews.
//
// The Play In-App Review API itself is quota-limited by the OS (it may show
// nothing if shown too often / too recently), so this never spams — our guard
// just avoids re-triggering our own logic. NO-OP on the iOS build: iOS ships
// from the SwiftUI app at `ios-native/` (see ReviewPrompt in LeyneApp.swift).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReviewPrompt {
  ReviewPrompt._();

  static const _kValueMomentsKey = 'lyne.review.valueMoments';
  static const _kRequestedKey = 'lyne.review.requested';

  /// Ask for a review only on the Nth qualifying value moment — the user has
  /// already seen value at least once, so this isn't a cold ask.
  static const int _askOnMoment = 2;

  /// Record a value moment (a useful-notification tap) and, once the threshold
  /// is reached, request a Play Store review exactly once per install. Safe to
  /// call from anywhere; fully self-contained and fire-and-forget.
  static Future<void> recordValueMomentAndMaybeAsk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kRequestedKey) ?? false) return;

      final moments = (prefs.getInt(_kValueMomentsKey) ?? 0) + 1;
      await prefs.setInt(_kValueMomentsKey, moments);
      if (moments < _askOnMoment) return;

      final inAppReview = InAppReview.instance;
      if (!await inAppReview.isAvailable()) return;

      // Let the user actually land on their bus first — the prompt should
      // arrive a beat after the value, not on top of the navigation.
      await Future<void>.delayed(const Duration(seconds: 3));
      await inAppReview.requestReview();
      // Mark asked regardless of whether the OS chose to show the sheet — we
      // gave it our one high-quality opportunity.
      await prefs.setBool(_kRequestedKey, true);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[review] prompt skipped: $e');
      }
    }
  }
}
