// Google AdMob banner + consent.
//
// CONFIG:
//  • App ID lives in `LyneInfo.plist` as `GADApplicationIdentifier`
//    (the real AdMob App ID — ca-app-pub-1910837226291536~3240337627).
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

private let adLog = Logger(subsystem: "com.lyne.Lyne", category: "Ads")

enum AdConfig {
    // Ad unit is gated by build configuration so testing is always safe and
    // production always earns — no manual swapping:
    //   • DEBUG  (Xcode Run → Simulator/device): Google's official always-
    //            test banner unit. Renders a "Test mode" ad anywhere, on any
    //            device, with zero AdMob policy risk. Use this to test.
    //   • RELEASE (Archive → TestFlight/App Store): this account's real
    //            production ad unit → real, revenue-generating ads.
    #if DEBUG
    static let bannerUnitID = "ca-app-pub-3940256099942544/2435281174"
    #else
    static let bannerUnitID = "ca-app-pub-1910837226291536/6928301192"
    #endif

    /// Extra devices to force into TEST ads even in a RELEASE build (rarely
    /// needed — DEBUG already serves test ads everywhere). Leave empty.
    static let testDeviceIdentifiers: [String] = []

    private static var started = false
    /// Idempotent SDK start. Safe to call more than once. Call only *after*
    /// consent has been gathered — see `AdConsent.gatherThenStart()`.
    static func startOnce() {
        guard !started else { return }
        started = true
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers =
            testDeviceIdentifiers
        MobileAds.shared.start(completionHandler: nil)
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
        guard !ran else { return }
        ran = true

        let params = RequestParameters()
        params.isTaggedForUnderAgeOfConsent = false
        #if DEBUG
        if !umpTestDeviceIdentifiers.isEmpty {
            let debug = ConsentDebugSettings()
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

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        banner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(banner)
        NSLayoutConstraint.activate([
            banner.widthAnchor.constraint(equalToConstant: 320),
            banner.heightAnchor.constraint(equalToConstant: 50),
            banner.centerXAnchor.constraint(equalTo: centerXAnchor),
            banner.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !fired, window != nil, banner.bounds.width > 0 else { return }
        fired = true
        onReady?()
    }
}

/// Standard fixed 320×50 banner — the smallest, least-intrusive size.
///
/// The host view is retained by the coordinator so it survives the repeated
/// rebuilds `tabViewBottomAccessory` performs (entry animation, collapsing
/// into the tab bar on scroll). Combined with the single-shot `onReady`,
/// exactly one ad request is ever made — fixing both the flashing (a fresh
/// request per rebuild when loading in `makeUIView`) and the "Invalid ad
/// width or height" error (loading before the view had a size).
private struct BannerAdView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> BannerHostView {
        let host = context.coordinator.host
        let banner = host.banner
        banner.adUnitID = AdConfig.bannerUnitID
        banner.delegate = context.coordinator
        host.onReady = {
            let c = context.coordinator
            guard !c.didLoad else { return }
            c.didLoad = true
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

    final class Coordinator: NSObject, BannerViewDelegate {
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
}

/// Drop-in compact banner: fixed 320×50, centered. Reserves exactly 50pt
/// so it never overlaps content.
struct AdBanner: View {
    var body: some View {
        BannerAdView()
            .frame(width: 320, height: 50)
            .frame(maxWidth: .infinity)
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
        if #available(iOS 26.0, *) {
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
    func overlayAdBanner(_ t: Theme) -> some View {
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
