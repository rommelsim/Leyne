// MrtMapView — zoomable + pannable LTA MRT system map viewer.
//
// Loads the "MRTSystemMap" asset from Assets.xcassets. If the image asset is
// empty (no art dropped in yet), falls back to a tidy placeholder with a link
// to the official LTA map page — so the button is immediately useful.
//
// Pinch-to-zoom and double-tap-to-zoom are handled by a UIScrollView-backed
// representable (ZoomableImageView) which gives us the full UIKit zoom stack:
// bouncing, momentum, content-inset safe areas, and hardware-accelerated
// texture rendering. SwiftUI's ScrollView+magnificationGesture combo doesn't
// replicate the native zoom feel reliably, so we bridge UIKit here.

import SwiftUI
import UIKit

// MARK: - Sheet wrapper

struct MrtMapView: View {
    @Environment(\.dismiss) private var dismiss

    private let mapImage = UIImage(named: "MRTSystemMap")

    var body: some View {
        NavigationStack {
            Group {
                if let image = mapImage {
                    ZoomableImageView(image: image)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    fallbackView
                }
            }
            .navigationTitle("MRT System Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Fallback (no art bundled yet)

    private var fallbackView: some View {
        VStack(spacing: 24) {
            Image(systemName: "map")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Map image not bundled yet")
                    .font(.headline)
                Text("Drop the official LTA MRT system map PNG into the\nMRTSystemMap asset in Assets.xcassets to enable the in-app zoom viewer.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                if let url = URL(string: "https://www.lta.gov.sg/content/ltagov/en/map/train.html") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open LTA system map", systemImage: "arrow.up.right.square")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - UIScrollView-backed zoomable image view

/// Wraps a custom `FitScrollView` UIScrollView subclass that fits the image
/// to the viewport on first layout, then allows pinch-to-zoom up to 5×.
/// Double-tap toggles between fit-scale and 2.5× centred on the tap point.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> FitScrollView {
        let scrollView = FitScrollView(image: image)
        scrollView.delegate = context.coordinator
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .systemBackground

        context.coordinator.scrollView = scrollView

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: FitScrollView, context: Context) {
        // Image is immutable after creation; nothing to update.
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: FitScrollView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? FitScrollView)?.imageView
        }

        /// Re-centre the image whenever it's smaller than the scroll bounds
        /// (standard UIScrollView centering trick — prevents top-left snap on zoom-out).
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let imageView = (scrollView as? FitScrollView)?.imageView else { return }
            let offsetX = max((scrollView.bounds.width  - scrollView.contentSize.width)  / 2, 0)
            let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) / 2, 0)
            imageView.center = CGPoint(
                x: scrollView.contentSize.width  / 2 + offsetX,
                y: scrollView.contentSize.height / 2 + offsetY
            )
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let sv = recognizer.view as? FitScrollView else { return }
            if sv.zoomScale > sv.minimumZoomScale {
                sv.setZoomScale(sv.minimumZoomScale, animated: true)
            } else {
                let tapPoint = recognizer.location(in: sv.imageView)
                let zoomScale: CGFloat = sv.minimumZoomScale * 2.5
                let w = sv.bounds.width  / zoomScale
                let h = sv.bounds.height / zoomScale
                sv.zoom(
                    to: CGRect(x: tapPoint.x - w / 2, y: tapPoint.y - h / 2, width: w, height: h),
                    animated: true
                )
            }
        }
    }
}

// MARK: - FitScrollView

/// A UIScrollView subclass that owns its image view and computes
/// the fit-to-bounds zoom scale in `layoutSubviews` (the earliest point
/// at which `bounds` reflects the real screen geometry).
final class FitScrollView: UIScrollView {
    let imageView: UIImageView
    private let nativeSize: CGSize
    /// True once we've applied the initial fit scale; prevents re-centering
    /// on every subsequent layout pass (e.g. keyboard, rotation).
    private var didApplyInitialZoom = false

    init(image: UIImage) {
        self.imageView = UIImageView(image: image)
        self.nativeSize = image.size
        super.init(frame: .zero)

        imageView.contentMode = .scaleAspectFill
        imageView.frame = CGRect(origin: .zero, size: nativeSize)
        addSubview(imageView)
        contentSize = nativeSize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard nativeSize.width > 0, nativeSize.height > 0,
              bounds.width > 0, bounds.height > 0 else { return }

        let fit = min(bounds.width / nativeSize.width,
                      bounds.height / nativeSize.height)
        // Update scale bounds every layout (handles rotation / size changes).
        minimumZoomScale = fit
        maximumZoomScale = fit * 5

        if !didApplyInitialZoom {
            didApplyInitialZoom = true
            // Set zoom scale without animation on first layout.
            zoomScale = fit
            // scrollViewDidZoom centres the image — call it manually once
            // since the delegate hasn't wired up during super.init.
            centreImageView()
        }
    }

    /// Centres the image view within the scroll bounds when it's smaller
    /// than the viewport (the standard inset-centering approach).
    fileprivate func centreImageView() {
        let offsetX = max((bounds.width  - contentSize.width)  / 2, 0)
        let offsetY = max((bounds.height - contentSize.height) / 2, 0)
        imageView.center = CGPoint(
            x: contentSize.width  / 2 + offsetX,
            y: contentSize.height / 2 + offsetY
        )
    }
}
