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
    /// Google's official iOS *test* adaptive-banner ad unit. Replace only if
    /// you specifically want to exercise your own (test) ad unit.
    static let bannerUnitID = "ca-app-pub-3940256099942544/2435281174"

    private static var started = false
    /// Idempotent SDK start. Safe to call more than once.
    static func startOnce() {
        guard !started else { return }
        started = true
        MobileAds.shared.start(completionHandler: nil)
    }
}

/// SwiftUI wrapper around a GoogleMobileAds `BannerView`, sized to an
/// anchored adaptive banner for the given width.
private struct BannerAdView: UIViewRepresentable {
    let width: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> BannerView {
        let size = largeAnchoredAdaptiveBanner(width: width)
        let view = BannerView(adSize: size)
        view.adUnitID = AdConfig.bannerUnitID
        view.delegate = context.coordinator
        view.rootViewController = Self.rootVC()
        view.load(Request())
        return view
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        let size = largeAnchoredAdaptiveBanner(width: width)
        if uiView.adSize.size.width != size.size.width {
            uiView.adSize = size
            uiView.load(Request())
        }
    }

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

/// Drop-in bottom banner. Reserves exactly the adaptive banner height so it
/// never overlaps content, and blends with the app surface.
struct AdBanner: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = largeAnchoredAdaptiveBanner(width: w).size.height
            BannerAdView(width: w)
                .frame(width: w, height: h)
                .frame(maxWidth: .infinity)
        }
        .frame(height: largeAnchoredAdaptiveBanner(
            width: UIScreen.main.bounds.width).size.height)
    }
}
