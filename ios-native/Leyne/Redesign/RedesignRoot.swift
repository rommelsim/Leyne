// Root of the SG Transit redesign (iOS). Owns the model, resolves the design
// tokens for the current theme/seed/premium choice, routes between the launch /
// onboarding / app phases, and lays the overlays above the app content.
//
// Self-contained: it manages its own light/dark via `preferredColorScheme` so
// the system status bar adapts, independent of the app's global theme.

import SwiftUI

/// Toggle for wiring the redesign into RootView. Set to `false` to restore the
/// production Soft UI.
enum RedesignFlags {
    static let enabled = true
}

struct RedesignRoot: View {
    @StateObject private var m = RedesignModel()

    // Offset-driven push/pop. Screens live in a ForEach keyed by their name, so a
    // pushed screen is created ONCE (stable identity from the moment it enters the
    // slide until it settles — no double onAppear / reload flicker), and both the
    // entering and leaving screens move in the direction `navDir` dictates
    // (forward = right→left, back = left→right).
    @State private var layers: [String] = ["map"]     // z-order; front animates in/out by offset
    @State private var xoff: [String: CGFloat] = ["map": 0]
    // Interactive edge swipe-back — drag the current screen right, commit past ⅓.
    @State private var backDX: CGFloat = 0
    @State private var swiping = false

    private var t: RDTokens {
        RDTokens.resolve(dark: m.dark, seed: m.seed, premium: m.premium)
    }

    var body: some View {
        ZStack {
            t.surface.ignoresSafeArea()
            content
        }
        .preferredColorScheme(t.dark ? .dark : .light)
        .animation(.easeOut(duration: 0.32), value: m.phase)
    }

    @ViewBuilder private var content: some View {
        switch m.phase {
        case .launch:
            RDLaunchScreen(t: t).transition(.opacity)
        case .onboarding:
            RDOnboarding(m: m, t: t).transition(.opacity)
        case .app:
            appShell.transition(.opacity)
        }
    }

    private var appShell: some View {
        ZStack {
            VStack(spacing: 0) {
                screensLayer
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                // The bottom nav exists only on the top-level screens; animating
                // its slide-out/in keeps the content frame from jumping.
                if m.showNav {
                    RDBottomNav(m: m, t: t)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.36, dampingFraction: 0.92), value: m.showNav)

            if m.searchOpen {
                RDSearchOverlay(m: m, t: t)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(40)
            }
            if m.luVisible {
                VStack { RDLiveUpdate(m: m, t: t); Spacer() }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(70)
            }
            if m.toast != nil {
                VStack { Spacer(); RDToast(m: m, t: t).padding(.bottom, 14) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(75)
            }
        }
        .animation(.easeOut(duration: 0.28), value: m.searchOpen)
        .animation(.easeOut(duration: 0.32), value: m.luVisible)
        .animation(.easeOut(duration: 0.3), value: m.toast != nil)
    }

    /// The two-screen slider. While settled, only `curScreen` shows (and owns the
    /// swipe gesture, with the pop destination revealed beneath during a drag).
    /// During a push/pop, the outgoing (`curScreen`) and incoming screens both
    /// slide in the direction dictated by `navDir`.
    private var screensLayer: some View {
        ZStack {
            if layers.count == 1, backDX > 0, let dest = m.stack.last, dest != layers.first {
                screen(dest).id("scr-\(dest)")   // revealed under the finger during a swipe
            }
            ForEach(layers, id: \.self) { s in
                screen(s).id("scr-\(s)")
                    .offset(x: (xoff[s] ?? 0) + (layers.count == 1 && s == m.screen ? backDX : 0))
            }
        }
        .simultaneousGesture(backSwipe)
        .onAppear { layers = [m.screen]; xoff = [m.screen: 0] }   // adopt deep-linked screen
        .onChange(of: m.screen) { old, new in
            guard !swiping, new != old else { return }
            let w = UIScreen.main.bounds.width
            let fwd = m.navDir == .forward
            xoff[new] = fwd ? w : -w                 // new enters off the trailing (fwd)/leading (back) edge
            xoff[old] = 0
            layers = fwd ? [old, new] : [new, old]   // forward: new on top; back: new revealed beneath
            withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
                xoff[new] = 0
                xoff[old] = fwd ? -w : w
            } completion: {
                layers = [new]; xoff = [new: 0]
            }
        }
    }

    /// Left-edge drag → pop. `.simultaneousGesture` + an edge/`canHandleBack`
    /// guard so it never steals normal taps, scrolls or the segmented controls.
    private var backSwipe: some Gesture {
        let width = UIScreen.main.bounds.width
        return DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { v in
                guard layers.count == 1, m.canHandleBack, v.startLocation.x < 24, v.translation.width > 0 else { return }
                backDX = min(v.translation.width, width)
            }
            .onEnded { v in
                guard layers.count == 1, m.canHandleBack, v.startLocation.x < 24 else { backDX = 0; return }
                let commit = v.translation.width > width * 0.33
                    || v.predictedEndTranslation.width > width * 0.55
                if commit {
                    swiping = true
                    withAnimation(.easeOut(duration: 0.22)) {
                        backDX = width
                    } completion: {
                        m.handleBack()
                        layers = [m.screen]; xoff = [m.screen: 0]; backDX = 0; swiping = false
                    }
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { backDX = 0 }
                }
            }
    }

    @ViewBuilder private func screen(_ s: String) -> some View {
        switch s {
        case "stop": RDStopScreen(m: m, t: t)
        case "station": RDStationScreen(m: m, t: t)
        case "route": RDRouteScreen(m: m, t: t)
        case "lines": RDLinesScreen(m: m, t: t)
        case "saved": RDSavedScreen(m: m, t: t)
        case "settings": RDSettingsScreen(m: m, t: t)
        case "switch": RDSwitchScreen(m: m, t: t)
        default: RDHomeScreen(m: m, t: t)
        }
    }
}
