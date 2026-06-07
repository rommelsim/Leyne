// Shared throttle across ALL full-screen ad formats (App Open + Interstitial).
//
// Each format keeps its own frequency cap, but a per-format cap can't see the
// other format — so without this an App Open ad on foreground and an
// Interstitial on the next Stop/Bus exit could stack back-to-back. This gate
// records the timestamp of the last full-screen ad of ANY kind and enforces a
// single global minimum gap, so the two formats never sandwich the user.
//
// Persisted (UserDefaults) so the gap also holds across a force-quit + relaunch.
// Mirrors lib/services/full_screen_ad_gate.dart on the Android side.

import Foundation

enum FullScreenAdGate {
    static let lastShownKey = "leyne.fullScreenAd.lastShown"

    /// Minimum gap between any two full-screen ads, regardless of per-format caps.
    static let minGap: TimeInterval = 90

    /// True when enough time has passed since the last full-screen ad of any
    /// kind that showing another now won't stack on a recent one.
    static func gapElapsed() -> Bool {
        let last = Date(timeIntervalSince1970:
            UserDefaults.standard.double(forKey: lastShownKey))
        return Date().timeIntervalSince(last) >= minGap
    }

    /// Record that a full-screen ad of some kind was just shown. Call from BOTH
    /// the App Open and Interstitial managers at present time.
    static func markShown() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastShownKey)
    }
}
