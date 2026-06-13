---
name: project-native-ad
description: Native ad implementation for the Home nearby list — AdConfig.nativeUnitID, NativeAdLoader, NativeAdUIView, NativeAdCard, placement in SoftHomeView
metadata:
  type: project
---

Native ad (GoogleMobileAds inline) shipped in `ios-native/Leyne/V2/NativeAdCard.swift` (2026-06-14).

Key facts:
- `AdConfig.nativeUnitID` added to `AdBanner.swift` mirroring the mrecUnitID DEBUG/RELEASE/forceTestUnit gate. DEBUG → `ca-app-pub-3940256099942544/3986624511`; RELEASE prod → `ca-app-pub-5864511655536507/2734244623`.
- `NativeAdLoader` is a `@MainActor ObservableObject` using the same SDK-started gate as `BannerHostView` (NotificationCenter `AdConfig.didStartName`). One load, exponential-backoff retry (5/10/30 s). No mid-session refresh.
- `NativeAdUIView` wraps `NativeAdView` (Swift name for `GADNativeAdView`). Asset outlets wired: `headlineView`, `bodyView`, `advertiserView`, `iconView`, `callToActionView`. `PaddedLabel` custom subclass used for the "Ad" badge (6 pt horizontal padding via `drawText(in:)` override).
- CTA button uses `UIButton.Configuration.filled()` — NOT deprecated `contentEdgeInsets`.
- SDK Swift name: `NativeAdView` (not `GADNativeAdView`), `NativeAdLoaderDelegate` (not `GADNativeAdLoaderDelegate`), `NativeAd`, `AdLoader`, `Request`.
- `NativeAdCard` renders `EmptyView` when no ad is loaded or `AdConfig.adsSuppressed` — no gap/placeholder.
- Placed in `SoftHomeView.swift` `ForEach(Array(others.enumerated()), …)` — emits after index 2 (3rd card in "More stops").

**Why:** Home shows the bottom adaptive banner + this one inline native — two ad placements per AdMob phase plan.

**How to apply:** If adding further native placements, reuse `NativeAdLoader` + `NativeAdUIView`. Don't add a second `NativeAdCard` to Home without an explicit ask (policy risk + UX).
