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
//   NativeAdCard    — SwiftUI card: sized to match SoftNearbyStopCard (fixed
//                     height 86 pt). Styled monochrome with t.surface / t.fg /
//                     t.dim tokens to sit as a sibling of SoftNearbyStopCard.
//                     Only rendered when an ad is loaded and consent is ready;
//                     callers see EmptyView otherwise (no empty gap).
//
// AdMob policy requirements satisfied:
//   • "Ad" attribution label — always visible, inline before headline.
//   • headlineView outlet wired — required.
//   • bodyView, iconView, callToActionView, advertiserView wired when present.
//   • NativeAdView is the root interaction target — taps route correctly.
//   • No custom click-handling; interaction delegate left to SDK defaults.
//
// Layout (stack-based, robust to any creative subset):
//
//   ┌─────────────────────────────────────────────────────────┐
//   │ 14pt │ [iconTile 42×42] 10pt │ [text VStack] │ [CTA] 14pt│
//   └─────────────────────────────────────────────────────────┘
//
//   Text VStack (leading-aligned):
//     Row 0: [Ad pill] [headline (1–2 lines)]
//     Row 1: optional secondary — body or advertiser (1 line, dim)
//
//   CTA pill: right-trailing, vertically centred; hidden when absent —
//   the text column expands to fill via .setContentHuggingPriority(.low).
//   "Ad" badge: inline pill at the start of the headline row — never
//   floats top-right, so it never collides with the AdChoices overlay.

import SwiftUI
import GoogleMobileAds
import os

private let nativeLog = Logger(subsystem: "com.leyne.Leyne", category: "NativeAd")

// MARK: - Retry constants (mirrors BannerHostView strategy)

private let kNativeRetryDelays: [TimeInterval] = [5, 10, 30]

// MARK: - Card height

/// Fixed card height that matches a standard SoftNearbyStopCard row.
///
/// SoftNearbyStopCard layout: .padding(14) all sides + 42 pt tile.
/// The non-highlighted card's text column (name + subtitle + compactMeta)
/// measures ~58 pt at default Dynamic Type, so the card naturally rests at
/// 14 + 58 + 14 ≈ 86 pt. We pin the ad card to this value so it is never
/// shorter (a thin strip) or taller (breaking the list rhythm).
private let kAdCardHeight: CGFloat = 86

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
/// Layout uses UIStackView throughout — no hand-rolled anchor math that
/// breaks when optional views are hidden. The card is pinned to a fixed
/// height (kAdCardHeight) via the SwiftUI .frame modifier on the caller,
/// so the UIKit layer never needs to compute its own height.
///
/// Stack structure:
///   outerH (horizontal, 10pt spacing, 14pt insets):
///     iconTile (42×42, fixed)
///     textV (vertical, 3pt spacing, compressionResistance low):
///       badgeRow (horizontal, 6pt spacing):
///         adBadge pill (fixed, hugs tightly)
///         headlineLabel (1–2 lines)
///       secondaryLabel (1 line, hidden when nil — UIStackView collapses it)
///     ctaButton (fixed, hugs tightly; hidden when nil — stack collapses it)
///
/// AdChoices overlay (rendered by the SDK) lands in its default top-right
/// corner. The "Ad" badge is inline in the text column, so there is zero
/// chance of collision.
struct NativeAdUIView: UIViewRepresentable {
    let nativeAd: NativeAd
    let theme: Theme

