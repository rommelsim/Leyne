// SoftRoot — Leyne 2.0 root composition. Owns the simple stack-based
// nav (Home / Nearby / Settings tabs; Search / Stop / Bus pushed).
// Observes `AppModel.openCard` so notification / Spotlight deep links
// surface as route pushes onto this stack.

import SwiftUI

enum SoftRoute: Equatable {
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
        ZStack {
            t.bg.ignoresSafeArea()

            // Base tab content
            tabContent
                .zIndex(0)

            // Pushed routes
            ForEach(Array(stack.enumerated()), id: \.offset) { idx, route in
                routeView(route)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(Double(10 + idx))
            }

            // Map handoff toast (overlay)
            VStack {
                MapHandoffToast(t: t, kind: $mapHandoff)
                    .padding(.top, 8)
                Spacer()
            }
            .zIndex(100)
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: stack)
        .animation(.easeInOut(duration: 0.18), value: tab)
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
