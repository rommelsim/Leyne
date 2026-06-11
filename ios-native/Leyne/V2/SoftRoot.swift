// SoftRoot — Leyne single-screen composition. Home (Nearby) is the ONLY
// full-screen view; everything else — Search, Saved, Settings, Stop, Bus —
// presents as a card (sheet) over the home canvas, navigating internally
// with native pushes (Search → Stop → Bus all inside one card). The bottom
// tab bar is gone: Search is a field at the top of Home, Saved/Settings are
// buttons beside it. AppModel.openCard observation drives notification /
// Spotlight / Live Activity deep-link cards.

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
    /// `fullRoute` is true when opened from a bus search (no anchor stop
    /// context), so the route timeline shows the whole route from origin.
    case bus(stopCode: String, svc: String, fullRoute: Bool = false)
    case search
}

/// Which card is presented over the home canvas. One card at a time; deeper
/// drill-downs (Search → Stop → Bus) push inside the card's own stack.
enum RootCard: Identifiable, Hashable {
    case search
    case saved
    case settings
    case stop(String)
    case bus(stopCode: String, svc: String, fullRoute: Bool = false)

    var id: String {
        switch self {
        case .search:               return "search"
        case .saved:                return "saved"
        case .settings:             return "settings"
        case .stop(let c):          return "stop-\(c)"
        case .bus(let c, let s, _): return "bus-\(c)-\(s)"
        }
    }

    /// Cards whose dismissal counts as "backing out of a detail" for the
    /// interstitial manager.
    var isDetail: Bool {
        switch self {
        case .stop, .bus: return true
        default:          return false
        }
    }
}

