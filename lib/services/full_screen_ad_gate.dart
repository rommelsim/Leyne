// Shared throttle across ALL full-screen ad formats (App Open + Interstitial).
//
// Each format keeps its own frequency cap, but a per-format cap can't see the
// other format — so without this an App Open ad on foreground and an
// Interstitial on the next stop/bus exit could stack back-to-back. This gate
// records the timestamp of the last full-screen ad of ANY kind and enforces a
// single global minimum gap, so the two formats never sandwich the user.
//
// Persisted (SharedPreferences) so the gap also holds across a force-quit +
// relaunch — e.g. an App Open at session end won't be immediately followed by
// an Interstitial seconds later in the next session.

import 'package:shared_preferences/shared_preferences.dart';

class FullScreenAdGate {
  FullScreenAdGate._();

  static const String _lastShownKey = 'lyne.fullScreenAd.lastShownMs';

  /// Minimum gap between any two full-screen ads, regardless of per-format caps.
  static const Duration minGap = Duration(seconds: 90);

  /// True when enough time has passed since the last full-screen ad of any kind
  /// that showing another one now won't stack on top of a recent one.
  static Future<bool> gapElapsed() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_lastShownKey) ?? 0;
    final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
    return DateTime.now().difference(last) >= minGap;
  }

  /// Record that a full-screen ad of some kind was just shown. Call from BOTH
  /// the App Open and Interstitial managers at present time.
  static Future<void> markShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastShownKey, DateTime.now().millisecondsSinceEpoch);
  }
}
