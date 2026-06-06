// Google AdMob banner + consent.
//
// CONFIG:
//  • App ID lives in `LeyneInfo.plist` as `GADApplicationIdentifier`
//    (the real AdMob App ID — ca-app-pub-5864511655536507~6330743279).
//  • The ad UNIT is gated by build configuration (see `AdConfig`): DEBUG
//    uses Google's always-test banner unit (zero policy risk anywhere);
//    RELEASE uses the real production unit.
//  • The iOS Simulator is automatically a test device in DEBUG.
//
// CONSENT (App Store / personalized ads): the SDK is NOT started at launch.
// `AdConsent.gatherThenStart()` first runs Google UMP (GDPR/EEA consent
// form) and then the Apple App Tracking Transparency prompt, and only then
// initializes the Mobile Ads SDK. Personalized ads + IDFA tracking depend
// on both. Requires `NSUserTrackingUsageDescription` in LyneInfo.plist and
// the app's PrivacyInfo.xcprivacy declaring tracking.

import SwiftUI
import GoogleMobileAds
import UserMessagingPlatform
import AppTrackingTransparency
import os

private let adLog = Logger(subsystem: "com.leyne.Leyne", category: "Ads")

enum AdConfig {
    /// MASTER SWITCH. Set to `false` to ship a no-ads build (e.g. during an
    /// AdMob account suspension). When `true`:
    ///   • `bottomAdBanner` / `overlayAdBanner` mount the banner
    ///   • `AdConsent.gatherThenStart()` runs UMP + ATT
    ///   • `MobileAds.shared.start()` initializes the SDK
    ///   • Onboarding's "Ads" step is shown (see OnboardingView)
    static let adsEnabled = true

    // ╔══════════════════════════════════════════════════════════════╗
    // ║ TESTFLIGHT TOGGLE — Force test ad unit in a Release Archive. ║
    // ║                                                              ║
    // ║ Apple gives TestFlight and App Store the SAME Archive (both  ║
    // ║ Release config), so #if DEBUG can't tell them apart. To ship ║
    // ║ a pre-review build to TestFlight without serving the real    ║
    // ║ AdMob unit, flip BOTH lines below together:                  ║
    // ║                                                              ║
    // ║   • Archiving for TestFlight (safe test ads):                ║
    // ║       1. Set `forceTestUnitForRelease = true`                ║
    // ║       2. UNCOMMENT the `#warning(…)` line directly below it  ║
    // ║                                                              ║
    // ║   • Archiving for App Store (real ads, real revenue):        ║
    // ║       1. Set `forceTestUnitForRelease = false`               ║
    // ║       2. RE-COMMENT the `#warning(…)` line                   ║
    // ║                                                              ║
    // ║ The #warning surfaces a yellow build warning every compile   ║
    // ║ so the toggle's state is impossible to miss when archiving.  ║
    // ║ Forgetting to comment it back out is fine — App Store builds ║
    // ║ tolerate warnings; forgetting to flip the bool is what hurts.║
    // ╚══════════════════════════════════════════════════════════════╝
    static let forceTestUnitForRelease = false
    //#warning("forceTestUnitForRelease is ON — DO NOT submit this Archive to App Store")

    // Ad unit selection. DEBUG always serves the test unit (Xcode Run).
    // RELEASE serves either the test unit or the real production unit
    // depending on `forceTestUnitForRelease` (the toggle above).
    // Production unit lives in the Leyne Google AdMob account
    // (leyne0000@gmail.com, ca-app-pub-5864511655536507), matching the
    // GADApplicationIdentifier in LeyneInfo.plist
    // (ca-app-pub-5864511655536507~6330743279).
    #if DEBUG
    static let bannerUnitID = "ca-app-pub-3940256099942544/2934735716"
    #else
    static let bannerUnitID = forceTestUnitForRelease
        ? "ca-app-pub-3940256099942544/2934735716"  // Google test unit
        : "ca-app-pub-5864511655536507/9782205994"  // leyne-acct prod
    #endif

    /// Extra devices to force into TEST ads even in a RELEASE build (rarely
    /// needed — DEBUG already serves test ads everywhere). Leave empty.
    static let testDeviceIdentifiers: [String] = []