struct SoftRoot: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback

    /// The presented card + the navigation path INSIDE it.
    @State private var card: RootCard?
    @State private var cardPath: [SoftRoute] = []
    /// Stop cards open at .medium (Maps-style peek, home visible behind) and
    /// promote to .large when a bus is pushed; everything else is .large.
    @State private var cardDetent: PresentationDetent = .large
    /// What was on screen when the sheet dismissed (sheet's onDismiss runs
    /// after `card` is already nil).
    @State private var lastPresented: RootCard?
    @State private var mapHandoff: MapHandoffKind = .none

    private var t: Theme { m.t }

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            // Home — the single full-screen canvas. Keeps a bare
            // NavigationStack only for its in-place pushes (the alerts list).
            NavigationStack {
                SoftHomeView(
                    onTab: { open(tab: $0) },
                    onOpenStop: { present(.stop($0)) },
                    onOpenSearch: { present(.search) },
                    onOpenBus: { code, svc in
                        present(.bus(stopCode: code, svc: svc))
                    },
                    onOpenSaved: { present(.saved) },
                    onOpenSettings: { present(.settings) }
                )
                .adBannerGutter()
                .softTopEdgeBlur()
                .toolbar(.hidden, for: .navigationBar)
            }

            // Map handoff toast overlays everything.
            VStack {
                MapHandoffToast(t: t, kind: $mapHandoff)
                    .padding(.top, 8)
                Spacer()
            }
            .zIndex(100)
            .allowsHitTesting(mapHandoff != .none)
        }
        .sheet(item: $card, onDismiss: cardDismissed) { c in
            cardContent(c)
        }
        // Interstitial ad: a Bus exit inside a card shows up as the card's
        // path shrinking; observing the path means the back button AND the
        // edge-swipe-back both trigger the attempt. Card dismissal itself is
        // handled in `cardDismissed`. The manager's guards decide whether one
        // actually shows.
        .onChange(of: cardPath) { old, new in
            handleStackPop(old, new)
            // Bus needs the full card — promote a medium Stop peek when
            // drilling into a bus.
            if pathHasBus(new) { cardDetent = .large }
        }
        // Notification / Spotlight / Live Activity deep links arrive via
        // AppModel.openCard. Present them as a Stop card (with the Bus pushed
        // when the link names a service), then clear so the same trigger
        // fires the next tap. `initial: true` is essential for COLD launches
        // (tapping a Live Activity from a suspended/killed app): onOpenURL
        // sets openCard before this observer attaches, so without the initial
        // pass the deep link is silently dropped and nothing navigates.
        .onChange(of: m.openCard, initial: true) { _, oc in
            guard let oc else { return }
            // Programmatic present — tell the interstitial manager so a
            // subsequent dismiss isn't read as a user back-exit (they tapped
            // a notification, not "back").
            InterstitialAdManager.shared.suppressNextExit()
            if let svc = oc.initialSelectedNo, !svc.isEmpty {
                present(.stop(oc.stopCode),
                        path: [.bus(stopCode: oc.stopCode, svc: svc)])
            } else {
                present(.stop(oc.stopCode))
            }
            m.openCard = nil
        }
    }

    // MARK: - Card presentation

    /// Presents (or swaps to) a card, resetting its internal path. Stop cards
    /// peek at .medium; anything else (or a pre-loaded deep path) is .large.
    private func present(_ c: RootCard, path: [SoftRoute] = []) {
        cardPath = path
        if case .stop = c, path.isEmpty {
            cardDetent = .medium
        } else {
            cardDetent = .large
        }
        lastPresented = c
        card = c
    }

    /// Maps legacy SoftTab requests (Settings' / Home's onTab links) onto
    /// the card model.
    private func open(tab: SoftTab) {
        switch tab {
        case .search:          present(.search)
        case .favourites:      present(.saved)
        case .settings:        present(.settings)
        case .home, .nearby:   card = nil
        }
    }

    private func cardDismissed() {
        // Backing out of a Stop/Bus card — or a card whose stack had drilled
        // into one — is the ad moment the tabbed app keyed off nav pops.
        let sawDetail = (lastPresented?.isDetail ?? false)
        cardPath = []
        lastPresented = nil
        if sawDetail {
            InterstitialAdManager.shared.maybeShowOnExit(model: m)
        }
    }

    /// Fires an interstitial attempt when the card's path shrinks and the
    /// removed top was a Stop or Bus detail — i.e. the user backed out of a
    /// detail inside the card. Growing paths (drill-in) are ignored.
    private func handleStackPop(_ old: [SoftRoute], _ new: [SoftRoute]) {
        guard new.count < old.count, let removed = old.last else { return }
        switch removed {
        case .stop, .bus:
            InterstitialAdManager.shared.maybeShowOnExit(model: m)
        case .search:
            break
        }
    }

    private func pathHasBus(_ p: [SoftRoute]) -> Bool {
        p.contains {
            if case .bus = $0 { return true }
            return false
        }
    }

    // MARK: - Card content

    @ViewBuilder
    private func cardContent(_ c: RootCard) -> some View {
        NavigationStack(path: $cardPath) {
            cardRoot(c)
                .softTopEdgeBlur()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: SoftRoute.self) { route in
                    routeDestination(route)
                }
        }
        .presentationDetents(detents(for: c), selection: $cardDetent)
        .presentationDragIndicator(.visible)
        .presentationBackground(t.bg)
    }

    private func detents(for c: RootCard) -> Set<PresentationDetent> {
        if case .stop = c { return [.medium, .large] }
        return [.large]
    }

    /// The root view of each card. Dismissal closures clear `card`; deeper
    /// navigation pushes onto the card's own path.
    @ViewBuilder
    private func cardRoot(_ c: RootCard) -> some View {
        switch c {
        case .search:
            SoftSearchView(
                onClose: { card = nil },
                onOpenStop: { cardPath.append(.stop($0)) },
                onOpenBus: { stopCode, svcNo in
                    cardPath.append(.bus(stopCode: stopCode, svc: svcNo,
                                         fullRoute: true))
                }
            )
            .adBannerGutter()
        case .saved:
            SoftFavouritesView(
                onOpenStop: { cardPath.append(.stop($0)) },
                onOpenBus: { code, svc in
                    cardPath.append(.bus(stopCode: code, svc: svc))
                },
                onOpenSearch: { present(.search) }
            )
            .adBannerGutter()
        case .settings:
            SoftSettingsView(onTab: { open(tab: $0) })
                .adBannerGutter()
        case .stop(let code):
            // No banner gutter — the Stop screen carries its own inline MREC.
            SoftStopView(stopCode: code,
                         onBack: { card = nil },
                         onOpenBus: { svc in
                             cardPath.append(.bus(stopCode: code, svc: svc))
                         })
        case .bus(let code, let svc, let fullRoute):
            SoftBusView(stopCode: code, svc: svc, fullRoute: fullRoute,
                        onBack: { card = nil })
                .adBannerGutter()
        }
    }

    /// A destination pushed INSIDE a card. The bottom ad-banner gutter is
    /// applied to every destination EXCEPT `.stop`, which carries its own
    /// inline 300×250 MREC instead — mounting both would double up ads on
    /// one screen.
    @ViewBuilder
    private func routeDestination(_ route: SoftRoute) -> some View {
        let pop = { if !cardPath.isEmpty { cardPath.removeLast() } }
        let content = Group {
            switch route {
            case .stop(let code):
                SoftStopView(stopCode: code,
                             onBack: pop,
                             onOpenBus: { svc in
                                 cardPath.append(.bus(stopCode: code, svc: svc))
                             })
            case .bus(let code, let svc, let fullRoute):
                SoftBusView(stopCode: code, svc: svc, fullRoute: fullRoute,
                            onBack: pop)
            case .search:
                // Legacy route — Search is a card now. Kept so any stale path
                // still resolves; taps route into the same card stack.
                SoftSearchView(
                    onClose: pop,
                    onOpenStop: { cardPath.append(.stop($0)) },
                    onOpenBus: { stopCode, svcNo in
                        cardPath.append(.bus(stopCode: stopCode, svc: svcNo,
                                             fullRoute: true))
                    }
                )
            }
        }
        .softTopEdgeBlur()
        .toolbar(.hidden, for: .navigationBar)
        .enableSwipeBack()

        if case .stop = route {
            content
        } else {
            content.adBannerGutter()
        }
    }
}
