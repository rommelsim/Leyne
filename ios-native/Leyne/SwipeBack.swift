// Edge-swipe back for NavigationStack screens that hide the system nav bar.
// (Extracted from the retired V2/SoftRoot.swift — WhereSia's wsHeaderBar
// depends on it.)

import SwiftUI
import UIKit

/// SwiftUI's NavigationStack drops the interactive pop gesture when the
/// nav bar is hidden via `.toolbar(.hidden, …)`. Setting the gesture
/// recogniser's delegate to `nil` reinstates it. Apply once at the root
/// of each pushed destination.
private struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }
    func updateUIViewController(_ uiViewController: UIViewController,
                                context: Context) {
        DispatchQueue.main.async {
            guard let nav = uiViewController.navigationController else { return }
            nav.interactivePopGestureRecognizer?.delegate = nil
            nav.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}

private struct EnableSwipeBack: ViewModifier {
    func body(content: Content) -> some View {
        content.background(SwipeBackEnabler().frame(width: 0, height: 0))
    }
}

extension View {
    /// Re-enables the edge-swipe-from-left back gesture for SwiftUI
    /// NavigationStack views that hide their toolbar.
    func enableSwipeBack() -> some View { modifier(EnableSwipeBack()) }
}
