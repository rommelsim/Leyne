// SoftRoot — Leyne 2.0 root composition. Wraps Home / Nearby / Settings
// in a NavigationStack so child views (Stop / Bus / Search) push with
// UIKit's native slide-from-trailing animation + edge-swipe back
// gesture. AppModel.openCard observation drives notification /
// Spotlight deep-link pushes onto the stack.

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

enum SoftRoute: Hashable {
    case stop(String)
    case bus(stopCode: String, svc: String)
    case search
    case allArrivals(String)
}

struct SoftRoot: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback

    @State private var tab: SoftTab = .home
    @State private var stack: [SoftRoute] = []
    @State private var mapHandoff: MapHandoffKind = .none

    private var t: Theme { m.t }

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            // Native push stack — NavigationStack handles the iOS
            // slide-from-trailing animation, parallax on the
            // underlying view, and the edge-swipe back gesture for free.
            NavigationStack(path: $stack) {
                tabContent
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(for: SoftRoute.self) { route in
                        routeView(route)
                            .toolbar(.hidden, for: .navigationBar)
                            .enableSwipeBack()
                    }
            }

            // Map handoff toast overlays the whole stack.
            VStack {
                MapHandoffToast(t: t, kind: $mapHandoff)
                    .padding(.top, 8)
                Spacer()
            }
            .zIndex(100)
            .allowsHitTesting(mapHandoff != .none)
        }
        // Notification / Spotlight deep links arrive via AppModel.openCard.
        // Convert each new request into a Stop or Bus route push, then
        // clear so the same trigger fires the next tap.
        .onChange(of: m.openCard) { _, card in
            guard let c = card else { return }
            if let svc = c.initialSelectedNo, !svc.isEmpty {
                stack = [.stop(c.stopCode), .bus(stopCode: c.stopCode, svc: svc)]
            } else {
                stack = [.stop(c.stopCode)]
            }
            m.openCard = nil
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .home:
            SoftHomeView(
                onTab: handleTabSelect,
                onOpenStop: { push(.stop($0)) },
                onOpenSearch: { push(.search) }
            )
        case .nearby:
            SoftNearbyView(
                onTab: handleTabSelect,
                onOpenStop: { push(.stop($0)) }
            )
        case .settings:
            SoftSettingsView(onTab: handleTabSelect)
        case .search:
            // Search is a route in the prototype; if the user tapped the
            // search tab, push it as a route and snap back to Home so the
            // tabbar reflects a base tab.
            SoftHomeView(
                onTab: handleTabSelect,
                onOpenStop: { push(.stop($0)) },
                onOpenSearch: { push(.search) }
            )
        }
    }

    @ViewBuilder
    private func routeView(_ route: SoftRoute) -> some View {
        switch route {
        case .stop(let code):
            SoftStopView(stopCode: code,
                         onBack: { pop() },
                         onOpenBus: { svc in push(.bus(stopCode: code, svc: svc)) },
                         onSeeAll: { push(.allArrivals(code)) })
        case .bus(let code, let svc):
            SoftBusView(stopCode: code, svc: svc, onBack: { pop() })
        case .search:
            SoftSearchView(
                onClose: { pop() },
                onOpenStop: { code in
                    pop()
                    push(.stop(code))
                }
            )
        case .allArrivals(let code):
            // Light wrapper around SoftStopView with the truncated list
            // toggled off — full implementation in Phase 2 follow-up.
            SoftStopView(stopCode: code,
                         onBack: { pop() },
                         onOpenBus: { svc in push(.bus(stopCode: code, svc: svc)) },
                         onSeeAll: {})
        }
    }

    private func handleTabSelect(_ next: SoftTab) {
        fb.select()
        if next == .search { push(.search); return }
        tab = next
        stack = []
    }

    private func push(_ route: SoftRoute) {
        stack.append(route)
    }
    private func pop() {
        if !stack.isEmpty { stack.removeLast() }
    }
}