    func makeUIView(context: Context) -> NativeAdView {
        let adView = NativeAdView()
        adView.backgroundColor = .clear

        // ── Create all subviews ───────────────────────────────────────────

        // Icon tile (always shown — either the creative icon or a placeholder)
        let iconTile = UIView()
        iconTile.layer.cornerRadius = 12
        iconTile.layer.cornerCurve = .continuous
        iconTile.clipsToBounds = true

        let iconImageView = UIImageView()
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.clipsToBounds = true
        adView.iconView = iconImageView

        let placeholderImageView = UIImageView()
        placeholderImageView.translatesAutoresizingMaskIntoConstraints = false
        placeholderImageView.contentMode = .center

        iconTile.addSubview(iconImageView)
        iconTile.addSubview(placeholderImageView)
        NSLayoutConstraint.activate([
            iconImageView.topAnchor.constraint(equalTo: iconTile.topAnchor),
            iconImageView.leadingAnchor.constraint(equalTo: iconTile.leadingAnchor),
            iconImageView.trailingAnchor.constraint(equalTo: iconTile.trailingAnchor),
            iconImageView.bottomAnchor.constraint(equalTo: iconTile.bottomAnchor),
            placeholderImageView.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            placeholderImageView.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
        ])

        // "Ad" attribution badge — inline pill, always visible (AdMob policy §3)
        let adBadge = PaddedLabel()
        adBadge.text = "Ad"
        adBadge.textAlignment = .center
        adBadge.layer.cornerRadius = 5
        adBadge.layer.cornerCurve = .continuous
        adBadge.clipsToBounds = true
        adBadge.adjustsFontForContentSizeCategory = true
        adBadge.setContentHuggingPriority(.required, for: .horizontal)
        adBadge.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Headline (required outlet)
        let headlineLabel = UILabel()
        headlineLabel.numberOfLines = 2
        headlineLabel.adjustsFontForContentSizeCategory = true
        headlineLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        adView.headlineView = headlineLabel

        // Badge + headline in a horizontal stack
        let badgeRow = UIStackView(arrangedSubviews: [adBadge, headlineLabel])
        badgeRow.axis = .horizontal
        badgeRow.spacing = 6
        badgeRow.alignment = .center

        // Secondary label: body if present, else advertiser, else hidden.
        // UIStackView automatically collapses hidden arranged subviews —
        // this is why we use a stack instead of hand-rolled constraints.
        let secondaryLabel = UILabel()
        secondaryLabel.numberOfLines = 1
        secondaryLabel.adjustsFontForContentSizeCategory = true
        secondaryLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // Wire to bodyView so AdMob attributes impression correctly.
        // (advertiserView is set to nil; we display whichever string exists.)
        adView.bodyView = secondaryLabel
        adView.advertiserView = secondaryLabel   // same view — both wired

        // Text column
        let textV = UIStackView(arrangedSubviews: [badgeRow, secondaryLabel])
        textV.axis = .vertical
        textV.spacing = 3
        textV.alignment = .leading
        textV.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textV.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // CTA button (hugs content; hidden when absent — stack collapses it)
        var ctaConfig = UIButton.Configuration.filled()
        ctaConfig.cornerStyle = .capsule
        ctaConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attr in
            var a = attr
            a.font = UIFontMetrics.default.scaledFont(
                for: UIFont.systemFont(ofSize: 13, weight: .semibold))
            return a
        }
        ctaConfig.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 14, bottom: 9, trailing: 14)
        let ctaButton = UIButton(configuration: ctaConfig)
        ctaButton.isUserInteractionEnabled = false   // NativeAdView owns the tap
        ctaButton.setContentHuggingPriority(.required, for: .horizontal)
        ctaButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        adView.callToActionView = ctaButton

        // Outer horizontal stack — the whole card row
        let outerH = UIStackView(arrangedSubviews: [iconTile, textV, ctaButton])
        outerH.axis = .horizontal
        outerH.spacing = 10
        outerH.alignment = .center
        outerH.translatesAutoresizingMaskIntoConstraints = false

        // Fix the icon tile size (stack doesn't know about fixed-size tiles)
        NSLayoutConstraint.activate([
            iconTile.widthAnchor.constraint(equalToConstant: 42),
            iconTile.heightAnchor.constraint(equalToConstant: 42),
        ])

        // Add the "Ad" badge fixed height
        adBadge.heightAnchor.constraint(equalToConstant: 18).isActive = true

        adView.addSubview(outerH)

        let pad: CGFloat = 14
        NSLayoutConstraint.activate([
            outerH.topAnchor.constraint(equalTo: adView.topAnchor, constant: pad),
            outerH.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: pad),
            outerH.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -pad),
            outerH.bottomAnchor.constraint(equalTo: adView.bottomAnchor, constant: -pad),
        ])

        // ── Populate asset values (must happen before .nativeAd is set) ──
        applyAssets(
            nativeAd: nativeAd,
            iconTile: iconTile,
            iconImageView: iconImageView,
            placeholderImageView: placeholderImageView,
            adBadge: adBadge,
            headlineLabel: headlineLabel,
            secondaryLabel: secondaryLabel,
            ctaButton: ctaButton
        )

        // Register outlets — MUST happen after all outlet properties are set.
        adView.nativeAd = nativeAd

        return adView
    }

    func updateUIView(_ uiView: NativeAdView, context: Context) {
        // Single-use; the loader never replaces an ad mid-session.
    }

    // MARK: - Asset population

    /// Populate creative content and style every subview.
    /// Called once in makeUIView, before nativeAd is assigned to the outlet.
    private func applyAssets(
        nativeAd: NativeAd,
        iconTile: UIView,
        iconImageView: UIImageView,
        placeholderImageView: UIImageView,
        adBadge: PaddedLabel,
        headlineLabel: UILabel,
        secondaryLabel: UILabel,
        ctaButton: UIButton
    ) {
        let fg        = UIColor(theme.fg)
        let dim       = UIColor(theme.dim)
        let surfaceHi = UIColor(theme.surfaceHi)
        let accent    = UIColor(theme.accent)
        let onAccent  = UIColor(theme.onAccent)

        // Ad badge
        adBadge.font = UIFontMetrics.default.scaledFont(
            for: UIFont.systemFont(ofSize: 10, weight: .semibold))
        adBadge.textColor = dim
        adBadge.backgroundColor = surfaceHi

        // Icon tile — always present; fills with creative icon or placeholder
        if let icon = nativeAd.icon?.image {
            iconImageView.image = icon
            iconTile.backgroundColor = .clear
            placeholderImageView.isHidden = true
        } else {
            iconImageView.image = nil
            iconTile.backgroundColor = surfaceHi
            placeholderImageView.isHidden = false
            placeholderImageView.tintColor = dim
            let cfg = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
            placeholderImageView.image = UIImage(systemName: "tag.fill", withConfiguration: cfg)
        }

        // Headline
        headlineLabel.text = nativeAd.headline
        headlineLabel.font = UIFontMetrics.default.scaledFont(
            for: UIFont.systemFont(ofSize: 14, weight: .semibold))
        headlineLabel.textColor = fg

        // Secondary line — body wins; fall back to advertiser; hide when neither
        if let body = nativeAd.body, !body.isEmpty {
            secondaryLabel.text = body
            secondaryLabel.isHidden = false
        } else if let advertiser = nativeAd.advertiser, !advertiser.isEmpty {
            secondaryLabel.text = advertiser
            secondaryLabel.isHidden = false
        } else {
            secondaryLabel.text = nil
            secondaryLabel.isHidden = true
        }
        secondaryLabel.font = UIFontMetrics.default.scaledFont(
            for: UIFont.systemFont(ofSize: 12, weight: .regular))
        secondaryLabel.textColor = dim

        // CTA button — hidden when absent; UIStackView collapses it automatically
        if let cta = nativeAd.callToAction, !cta.isEmpty {
            var config = ctaButton.configuration ?? UIButton.Configuration.filled()
            config.title = cta
            config.baseForegroundColor = onAccent
            config.baseBackgroundColor = accent
            ctaButton.configuration = config
            ctaButton.isHidden = false
        } else {
            ctaButton.isHidden = true
        }
    }

    // MARK: - Font helper (kept for internal clarity — identical to applyAssets calls)

    private func scaledFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        UIFontMetrics.default.scaledFont(for: UIFont.systemFont(ofSize: size, weight: weight))
    }
}

// MARK: - PaddedLabel

/// UILabel with fixed horizontal padding — used for the "Ad" attribution badge.
/// UILabel has no built-in content inset; we override drawText(in:) and
/// intrinsicContentSize to add symmetric horizontal padding (6 pt each side).
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
/// Fixed height (kAdCardHeight = 86 pt) matches SoftNearbyStopCard's
/// typical row so the card sits flush in the list rhythm.
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
            .frame(height: kAdCardHeight)   // fixed height — no collapse, no bloat
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
