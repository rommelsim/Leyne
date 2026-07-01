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

    // Interactive edge swipe-back (the custom string-nav has no NavigationStack,
    // so we drive the pop ourselves): drag the current screen right, commit past
    // a third of the width.
    @State private var backDX: CGFloat = 0
    @State private var swiping = false

    private var t: RDTokens {
        RDTokens.resolve(dark: m.dark, seed: m.seed, premium: m.premium)
    }

    /// Directional push/pop: forward slides the incoming screen in from the
    /// trailing edge while the old one exits left; back reverses both, so a
    /// "back" visibly slides the screen back out to the right.
    private var pushTransition: AnyTransition {
        switch m.navDir {
        case .forward:
            return .asymmetric(insertion: .move(edge: .trailing),
                               removal: .move(edge: .leading))
        case .back:
            return .asymmetric(insertion: .move(edge: .leading),
                               removal: .move(edge: .trailing))
        }
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
                screenView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(m.screen)
                    .transition(swiping ? .identity : pushTransition)
                    .offset(x: backDX)
                    .simultaneousGesture(backSwipe)
                // The bottom nav exists only on the top-level screens. Animating
                // its slide-out/in (instead of letting it pop) keeps the content
                // frame from jumping when you push into / pop out of a detail
                // screen — the two motions stay in sync under one spring.
                if m.showNav {
                    RDBottomNav(m: m, t: t)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.36, dampingFraction: 0.92), value: m.screen)
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

    /// Left-edge drag → pop. `.simultaneousGesture` + an edge/`canHandleBack`
    /// guard so it never steals normal taps, scrolls or the segmented controls.
    private var backSwipe: some Gesture {
        let width = UIScreen.main.bounds.width
        return DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { v in
                guard m.canHandleBack, v.startLocation.x < 24, v.translation.width > 0 else { return }
                backDX = min(v.translation.width, width)
            }
            .onEnded { v in
                guard m.canHandleBack, v.startLocation.x < 24 else { backDX = 0; return }
                let commit = v.translation.width > width * 0.33
                    || v.predictedEndTranslation.width > width * 0.55
                if commit {
                    swiping = true
                    withAnimation(.easeOut(duration: 0.22)) {
                        backDX = width
                    } completion: {
                        m.handleBack()
                        backDX = 0
                        swiping = false
                    }
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { backDX = 0 }
                }
            }
    }

    @ViewBuilder private var screenView: some View {
        switch m.screen {
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
