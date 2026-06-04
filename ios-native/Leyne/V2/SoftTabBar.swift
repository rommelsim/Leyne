// SoftTab — tab identity for the native iOS 26 TabView mounted in
// SoftRoot. The custom floating-pill tab bar that used to live here was
// replaced by the system TabView, which renders the Liquid Glass bar and
// the detached `.search` circle natively. This file now only carries the
// tab enum plus the ad-banner gutter the tabbed screens share.

import SwiftUI

enum SoftTab: String, CaseIterable {
    case home, favourites, nearby, settings, search
}

// MARK: - Top scroll-edge blur

extension View {
    /// Re-instates the iOS 26 soft scroll-edge effect on the top edge.
    /// These screens hide the navigation bar, which is what normally
    /// anchors the system's top blur — without it, scrolled content
    /// bleeds straight under the status bar / Dynamic Island. Requesting
    /// the `.soft` style restores a progressive blur so the OS chrome
    /// stays legible. No-op on iOS 25 and below.
    @ViewBuilder
    func softTopEdgeBlur() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}

// MARK: - Ad banner gutter

extension View {
    /// Inserts the AdMob banner just above the floating tab bar via a
    /// bottom safe-area inset, so it sits in the same gutter on every
    /// tabbed screen and never occludes scroll content. Self-suppresses
    /// when ads are disabled or screenshot mode is on.
    @ViewBuilder
    func adBannerGutter() -> some View {
        if AdConfig.adsEnabled && !AdConfig.screenshotMode {
            self.safeAreaInset(edge: .bottom) {
                AdBanner()
                    .frame(height: 50)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12,
                                                style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }
        } else {
            self
        }
    }
}