    /// True only when the app is launched with the `-screenshots` argument
    /// (set via the Xcode scheme or `simctl launch --args -screenshots` when
    /// capturing App Store marketing shots). End users cannot inject launch
    /// arguments into a shipped build, so this is safe to ship: it suppresses
    /// the ad banner so screenshots never contain third-party ad creatives.
    static let screenshotMode =
        ProcessInfo.processInfo.arguments.contains("-screenshots")

    /// SDK-started signal. Toggling this notifies anyone waiting (BannerAdView)
    /// so the first ad request goes out *after* `MobileAds.shared.start()` —
    /// previously a returning-user launch raced the load against consent.
    @MainActor
    static let didStart = NotificationCenter.default
    static let didStartName = Notification.Name("LeyneAdsSDKDidStart")
    private(set) static var started = false

    /// Idempotent SDK start. Safe to call more than once. Call only *after*
    /// consent has been gathered — see `AdConsent.gatherThenStart()`.
    static func startOnce() {
        guard !started else { return }
        started = true
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers =
            testDeviceIdentifiers
        MobileAds.shared.start { _ in
            adLog.notice("Mobile Ads SDK initialized")
            NotificationCenter.default.post(name: didStartName, object: nil)
        }
    }
}

// MARK: - Adaptive banner size

extension AdConfig {
    /// Anchored-adaptive banner size — fills the available width (instead of a
    /// fixed 320pt) at a COMPACT height (~50–60pt). We deliberately use the
    /// standard anchored-adaptive size, not the taller "Large" variant, for a
    /// lighter footprint on every screen: the width fill is the main eCPM win
    /// over a fixed 320×50; the extra Large height is the smaller increment.
    /// (The standard getter is deprecated in favour of Large, so this emits one
    /// intentional deprecation warning — accepted for the smaller footprint.)
    ///
    /// Computed once from the device's PORTRAIT width (stable across rotation)
    /// minus the gutter's 16pt side insets, then cached. Caching keeps the
    /// SwiftUI height reservation and the BannerView's `adSize` perfectly in
    /// sync — a mismatch would clip the creative or jump the layout.
    @MainActor private static var _adaptiveAdSize: AdSize?

    @MainActor
    static var adaptiveBannerAdSize: AdSize {
        if let s = _adaptiveAdSize { return s }
        let bounds = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.bounds ?? UIScreen.main.bounds
        // Portrait width regardless of current orientation, minus the gutter's
        // 16pt insets (×2) so the banner fits inside its rounded card.
        let width = min(bounds.width, bounds.height) - 32
        // portrait… (not currentOrientation…) so the cached height is the
        // stable portrait value and never clips after a rotation. Deprecated in
        // favour of the Large variant — intentional; we want the compact height.
        let size = portraitAnchoredAdaptiveBanner(width: width)
        _adaptiveAdSize = size
        return size
    }

    @MainActor static var adaptiveBannerWidth: CGFloat { adaptiveBannerAdSize.size.width }
    @MainActor static var adaptiveBannerHeight: CGFloat { adaptiveBannerAdSize.size.height }
}

/// Consent + ATT gate for App Store / personalized ads.
///
/// Order is required: Google UMP first (collects GDPR consent in the
/// EEA/UK), then Apple ATT (authorizes IDFA-based personalization), then
/// the Mobile Ads SDK is initialized. Runs exactly once per launch and is
/// a no-op on repeat calls, so it's safe to attach to a `.task`.
enum AdConsent {
    /// Hashed device IDs that force the UMP form to appear for testing.
    /// The SDK prints the current device's hash to the console on first
    /// run ("To get test ads on this device, set..."). Leave empty for
    /// production — only consulted in DEBUG.
    static let umpTestDeviceIdentifiers: [String] = []

    private static var ran = false

