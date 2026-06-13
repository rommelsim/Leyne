// NativeAdCard — inline native ad for the Home nearby list.
//
// Architecture overview:
//   NativeAdLoader  — ObservableObject; owns one AdLoader (GADAdLoader →
//                     Swift name "AdLoader"), respects the same
//                     AdConfig.started / AdConsent gate as BannerHostView.
//                     One load, then exponential-backoff retry on failure.
//                     Exposes the loaded NativeAd to SwiftUI.
//
//   NativeAdUIView  — UIViewRepresentable wrapping NativeAdView (GADNativeAdView
//                     → Swift name "NativeAdView"); registers all asset
//                     subviews so AdMob can track impressions/clicks.
//
//   NativeAdCard    — SwiftUI card: "Ad" badge + headline + body + icon +
//                     CTA button. Styled monochrome with t.surface / t.fg /
//                     t.dim tokens to sit as a sibling of SoftNearbyStopCard.
//                     Only rendered when an ad is loaded and consent is ready;
//                     callers see EmptyView otherwise (no empty gap).
//
// AdMob policy requirements satisfied:
//   • "Ad" attribution label — always visible, per policy §3.
//   • headlineView outlet wired — required.
//   • bodyView, iconView, callToActionView, advertiserView wired when present.
//   • NativeAdView is the root interaction target — taps route correctly.
//   • No custom click-handling; interaction delegate left to SDK defaults.

import SwiftUI
import GoogleMobileAds
import os

private let nativeLog = Logger(subsystem: "com.leyne.Leyne", category: "NativeAd")

// MARK: - Retry constants (mirrors BannerHostView strategy)

private let kNativeRetryDelays: [TimeInterval] = [5, 10, 30]

// MARK: - NativeAdLoader

