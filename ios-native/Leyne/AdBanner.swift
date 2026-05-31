// Google AdMob banner + consent.
//
// CONFIG:
//  • App ID lives in `LeyneInfo.plist` as `GADApplicationIdentifier`
//    (the real AdMob App ID — ca-app-pub-6816620800052795~4249846169).
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
    // Production unit lives in the verified personal Google AdMob account
    // (ca-app-pub-6816620800052795), matching the
    // GADApplicationIdentifier in LeyneInfo.plist
    // (ca-app-pub-6816620800052795~4249846169).
    #if DEBUG
    static let bannerUnitID = "ca-app-pub-3940256099942544/2934735716"
    #else
    static let bannerUnitID = forceTestUnitForRelease
        ? "ca-app-pub-3940256099942544/2934735716"  // Google test unit
        : "ca-app-pub-6816620800052795/8532706109"  // personal-acct prod
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

        // 2. Apple ATT — required for IDFA-based personalized ads. Only
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

/// Fixed-size 320×50 host. The `BannerView` and one ad request are bound to
/// this view's lifetime: the request fires from `layoutSubviews` the first
/// time the view is actually on screen with a real size. `layoutSubviews`
/// (not `updateUIView`) is the trigger because SwiftUI does not reliably
/// re-run `updateUIView` once the view lands in a window.
private final class BannerHostView: UIView {
    let banner = BannerView(adSize: AdSizeBanner)   // 320 × 50
    var onReady: (() -> Void)?
    private var fired = false
    private var sdkObserver: NSObjectProtocol?

    override init(frame: CGRect) {
        super.init(frame: frame)
        adLog.notice("BannerHostView init")
        backgroundColor = .clear
        banner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(banner)
        NSLayoutConstraint.activate([
            banner.widthAnchor.constraint(equalToConstant: 320),
            banner.heightAnchor.constraint(equalToConstant: 50),
            banner.centerXAnchor.constraint(equalTo: centerXAnchor),
            banner.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        // If layoutSubviews fires before the SDK has finished initializing,
        // we hold the ad request until the start completion posts. Without
        // this, returning-user launches race load() ahead of MobileAds.start
        // and silently get nothing back.
        sdkObserver = NotificationCenter.default.addObserver(
            forName: AdConfig.didStartName, object: nil, queue: .main
        ) { [weak self] _ in
            adLog.notice("BannerHostView got SDK didStart notification")
            self?.tryFire()
        }
    }

    deinit {
        if let o = sdkObserver { NotificationCenter.default.removeObserver(o) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        adLog.notice("BannerHostView didMoveToWindow window=\(self.window != nil) bounds=\(NSCoder.string(for: self.bounds))")
        tryFire()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !loggedLayoutOnce {
            loggedLayoutOnce = true
            adLog.notice("BannerHostView layoutSubviews bounds=\(NSCoder.string(for: self.bounds)) window=\(self.window != nil)")
        }
        tryFire()
    }
    private var loggedLayoutOnce = false

    private func tryFire() {
        if fired { return }
        let hasWindow = window != nil
        let hasWidth = banner.bounds.width > 0
        let sdkStarted = AdConfig.started
        guard hasWindow, hasWidth, sdkStarted else {
            adLog.debug("BannerHostView tryFire skipped: window=\(hasWindow) width=\(hasWidth) sdk=\(sdkStarted)")
            return
        }
        adLog.notice("BannerHostView tryFire → load()")
        fired = true
        onReady?()
    }
}

/// Process-singleton owner of the banner UIView + ad delegate. SwiftUI's
/// `tabViewBottomAccessory` re-evaluates its content closure many times
/// per app session — every accessory expand/collapse with scroll, every
/// AppModel `tick` publish, every theme change. The previous design held
/// the host inside a `Coordinator` that SwiftUI also recreates on each
/// rebuild, so every cycle allocated a fresh `BannerHostView`, fresh
/// `BannerView`, fresh delegate, and fired its own ad request. Hoisting
/// the host into a static let means one of each, for the app's lifetime.
/// iOS handles the UIView being re-parented across rebuilds transparently.
@MainActor
private final class BannerHostHolder: NSObject, BannerViewDelegate {
    static let shared = BannerHostHolder()
    let host = BannerHostView(frame: .zero)
    var didLoad = false

    func bannerViewDidReceiveAd(_ bannerView: BannerView) {
        adLog.notice("Banner loaded (test) \(bannerView.adUnitID ?? "?")")
    }
    func bannerView(_ bannerView: BannerView,
                    didFailToReceiveAdWithError error: Error) {
        adLog.error("Banner failed: \(error.localizedDescription)")
    }
}

/// Standard fixed 320×50 banner — the smallest, least-intrusive size.
///
/// The host view + delegate live in `BannerHostHolder.shared` so a single
/// pair survives every SwiftUI rebuild of the accessory. `makeUIView`
/// re-applies the configuration each time (idempotent) and returns the
/// same `BannerHostView`. The `didLoad` flag on the holder ensures the
/// banner load fires exactly once per app session.
private struct BannerAdView: UIViewRepresentable {
    func makeUIView(context: Context) -> BannerHostView {
        let holder = BannerHostHolder.shared
        let host = holder.host
        let banner = host.banner
        banner.adUnitID = AdConfig.bannerUnitID
        banner.delegate = holder
        host.onReady = {
            guard !holder.didLoad else { return }
            holder.didLoad = true
            banner.rootViewController = Self.rootVC()
            banner.load(Request())
        }
        return host
    }

    func updateUIView(_ uiView: BannerHostView, context: Context) {}

    private static func rootVC() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}

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

/// Drop-in compact banner: fixed 320×50, centered. Reserves exactly 50pt
/// so it never overlaps content. A faint surface fill sits behind the
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
                .frame(width: 320, height: 50)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
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
