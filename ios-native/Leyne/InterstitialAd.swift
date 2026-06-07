// Google AdMob Interstitial ad — full-screen ad shown at a natural transition
// point: when the user backs OUT of a Stop or Bus detail view (a task just
// completed, before the next one starts). Never mid-task, never on entry.
//
// UX-first / policy-safe guards, all enforced in `maybeShowOnExit(model:)`:
//   • Respects the same gates as the banner: `AdConfig.adsEnabled`,
//     `AdConfig.screenshotMode`, and `AdConfig.started` (UMP + ATT + SDK init).
//   • NEVER during/before onboarding, or over the launch splash.
//   • NEVER on a deep-link / notification-driven stack change (`suppressNextExit`).
//   • Only fires every `minExitsBeforeShow`-th qualifying exit, so a quick
//     in-and-out never triggers one — the user gets value first.
//   • At most once every `minInterval` (interstitial-specific cap, persisted).
//   • Plus a shared cross-format gap (`FullScreenAdGate`) so an interstitial
//     never stacks right after an App Open ad (or vice versa).
//
// iOS ships this; the Android equivalent lives in lib/services/interstitial_ad.dart.

import SwiftUI
import GoogleMobileAds
import os

private let interLog = Logger(subsystem: "com.leyne.Leyne", category: "InterstitialAd")

enum InterstitialAdConfig {
    // Ad unit selection mirrors AdConfig.bannerUnitID:
    //   • DEBUG (Xcode Run): Google's reserved Interstitial TEST unit.
    //   • RELEASE: the real production unit, unless `forceTestUnitForRelease`
    //     (the TestFlight toggle in AdConfig) forces the test unit.
    //
    // Production unit lives in the Leyne AdMob account (leyne0000@gmail.com,
    // ca-app-pub-5864511655536507), matching the GADApplicationIdentifier
    // (…~6330743279) in LeyneInfo.plist.
    #if DEBUG
    static let unitID = "ca-app-pub-3940256099942544/4411468910"  // Google test
    #else
    static let unitID = AdConfig.forceTestUnitForRelease
        ? "ca-app-pub-3940256099942544/4411468910"   // Google test
        : "ca-app-pub-5864511655536507/8576751750"   // leyne-acct prod Interstitial
    #endif

    /// Interstitial-specific frequency cap — at most one per this window. Longer
    /// than the shared cross-format gap; this is the main pace control.
    static let minInterval: TimeInterval = 3 * 60

    /// Require this many qualifying exits since the last interstitial before
    /// showing another, so a rapid in-and-out never triggers one.
    static let minExitsBeforeShow = 2
}

@MainActor
final class InterstitialAdManager: NSObject {
    static let shared = InterstitialAdManager()

    private var ad: InterstitialAd?
    private var isLoading = false
    private var isShowing = false
    /// In-memory count of qualifying exits since the last shown interstitial.
    /// Not persisted — a fresh launch should let the user settle in before the
    /// first interstitial regardless of last session's count.
    private var exitsSinceShown = 0
    private var suppressUntil: Date = .distantPast
    private let lastShownKey = "leyne.interstitialAd.lastShown"

    private override init() { super.init() }

    /// True once a real prod unit is wired (or in test builds). When false in a
    /// prod build the manager is a complete no-op.
    private var configured: Bool { !InterstitialAdConfig.unitID.isEmpty }

    /// Called before a deep-link / notification mutates a nav stack so the
    /// stack-shrink it causes isn't mistaken for a user back-exit. Short TTL
    /// covers the synchronous SwiftUI state update that follows.
    func suppressNextExit() {
        suppressUntil = Date().addingTimeInterval(1)
    }

    /// Load a single ad ahead of time if we don't already have one.
    func preload() {
        guard AdConfig.adsEnabled, !AdConfig.screenshotMode else { return }
        guard AdConfig.started else { return }       // consent + SDK ready
        guard configured else { return }
        guard !isLoading, ad == nil else { return }
        isLoading = true
        interLog.notice("Interstitial loading…")
        InterstitialAd.load(with: InterstitialAdConfig.unitID, request: Request()) { [weak self] ad, error in
            // The completion is delivered on the main queue; the manager is
            // @MainActor so touching its state here is safe (same pattern as
            // the App Open manager's callbacks).
            guard let self else { return }
            self.isLoading = false
            if let error {
                interLog.error("Interstitial load failed: \(error.localizedDescription)")
                return
            }
            ad?.fullScreenContentDelegate = self
            self.ad = ad
            interLog.notice("Interstitial loaded")
        }
    }

    /// Call when the user exits a Stop or Bus detail view. Presents an
    /// interstitial IF every guard passes; otherwise counts the exit and makes
    /// sure one is loading for next time. The navigation has already happened,
    /// so this never blocks the user.
    func maybeShowOnExit(model: AppModel) {
        guard AdConfig.adsEnabled, !AdConfig.screenshotMode, configured else { return }
        // A deep link / notification drove this stack change — not a user exit.
        guard Date() >= suppressUntil else { return }
        guard AdConfig.started else { preload(); return }
        // Never during/before onboarding, or over the launch splash.
        guard model.onboarded, !model.showOnboarding, !model.launching else { return }
        guard !isShowing else { return }

        exitsSinceShown += 1
        // Hold the first few exits so the user gets value before any interstitial.
        guard exitsSinceShown >= InterstitialAdConfig.minExitsBeforeShow else {
            preload(); return
        }

        // Interstitial-specific frequency cap.
        let last = Date(timeIntervalSince1970:
            UserDefaults.standard.double(forKey: lastShownKey))
        guard Date().timeIntervalSince(last) >= InterstitialAdConfig.minInterval else {
            preload(); return
        }
        // Shared cross-format gap — don't stack on a recent App Open ad.
        guard FullScreenAdGate.gapElapsed() else { preload(); return }

        guard let ad else { preload(); return }
        guard let root = AppOpenAdManager.rootVC() else { return }

        isShowing = true
        // Record BEFORE presenting so a present-failure still counts against the
        // caps (don't hammer the user with retries). Reset the exit counter and
        // stamp both the interstitial cap and the shared cross-format gate.
        exitsSinceShown = 0
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastShownKey)
        FullScreenAdGate.markShown()
        self.ad = nil   // hand ownership to the present() lifecycle
        interLog.notice("Interstitial present")
        ad.present(from: root)
    }
}

extension InterstitialAdManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        isShowing = false
        self.ad = nil
        preload()   // get the next one ready
    }

    func ad(_ ad: FullScreenPresentingAd,
            didFailToPresentFullScreenContentWithError error: Error) {
        interLog.error("Interstitial present failed: \(error.localizedDescription)")
        isShowing = false
        self.ad = nil
        preload()
    }
}