    @MainActor
    static func gatherThenStart() async {
        // Hard-stop when ads are disabled. Don't request consent, don't
        // start the Mobile Ads SDK, don't generate any traffic that could
        // hit a suspended AdMob account.
        guard AdConfig.adsEnabled else { return }
        guard !ran else { return }
        ran = true

        let params = RequestParameters()
        params.isTaggedForUnderAgeOfConsent = false
        #if DEBUG
        if !umpTestDeviceIdentifiers.isEmpty {
            let debug = DebugSettings()
            debug.geography = .EEA          // force the EEA form in DEBUG
            debug.testDeviceIdentifiers = umpTestDeviceIdentifiers
            params.debugSettings = debug
        }
        #endif

        // 1. Refresh consent status, then show the UMP form if required.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            ConsentInformation.shared.requestConsentInfoUpdate(with: params) { error in
                if let error {
                    adLog.error("UMP info update failed: \(error.localizedDescription)")
                    cont.resume(); return
                }
                ConsentForm.loadAndPresentIfRequired(from: nil) { formError in
                    if let formError {
                        adLog.error("UMP form error: \(formError.localizedDescription)")
                    }
                    cont.resume()
                }
            }
        }

        // 2. Apple ATT — required for IDFA-based personalization. Only
        //    actually presents while the app is active (the caller's
        //    `.task` runs after the scene is active).
        let status: ATTrackingManager.AuthorizationStatus =
            await withCheckedContinuation { cont in
                ATTrackingManager.requestTrackingAuthorization {
                    cont.resume(returning: $0)
                }
            }
        adLog.notice("ATT status: \(status.rawValue)")

        // 3. Consent resolved — safe to initialize the SDK and serve ads.
        AdConfig.startOnce()
    }
}

// MARK: - Banner refresh / retry constants

/// Minimum seconds between consecutive ad load() calls on the same view.
/// AdMob's default server-side refresh is 30–60 s. Using 45 s as the
/// debounce floor means tick-driven re-parents (which fire many times per
/// second) are collapsed into a single reload, while a legitimate recovery
/// attempt after the refresh interval fires promptly.
private let kAdRefreshDebounce: TimeInterval = 45

/// Retry delays (seconds) after a failed load: 5 → 10 → 30, then held at
/// 30 s. Three levels are sufficient; beyond 30 s AdMob's own retry logic
/// also starts kicking in, so aggressive retries would only compete with it.
private let kAdRetryDelays: [TimeInterval] = [5, 10, 30]

// MARK: - BannerHostView

/// Anchored-adaptive banner host. One `BannerHostView` is created per mount point
/// (each tab's `adBannerGutter` owns its own — see `BannerAdView.Coordinator`)
/// and lives for that mount's lifetime. Ad requests are gated by the
/// SDK-started signal, window attachment, and a debounce timer so the
/// frequent SwiftUI rebuilds (every AppModel `tick`) never spam load(). On
/// failure, exponential back-off retries are scheduled. The rootViewController
/// is refreshed every time the view re-enters a window so stale captures don't
/// confuse AdMob's presentation layer after a re-parent.
private final class BannerHostView: UIView {
    let banner: BannerView
    var onReady: (() -> Void)?
    private var sdkObserver: NSObjectProtocol?

    // ------------------------------------------------------------------
    // Debounce: tracks the last time load() was successfully dispatched so
    // rapid re-parent/rebuild cycles collapse into a single request.
    private var lastLoadTime: Date = .distantPast

    // Retry state: index into kAdRetryDelays; reset to 0 on success.
    private var retryIndex = 0
    private var retryWorkItem: DispatchWorkItem?

    // One-shot layout logger (unchanged from original).
    private var loggedLayoutOnce = false

