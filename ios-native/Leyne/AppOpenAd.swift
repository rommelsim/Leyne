// Google AdMob App Open ad — full-screen ad shown when the app returns to the
// foreground from the background. The single highest-value format for a
// high-frequency utility app like a bus tracker (opened many times a day).
//
// UX-first / policy-safe guards, all enforced in `showIfReady(model:)`:
//   • Respects the same gates as the banner: `AdConfig.adsEnabled`,
//     `AdConfig.screenshotMode`, and `AdConfig.started` (UMP + ATT + SDK init).
//   • NEVER during/before onboarding, or over the launch splash.
//   • NEVER when a notification / widget / Spotlight tap brought the user to
//     the foreground — they want their bus, not an ad (`suppressNextPresentation`).
//   • At most once every `minInterval` (frequency cap, persisted in UserDefaults).
//   • Only a fresh creative — App Open ads expire `maxCacheAge` after load
//     (AdMob policy); stale ones are dropped and reloaded.
//
// Wired to fire on WARM foreground only (scenePhase .background → .active in
// LeyneApp), never on cold launch — least jarring, and avoids racing the
// consent / ATT prompts that run on first launch.

import SwiftUI
import GoogleMobileAds
import os

private let aoaLog = Logger(subsystem: "com.leyne.Leyne", category: "AppOpenAd")

enum AppOpenAdConfig {
    // Ad unit selection mirrors AdConfig.bannerUnitID:
    //   • DEBUG (Xcode Run): Google's reserved App Open TEST unit.
    //   • RELEASE: the real production unit, unless `forceTestUnitForRelease`
    //     (the TestFlight toggle in AdConfig) forces the test unit.
    //
    // Production App Open unit lives in the Leyne AdMob account
    // (leyne0000@gmail.com, ca-app-pub-5864511655536507), matching the
    // GADApplicationIdentifier (…~6330743279) in LeyneInfo.plist.
    #if DEBUG
    static let unitID = "ca-app-pub-3940256099942544/5575463023"  // Google test
    #else
    static let unitID = AdConfig.forceTestUnitForRelease
        ? "ca-app-pub-3940256099942544/5575463023"   // Google test
        : "ca-app-pub-5864511655536507/4093216883"   // leyne-acct prod App Open
    #endif

    /// Frequency cap — at most one App Open ad per this window.
    static let minInterval: TimeInterval = 5 * 60

    /// App Open creatives expire 4h after load (AdMob). Drop + reload past this.
    static let maxCacheAge: TimeInterval = 4 * 60 * 60
}

@MainActor
final class AppOpenAdManager: NSObject {
    static let shared = AppOpenAdManager()

    private var ad: AppOpenAd?
    private var loadTime: Date = .distantPast
    private var isLoading = false
    private var isShowing = false
    private var suppressUntil: Date = .distantPast
    private var wasBackgrounded = false
    private let lastShownKey = "leyne.appOpenAd.lastShown"

    private override init() { super.init() }

    /// Call when the scene enters the background. scenePhase steps through
    /// .inactive between .background and .active, so the previous phase is NOT
    /// reliably .background on return — we track backgrounding explicitly here.
    /// Also preloads so an ad is ready for the return-to-foreground.
    func noteBackgrounded() {
        wasBackgrounded = true
        preload()
    }

    /// Call when the scene becomes active. Presents only if we actually returned
    /// from the background — ignores cold launch (never hit .background) and
    /// transient .inactive blips (Control Center, the notification shade).
    func showIfReturningToForeground(model: AppModel) {
        guard wasBackgrounded else { return }
        wasBackgrounded = false
        showIfReady(model: model)
    }

    /// Called by the notification / widget / Spotlight handlers so the App Open
    /// ad is skipped on the foreground they triggered. Short TTL covers the race
    /// between the scenePhase transition and the deep-link handler firing.
    func suppressNextPresentation() {
        suppressUntil = Date().addingTimeInterval(3)
        aoaLog.notice("App Open suppressed (deep link)")
    }

    private var isExpired: Bool {
        Date().timeIntervalSince(loadTime) > AppOpenAdConfig.maxCacheAge
    }

    /// Load a single ad ahead of time if we don't already have a fresh one.
    func preload() {
        guard AdConfig.adsEnabled, !AdConfig.screenshotMode else { return }
        guard AdConfig.started else { return }       // consent + SDK ready
        guard !isLoading, ad == nil || isExpired else { return }
        isLoading = true
        aoaLog.notice("App Open loading…")
        AppOpenAd.load(with: AppOpenAdConfig.unitID, request: Request()) { [weak self] ad, error in
            // GADAppOpenAd delivers this completion on the main queue; the
            // manager is @MainActor so touching its state here is safe (same
            // pattern as the banner's delegate callbacks).
            guard let self else { return }
            self.isLoading = false
            if let error {
                aoaLog.error("App Open load failed: \(error.localizedDescription)")
                return
            }
            ad?.fullScreenContentDelegate = self
            self.ad = ad
            self.loadTime = Date()
            aoaLog.notice("App Open loaded")
        }
    }

    /// Present the App Open ad on foreground IF every guard passes; otherwise
    /// make sure one is loading for next time. Safe to call on every foreground.
    func showIfReady(model: AppModel) {
        guard AdConfig.adsEnabled, !AdConfig.screenshotMode else { return }
        guard AdConfig.started else { preload(); return }

        // Never during/before onboarding, or over the launch splash.
        guard model.onboarded, !model.showOnboarding, !model.launching else {
            aoaLog.notice("App Open skip: onboarding/launch")
            return
        }
        // A notification / widget / Spotlight tap brought us here — show content.
        guard Date() >= suppressUntil else {
            aoaLog.notice("App Open skip: deep-link suppression")
            return
        }
        // Frequency cap.
        let last = Date(timeIntervalSince1970:
            UserDefaults.standard.double(forKey: lastShownKey))
        guard Date().timeIntervalSince(last) >= AppOpenAdConfig.minInterval else {
            aoaLog.notice("App Open skip: within frequency cap")
            return
        }

        guard !isShowing else { return }
        // No fresh ad ready — drop any stale one and load for next time.
        guard let ad, !isExpired else {
            if isExpired { self.ad = nil }
            preload()
            return
        }
        guard let root = Self.rootVC() else { return }

        isShowing = true
        // Record BEFORE presenting so a present-failure still counts against the
        // cap (don't hammer the user with retries).
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastShownKey)
        self.ad = nil   // hand ownership to the present() lifecycle
        aoaLog.notice("App Open present")
        ad.present(from: root)
    }

    static func rootVC() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}

extension AppOpenAdManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        isShowing = false
        self.ad = nil
        preload()   // get the next one ready
    }

    func ad(_ ad: FullScreenPresentingAd,
            didFailToPresentFullScreenContentWithError error: Error) {
        aoaLog.error("App Open present failed: \(error.localizedDescription)")
        isShowing = false
        self.ad = nil
        preload()
    }
}