/// Loads one NativeAd and exposes it to SwiftUI.
///
/// Lifecycle:
///   1. load() is called once the SDK has started (gated by AdConfig.started
///      + a NotificationCenter observer for the didStart notification —
///      the exact same pattern as BannerHostView). Prevents the race between
///      SDK initialisation and the first ad request on returning-user launches.
///   2. On success, `nativeAd` is set and the SwiftUI card renders.
///   3. On failure, exponential back-off retries: 5 s → 10 s → 30 s (held).
///      Retries stop if the loader is deallocated.
///   4. A second load() call is a no-op once an ad was successfully received
///      (no mid-session refresh to avoid layout shift).
@MainActor
final class NativeAdLoader: NSObject, ObservableObject,
                            AdLoaderDelegate, NativeAdLoaderDelegate {
    @Published private(set) var nativeAd: NativeAd?

    private var loader: AdLoader?
    private var retryIndex = 0
    private var retryWorkItem: DispatchWorkItem?
    private var sdkObserver: NSObjectProtocol?
    private var hasLoaded = false   // true once an ad was successfully received

    override init() {
        super.init()
        if AdConfig.started {
            triggerLoad()
        } else {
            // queue: nil — we hop explicitly to @MainActor so the compiler
            // knows the call site is main-actor-isolated (no isolation warning).
            sdkObserver = NotificationCenter.default.addObserver(
                forName: AdConfig.didStartName, object: nil, queue: nil
            ) { [weak self] _ in
                nativeLog.notice("NativeAdLoader received SDK didStart")
                Task { @MainActor [weak self] in self?.triggerLoad() }
            }
        }
    }

    deinit {
        retryWorkItem?.cancel()
        if let o = sdkObserver { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: Load orchestration

    private func triggerLoad() {
        guard !hasLoaded else { return }
        guard !AdConfig.adsSuppressed else { return }

        if let o = sdkObserver {
            NotificationCenter.default.removeObserver(o)
            sdkObserver = nil
        }

        retryWorkItem?.cancel()
        retryWorkItem = nil

        nativeLog.notice("NativeAdLoader triggerLoad → AdLoader.load()")
        let adLoader = AdLoader(
            adUnitID: AdConfig.nativeUnitID,
            rootViewController: rootVC(),
            adTypes: [.native],
            options: nil
        )
        adLoader.delegate = self
        self.loader = adLoader
        adLoader.load(Request())
    }

    private func scheduleRetry() {
        let delay = kNativeRetryDelays[min(retryIndex, kNativeRetryDelays.count - 1)]
        retryIndex = min(retryIndex + 1, kNativeRetryDelays.count - 1)
        nativeLog.notice("NativeAdLoader scheduling retry in \(delay, privacy: .public)s")

        let item = DispatchWorkItem { [weak self] in
            self?.triggerLoad()
        }
        retryWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: AdLoaderDelegate

    nonisolated func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        nativeLog.error("NativeAdLoader failed: \(error.localizedDescription)")
        Task { @MainActor in self.scheduleRetry() }
    }

    // MARK: NativeAdLoaderDelegate

    nonisolated func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        nativeLog.notice("NativeAdLoader didReceive headline=\(nativeAd.headline ?? "nil", privacy: .public)")
        Task { @MainActor in
            self.nativeAd = nativeAd
            self.hasLoaded = true
            self.retryIndex = 0
            self.retryWorkItem?.cancel()
            self.retryWorkItem = nil
        }
    }

    // MARK: Helpers

    private func rootVC() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}

// MARK: - NativeAdUIView

/// UIViewRepresentable wrapping NativeAdView and wiring all asset subviews
/// so AdMob can attribute impressions and route clicks correctly.
///
/// Asset wiring is required by AdMob policy: NativeAdView must hold
/// UIView references for every rendered asset. The SDK attaches gesture
/// recognisers to those outlets — do NOT add your own tap handlers.
struct NativeAdUIView: UIViewRepresentable {
    let nativeAd: NativeAd
    let theme: Theme

    func makeUIView(context: Context) -> NativeAdView {
        let adView = NativeAdView()
        adView.backgroundColor = .clear

        // ── Headline (required) ───────────────────────────────────────────
        let headlineLabel = UILabel()
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false
        headlineLabel.numberOfLines = 2
        headlineLabel.adjustsFontForContentSizeCategory = true
        adView.headlineView = headlineLabel

        // ── Body ──────────────────────────────────────────────────────────
        let bodyLabel = UILabel()
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.numberOfLines = 3
        bodyLabel.adjustsFontForContentSizeCategory = true
        adView.bodyView = bodyLabel

        // ── Advertiser ────────────────────────────────────────────────────
        let advertiserLabel = UILabel()
        advertiserLabel.translatesAutoresizingMaskIntoConstraints = false
        advertiserLabel.numberOfLines = 1
        adView.advertiserView = advertiserLabel

        // ── Icon image ────────────────────────────────────────────────────
        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.clipsToBounds = true
        iconView.layer.cornerRadius = 8
        iconView.layer.cornerCurve = .continuous
        adView.iconView = iconView

        // ── Call-to-action button ─────────────────────────────────────────
        // isUserInteractionEnabled = false — NativeAdView owns the tap event.
        // We use UIButtonConfiguration (iOS 15+) to avoid the deprecated
        // contentEdgeInsets property and get proper content padding.
        var ctaConfig = UIButton.Configuration.filled()
        ctaConfig.cornerStyle = .capsule
        ctaConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attr in
            var a = attr
            a.font = scaledFont(size: 13, weight: .semibold)
            return a
        }
        let ctaButton = UIButton(configuration: ctaConfig)
        ctaButton.translatesAutoresizingMaskIntoConstraints = false
        ctaButton.isUserInteractionEnabled = false
        adView.callToActionView = ctaButton

        // ── "Ad" attribution badge ────────────────────────────────────────
        // Required by AdMob policy §3 — must be clearly visible at all times.
        // Styled as a small surfaceHi pill with dim text, matching the
        // "Closest stop" badge pattern on SoftNearbyStopCard.
        let adBadge = PaddedLabel()
        adBadge.translatesAutoresizingMaskIntoConstraints = false
        adBadge.text = "Ad"
        adBadge.adjustsFontForContentSizeCategory = true
        adBadge.textAlignment = .center

        // ── Assemble the card layout ──────────────────────────────────────
        let container = buildContainer(
            adView: adView,
            headlineLabel: headlineLabel,
            bodyLabel: bodyLabel,
            advertiserLabel: advertiserLabel,
            iconView: iconView,
            ctaButton: ctaButton,
            adBadge: adBadge,
            theme: theme,
            nativeAd: nativeAd
        )
        adView.addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: adView.topAnchor),
            container.leadingAnchor.constraint(equalTo: adView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: adView.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: adView.bottomAnchor),
        ])

        // Register assets — MUST happen after outlets are set.
        adView.nativeAd = nativeAd

        return adView
    }

    func updateUIView(_ uiView: NativeAdView, context: Context) {
        // Single-use; the loader never replaces an ad mid-session.
    }

    // MARK: - Layout

    private func buildContainer(
        adView: NativeAdView,
        headlineLabel: UILabel,
        bodyLabel: UILabel,
        advertiserLabel: UILabel,
        iconView: UIImageView,
        ctaButton: UIButton,
        adBadge: PaddedLabel,
        theme: Theme,
        nativeAd: NativeAd
    ) -> UIView {
        let fg        = UIColor(theme.fg)
        let dim       = UIColor(theme.dim)
        let surfaceHi = UIColor(theme.surfaceHi)
        let accent    = UIColor(theme.accent)
        let onAccent  = UIColor(theme.onAccent)

        // "Ad" badge styling
        adBadge.font = scaledFont(size: 10, weight: .semibold)
        adBadge.textColor = dim
        adBadge.backgroundColor = surfaceHi
        adBadge.layer.cornerRadius = 5
        adBadge.layer.cornerCurve = .continuous
        adBadge.clipsToBounds = true

        // Headline
        headlineLabel.text = nativeAd.headline
        headlineLabel.font = scaledFont(size: 15, weight: .semibold)
        headlineLabel.textColor = fg

        // Body
        bodyLabel.text = nativeAd.body
        bodyLabel.font = scaledFont(size: 12, weight: .regular)
        bodyLabel.textColor = dim
        bodyLabel.isHidden = nativeAd.body == nil

        // Advertiser
        advertiserLabel.text = nativeAd.advertiser
        advertiserLabel.font = scaledFont(size: 11, weight: .regular)
        advertiserLabel.textColor = dim
        advertiserLabel.isHidden = nativeAd.advertiser == nil

        // Icon
        if let icon = nativeAd.icon {
            iconView.image = icon.image
            iconView.isHidden = false
        } else {
            iconView.isHidden = true
        }

        // CTA button — update configuration colours
        let ctaTitle = nativeAd.callToAction ?? "Learn More"
        var config = ctaButton.configuration ?? UIButton.Configuration.filled()
        config.title = ctaTitle
        config.baseForegroundColor = onAccent
        config.baseBackgroundColor = accent
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        ctaButton.configuration = config

        // Layout
        let container = UIView()
        container.backgroundColor = .clear
        [headlineLabel, bodyLabel, advertiserLabel, iconView, ctaButton, adBadge]
            .forEach { container.addSubview($0) }

        let iconSize: CGFloat = 42

        NSLayoutConstraint.activate([
            // Icon: top-left
            iconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),

            // "Ad" badge: top-right
            adBadge.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            adBadge.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            adBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 28),
            adBadge.heightAnchor.constraint(equalToConstant: 18),

            // Headline: right of icon, left of badge
            headlineLabel.topAnchor.constraint(equalTo: iconView.topAnchor),
            headlineLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            headlineLabel.trailingAnchor.constraint(equalTo: adBadge.leadingAnchor, constant: -8),

            // Body: below headline, same span
            bodyLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 3),
            bodyLabel.leadingAnchor.constraint(equalTo: headlineLabel.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: headlineLabel.trailingAnchor),

            // Second row: below icon
            advertiserLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 10),
            advertiserLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            advertiserLabel.trailingAnchor.constraint(equalTo: ctaButton.leadingAnchor, constant: -8),

            // CTA: right-aligned to advertiser row
            ctaButton.centerYAnchor.constraint(equalTo: advertiserLabel.centerYAnchor),
            ctaButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),

            // Container bottom clears whichever is taller
            container.bottomAnchor.constraint(
                greaterThanOrEqualTo: advertiserLabel.bottomAnchor, constant: 14),
            container.bottomAnchor.constraint(
                greaterThanOrEqualTo: ctaButton.bottomAnchor, constant: 14),
        ])

        return container
    }

    // MARK: - Font helper

    private func scaledFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        UIFontMetrics.default.scaledFont(for: UIFont.systemFont(ofSize: size, weight: weight))
    }
}

