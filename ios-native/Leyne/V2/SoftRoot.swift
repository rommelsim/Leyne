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
    // One navigation stack per tab so a drill-down in Home doesn't follow
    // the user over to Nearby or Search. The native TabView preserves each
    // path across tab switches, matching iOS's standard tab behaviour.
    @State private var homeStack: [SoftRoute] = []
    @State private var nearbyStack: [SoftRoute] = []
    @State private var settingsStack: [SoftRoute] = []
    @State private var searchStack: [SoftRoute] = []
    @State private var mapHandoff: MapHandoffKind = .none

    private var t: Theme { m.t }

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            // Native iOS 26 TabView — the system renders the floating
            // Liquid Glass tab bar, handles selection switching, and
            // detaches the `.search` role into its own trailing circle
            // for free. Each tab owns a NavigationStack so child pushes
            // (Stop / Bus) keep the native slide + edge-swipe-back.
            TabView(selection: $tab) {
                Tab("Home", systemImage: "house.fill", value: SoftTab.home) {
                    navStack($homeStack) {
                        SoftHomeView(
                            onTab: { tab = $0 },
                            onOpenStop: { homeStack.append(.stop($0)) },
                            onOpenSearch: { tab = .search }
                        )
                    }
                }
                Tab("Nearby", systemImage: "location.fill", value: SoftTab.nearby) {
                    navStack($nearbyStack) {
                        SoftNearbyView(
                            onTab: { tab = $0 },
                            onOpenStop: { nearbyStack.append(.stop($0)) }
                        )
                    }
                }
                Tab("Settings", systemImage: "gearshape.fill", value: SoftTab.settings) {
                    navStack($settingsStack) {
                        SoftSettingsView(onTab: { tab = $0 })
                    }
                }
                Tab(value: SoftTab.search, role: .search) {
                    navStack($searchStack) {
                        SoftSearchView(
                            onClose: { tab = .home },
                            onOpenStop: { searchStack.append(.stop($0)) }
                        )
                    }
                }
            }
            .tint(t.accent)

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
        // Route them into the Home tab's stack, then clear so the same
        // trigger fires the next tap.
        .onChange(of: m.openCard) { _, card in
            guard let c = card else { return }
            tab = .home
            if let svc = c.initialSelectedNo, !svc.isEmpty {
                homeStack = [.stop(c.stopCode), .bus(stopCode: c.stopCode, svc: svc)]
            } else {
                homeStack = [.stop(c.stopCode)]
            }
            m.openCard = nil
        }
    }

    /// Wraps a tab's root in a NavigationStack bound to that tab's path,
    /// registering the shared route destinations. The ad-banner gutter is
    /// applied to the root only, so pushed detail views stay full-bleed.
    @ViewBuilder
    private func navStack<Root: View>(_ path: Binding<[SoftRoute]>,
                                      @ViewBuilder root: () -> Root) -> some View {
        NavigationStack(path: path) {
            root()
                .adBannerGutter()
                .softTopEdgeBlur()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: SoftRoute.self) { route in
                    routeView(route, path: path)
                        .softTopEdgeBlur()
                        .toolbar(.hidden, for: .navigationBar)
                        .toolbar(.hidden, for: .tabBar)
                        .enableSwipeBack()
                }
        }
    }

    @ViewBuilder
    private func routeView(_ route: SoftRoute,
                           path: Binding<[SoftRoute]>) -> some View {
        let pop = { if !path.wrappedValue.isEmpty { path.wrappedValue.removeLast() } }
        switch route {
        case .stop(let code):
            SoftStopView(stopCode: code,
                         onBack: pop,
                         onOpenBus: { svc in path.wrappedValue.append(.bus(stopCode: code, svc: svc)) },
                         onSeeAll: { path.wrappedValue.append(.allArrivals(code)) })
        case .bus(let code, let svc):
            SoftBusView(stopCode: code, svc: svc, onBack: pop)
        case .search:
            // Legacy route — Search is now a first-class tab. Kept so any
            // stale path still resolves; route taps into the same stack.
            SoftSearchView(
                onClose: pop,
                onOpenStop: { code in
                    pop()
                    path.wrappedValue.append(.stop(code))
                }
            )
        case .allArrivals(let code):
            // Light wrapper around SoftStopView with the truncated list
            // toggled off — full implementation in Phase 2 follow-up.
            SoftStopView(stopCode: code,
                         onBack: pop,
                         onOpenBus: { svc in path.wrappedValue.append(.bus(stopCode: code, svc: svc)) },
                         onSeeAll: {})
        }
    }
}
