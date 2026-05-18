// Google AdMob banner (test mode).
//
// TEST SETUP — safe by design:
//  • App ID lives in Info.plist as `GADApplicationIdentifier` (build setting
//    INFOPLIST_KEY_GADApplicationIdentifier). It is currently Google's SAMPLE
//    App ID. Swap it for your real AdMob App ID (ca-app-pub-XXXX~YYYY) there.
//  • The ad UNIT below is Google's official always-test banner unit, so it
//    never serves live ads and can't trigger AdMob policy strikes.
//  • The iOS Simulator is automatically a test device regardless.

import SwiftUI
import GoogleMobileAds
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
    /// Idempotent SDK start. Safe to call more than once.
    static func startOnce() {
        guard !started else { return }
        started = true
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers =
            testDeviceIdentifiers
        MobileAds.shared.start(completionHandler: nil)
    }
}

/// Standard fixed 320×50 banner — the smallest, least-intrusive size.
private struct BannerAdView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> BannerView {
        let view = BannerView(adSize: AdSizeBanner)   // 320 × 50
        view.adUnitID = AdConfig.bannerUnitID
        view.delegate = context.coordinator
        view.rootViewController = Self.rootVC()
        view.load(Request())
        return view
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    private static func rootVC() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }

    final class Coordinator: NSObject, BannerViewDelegate {
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
    /// Pins the compact banner above the bottom safe area (tab bar) with a
    /// hairline divider on the app surface. One definition, used everywhere.
    func bottomAdBanner(_ t: Theme) -> some View {
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