// MARK: - PaddedLabel

/// UILabel with fixed horizontal padding — used for the "Ad" attribution badge.
/// UILabel has no built-in content inset; we override drawText(in:) and
/// sizeThatFits(_:) to add symmetric horizontal padding (6 pt each side).
private final class PaddedLabel: UILabel {
    private let hPad: CGFloat = 6

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.insetBy(dx: hPad, dy: 0))
    }

    override var intrinsicContentSize: CGSize {
        let base = super.intrinsicContentSize
        return CGSize(width: base.width + hPad * 2, height: base.height)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let base = super.sizeThatFits(size)
        return CGSize(width: base.width + hPad * 2, height: base.height)
    }
}

// MARK: - NativeAdCard (SwiftUI public surface)

/// Drop-in SwiftUI card for the Home nearby list.
///
/// Only renders content when a native ad is loaded AND ads are not suppressed.
/// Renders nothing otherwise — no reserved space, no empty gap.
///
/// Placement: use inside a SwiftUI List after about the 3rd stop card.
struct NativeAdCard: View {
    @EnvironmentObject private var m: AppModel
    @StateObject private var loader = NativeAdLoader()

    var body: some View {
        if !AdConfig.adsSuppressed, let ad = loader.nativeAd {
            adCard(ad)
                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        // No else — no placeholder, no empty gap.
    }

    @ViewBuilder
    private func adCard(_ ad: NativeAd) -> some View {
        let t = m.t
        NativeAdUIView(nativeAd: ad, theme: t)
            .frame(maxWidth: .infinity)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(t.line, lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                [ad.headline, ad.advertiser]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                + ". Advertisement."
            )
    }
}