    override init(frame: CGRect) {
        banner = BannerView(adSize: AdConfig.adaptiveBannerAdSize)
        super.init(frame: frame)
        adLog.notice("BannerHostView init")
        backgroundColor = .clear
        banner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(banner)
        NSLayoutConstraint.activate([
            banner.widthAnchor.constraint(equalToConstant: AdConfig.adaptiveBannerWidth),
            banner.heightAnchor.constraint(equalToConstant: AdConfig.adaptiveBannerHeight),
            banner.centerXAnchor.constraint(equalTo: centerXAnchor),
            banner.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        // If tryLoad fires before the SDK has finished initializing,
        // we hold the ad request until the start completion posts. Without
        // this, returning-user launches race load() ahead of MobileAds.start
        // and silently get nothing back.
        sdkObserver = NotificationCenter.default.addObserver(
            forName: AdConfig.didStartName, object: nil, queue: .main
        ) { [weak self] _ in
            adLog.notice("BannerHostView got SDK didStart notification")
            self?.tryLoad(reason: "sdkDidStart")
        }
    }

    deinit {
        retryWorkItem?.cancel()
        if let o = sdkObserver { NotificationCenter.default.removeObserver(o) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    // ------------------------------------------------------------------
    // MARK: UIView overrides

    override func didMoveToWindow() {
        super.didMoveToWindow()
        adLog.notice("BannerHostView didMoveToWindow window=\(self.window != nil) bounds=\(NSCoder.string(for: self.bounds))")

        // Refresh rootViewController every time we (re-)enter a window.
        // tabViewBottomAccessory re-parents the view frequently; the VC
        // captured at first load can go stale and confuse AdMob's presentation
        // layer, causing the creative to clear and never recover.
        if window != nil, let vc = BannerAdView.rootVC() {
            banner.rootViewController = vc
            adLog.debug("BannerHostView refreshed rootViewController: \(String(describing: type(of: vc)))")
        }

        tryLoad(reason: "didMoveToWindow")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !loggedLayoutOnce {
            loggedLayoutOnce = true
            adLog.notice("BannerHostView layoutSubviews bounds=\(NSCoder.string(for: self.bounds)) window=\(self.window != nil)")
        }
        tryLoad(reason: "layoutSubviews")
    }

    // ------------------------------------------------------------------
    // MARK: Load orchestration

    /// Central gate for all ad load attempts.
    ///
    /// Conditions required before calling load():
    ///   1. View is attached to a window (not mid-re-parent).
    ///   2. Banner has a non-zero width (layout is settled).
    ///   3. SDK has finished initializing (AdConfig.started).
    ///   4. At least `kAdRefreshDebounce` seconds have passed since the
    ///      last successful load() dispatch — collapses tick-driven
    ///      re-parents into a single request.
    ///
    /// `reason` is logged so Console.app clearly shows which code path
    /// triggered each load attempt.
    func tryLoad(reason: String) {
        let hasWindow = window != nil
        let hasWidth = banner.bounds.width > 0 || bounds.width > 0
        let sdkStarted = AdConfig.started
        let elapsed = Date().timeIntervalSince(lastLoadTime)
        let debounced = elapsed >= kAdRefreshDebounce

        guard hasWindow, hasWidth, sdkStarted else {
            adLog.debug("BannerHostView tryLoad(\(reason, privacy: .public)) skipped: window=\(hasWindow) width=\(hasWidth) sdk=\(sdkStarted)")
            return
        }
        guard debounced else {
            adLog.debug("BannerHostView tryLoad(\(reason, privacy: .public)) debounced: \(String(format: "%.1f", elapsed), privacy: .public)s < \(kAdRefreshDebounce, privacy: .public)s since last load")
            return
        }

        dispatchLoad(reason: reason)
    }

    /// Unconditionally fires a new ad request and resets retry state.
    /// Call only after all guards in `tryLoad` have passed, or from the
    /// retry work item (which has its own elapsed-time check).
    private func dispatchLoad(reason: String) {
        retryWorkItem?.cancel()
        retryWorkItem = nil
        lastLoadTime = Date()

        // Always re-resolve rootViewController immediately before load()
        // so we never hand AdMob a stale hierarchy.
        if let vc = BannerAdView.rootVC() {
            banner.rootViewController = vc
        }

        adLog.notice("BannerHostView dispatchLoad(\(reason, privacy: .public)) → load()")
        onReady?()
    }

    // ------------------------------------------------------------------
    // MARK: Delegate callbacks (called by BannerAdView.Coordinator)

    /// Called by `BannerAdView.Coordinator.bannerViewDidReceiveAd`. Resets retry
    /// state so the next failure starts the back-off sequence fresh.
    func didReceiveAd() {
        retryIndex = 0
        retryWorkItem?.cancel()
        retryWorkItem = nil
        adLog.notice("BannerHostView didReceiveAd — retry state reset")
    }

    /// Called by `BannerAdView.Coordinator.bannerView(_:didFailToReceiveAdWithError:)`.
    /// Schedules a retry after exponential back-off. Each successive failure
    /// advances the index (5 s → 10 s → 30 s, then stays at 30 s).
    func didFailWithError(_ error: Error) {
        retryWorkItem?.cancel()

        let delay = kAdRetryDelays[min(retryIndex, kAdRetryDelays.count - 1)]
        retryIndex = min(retryIndex + 1, kAdRetryDelays.count - 1)

        adLog.error("BannerHostView didFail: \(error.localizedDescription) — retrying in \(delay, privacy: .public)s (retryIndex now \(self.retryIndex, privacy: .public))")

        let item = DispatchWorkItem { [weak self] in
            guard let self, self.window != nil else {
                adLog.debug("BannerHostView retry fired but no window — skipping")
                return
            }
            // Bypass the debounce: the failure handler already waited long
            // enough, and the point of the retry is to recover, not to wait
            // again for kAdRefreshDebounce.
            adLog.notice("BannerHostView retry firing after \(delay, privacy: .public)s back-off")
            self.dispatchLoad(reason: "retry")
        }
        retryWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}

// MARK: - BannerAdView

/// Anchored-adaptive banner — fills the available width at a compact
/// Google-optimized anchored height.
///
/// Each mount point gets its OWN host + delegate, held in the representable's
/// `Coordinator`. This is deliberate: the redesign mounts `adBannerGutter`
/// once per tab (Home / Saved / Search / Settings), so four `BannerAdView`s
/// coexist. A UIView can only live in one superview at a time, so a single
/// shared host would be "stolen" by whichever tab was visited last, leaving
/// the others blank on return — the exact bug this replaced. With one host
/// per tab, every tab keeps its own banner permanently.
///
/// SwiftUI calls `makeCoordinator` once per stable view identity (each tab's
/// gutter is stable across AppModel `tick` rebuilds), so the host is NOT
/// reallocated on every rebuild — `updateUIView` is a no-op. Load
/// orchestration (debounce, retry, rootVC refresh) is owned entirely by
/// `BannerHostView`, and its `window != nil` gate means only the currently
/// visible tab ever requests an ad (the TabView keeps only the selected tab
/// in the window), so multiple hosts stay AdMob-policy-clean.
private struct BannerAdView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> BannerHostView {
        let host = context.coordinator.host
        let banner = host.banner
        banner.adUnitID = AdConfig.bannerUnitID
        banner.delegate = context.coordinator
        // Wire the onReady closure: called by dispatchLoad() each time a
        // fresh request should go out. rootViewController is set immediately
        // before load() inside dispatchLoad, so it's always current.
        host.onReady = { [weak banner] in
            banner?.load(Request())
        }
        return host
    }

    func updateUIView(_ uiView: BannerHostView, context: Context) {}

    /// Per-instance owner of the banner UIView + ad delegate. One is created
    /// for each `BannerAdView` (i.e. one per tab gutter) and retained for that
    /// view's lifetime.
    @MainActor
    final class Coordinator: NSObject, BannerViewDelegate {
        let host = BannerHostView(frame: .zero)

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            adLog.notice("Banner loaded \(bannerView.adUnitID ?? "?")")
            host.didReceiveAd()
        }
        func bannerView(_ bannerView: BannerView,
                        didFailToReceiveAdWithError error: Error) {
            adLog.error("Banner failed: \(error.localizedDescription)")
            host.didFailWithError(error)
        }
    }

    /// Resolves the current key-window rootViewController. Called from
    /// BannerHostView so the VC is refreshed on every re-parent, not just
    /// the first load.
    static func rootVC() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}

// MARK: - Probes (unchanged)

/// One-shot logger for the bottomAdBanner branch + screenshot flag state.
/// The presence of `-screenshots` in `ProcessInfo.arguments` is a frequent
/// foot-gun — Xcode caches scheme settings and silent-fail short-circuits
/// the whole accessory. We capture the live value once so the next launch
/// either confirms the flag is off (and the missing banner is elsewhere)
/// or proves the flag is still being applied.
private enum BottomAdBannerProbe {
    nonisolated(unsafe) static var did = false
    static func logOnce() {
        if did { return }; did = true
        let mode = AdConfig.screenshotMode
        let args = ProcessInfo.processInfo.arguments
        let branch: String
        if mode { branch = "SCREENSHOT (no banner)" }
        else if #available(iOS 26.0, *) { branch = "iOS 26 tabViewBottomAccessory" }
        else { branch = "legacy safeAreaInset" }
        adLog.notice("bottomAdBanner first call: screenshotMode=\(mode, privacy: .public) branch=\(branch, privacy: .public) args=\(args, privacy: .public)")
    }
}

/// Drop-in anchored-adaptive banner, centered. Reserves the SDK-reported
/// adaptive height so it never overlaps content. A faint surface fill sits behind the
/// `BannerAdView` until the ad loads — `tabViewBottomAccessory` on iOS 26
/// collapses fully-transparent accessory content, which made an unloaded
/// banner look like it wasn't mounted at all.
struct AdBanner: View {
    @EnvironmentObject private var m: AppModel
    var body: some View {
        let _ = AdBannerProbe.logOnce()
        ZStack {
            // Slightly darker than the page background (surfaceHi vs surface)
            // so the accessory area is perceptible even before an ad loads —
            // iOS 26's tabViewBottomAccessory collapses fully-transparent
            // content. surfaceHi == hero-card colour, so it reads as part
            // of the design language, not a stray panel.
            m.t.surfaceHi
            BannerAdView()
                .frame(width: AdConfig.adaptiveBannerWidth,
                       height: AdConfig.adaptiveBannerHeight)
        }
        .frame(maxWidth: .infinity, minHeight: AdConfig.adaptiveBannerHeight)
    }
}

/// One-shot logger so we know `AdBanner.body` actually evaluated. Without
/// this, a missing banner could be explained either by tabViewBottomAccessory
/// not invoking the closure (zero log) or by the SDK never loading the ad
/// (the BannerHostView logs will fire instead).
private enum AdBannerProbe {
    nonisolated(unsafe) static var did = false
    static func logOnce() {
        if did { return }; did = true
        adLog.notice("AdBanner.body evaluated for first time")
    }
}

// MARK: - View extensions

extension View {
    /// Banner for the main `TabView`.
    ///
    /// iOS 26's tab bar is a floating Liquid Glass pill that draws *over*
    /// content, so a `safeAreaInset` banner pinned to the bottom ends up
    /// underneath it. `tabViewBottomAccessory` is the system-provided slot
    /// for persistent UI directly above the tab bar — it never overlaps and
    /// adopts the glass treatment automatically.
    ///
    /// On iOS 18–25 the tab bar is a fixed opaque strip, so the original
    /// `safeAreaInset` placement (banner above the bar) is still correct.
    @ViewBuilder
    func bottomAdBanner(_ t: Theme) -> some View {
        let _ = BottomAdBannerProbe.logOnce()
        if !AdConfig.adsEnabled || AdConfig.screenshotMode {
            self
        } else if #available(iOS 26.0, *) {
            tabViewBottomAccessory {
                AdBanner().frame(maxWidth: .infinity)
            }
        } else {
            overlayAdBanner(t)
        }
    }

    /// Pins the compact banner above the bottom safe area with a hairline
    /// divider on the app surface. Used for full-screen overlays (e.g. the
    /// search sheet) that sit above the `TabView` and so can't use the
    /// `tabViewBottomAccessory` slot.
    @ViewBuilder
    func overlayAdBanner(_ t: Theme) -> some View {
        if !AdConfig.adsEnabled || AdConfig.screenshotMode {
            self
        } else {
            safeAreaInset(edge: .bottom, spacing: 0) {
                AdBanner()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(t.surface)
                    .overlay(alignment: .top) {
                        Rectangle().fill(t.line).frame(height: 1)
                    }
            }
        }
    }
}
