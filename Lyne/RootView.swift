// Root composition — the App() equivalent from app.jsx.
// On a real device the phone IS the frame, so there's no IOSDevice chrome:
// the status bar / Dynamic Island / home indicator come from iOS itself.

import SwiftUI

struct RootView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback

    @State private var shakeOffset: CGFloat = 0

    private var t: Theme { m.t }

    /// Routes tab changes through the model so the select haptic still fires.
    private var tabSelection: Binding<AppTab> {
        Binding(get: { m.tab }, set: { m.setTab($0) })
    }

    var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()

            // ── Native iOS 26 Liquid Glass tab bar ──────────
            TabView(selection: tabSelection) {
                HomeView()
                    .tabItem { Label("Home", systemImage: "house.fill") }
                    .tag(AppTab.home)
                NearbyView()
                    .tabItem { Label("Nearby", systemImage: "smallcircle.filled.circle") }
                    .tag(AppTab.nearby)
                SettingsView(
                    onReplayLaunch: { m.launching = true },
                    onReplayOnboarding: { m.showOnboarding = true }
                )
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
            }
            .tint(t.accent)
            .offset(x: shakeOffset)

            // ── Search FAB (floats above the glass tab bar) ──
            if !m.launching && !m.showOnboarding && !m.showAdd
                && m.openCard == nil && !m.searchOpen && m.liveActivity == nil {
                SearchFAB(t: t) {
                    fb.select(); m.searchOpen = true
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 16).padding(.bottom, 92)
                .transition(.scale.combined(with: .opacity))
                .zIndex(25)
            }

            // ── Detail ──────────────────────────────────────
            if let card = m.openCardLive() {
                DetailView(card: card, t: t, dark: m.isDark) { m.openCard = nil }
                    .zIndex(30)
            }

            // ── Search sheet ────────────────────────────────
            if m.searchOpen {
                Group {
                    if m.searchStyle == "ambitious" {
                        SearchSheetB(t: t, dark: m.isDark,
                                     onClose: { m.searchOpen = false },
                                     onPick: { m.openFromSearch(stopCode: $0) })
                    } else {
                        SearchSheetA(t: t, dark: m.isDark,
                                     onClose: { m.searchOpen = false },
                                     onPick: { m.openFromSearch(stopCode: $0) })
                    }
                }
                .transition(.opacity)
                .zIndex(45)
            }

            // ── Add sheet ───────────────────────────────────
            if m.showAdd {
                AddStopSheet(t: t, onClose: { m.showAdd = false }) { code, tracked in
                    m.addPin(code: code, tracked: tracked)
                }
                .transition(.opacity)
                .zIndex(40)
            }

            // ── Onboarding ──────────────────────────────────
            if m.showOnboarding && !m.launching {
                OnboardingView(t: t, dark: m.isDark,
                                onRequestLocation: { LocationManager.shared.requestPermission() }) {
                    m.finishOnboarding()
                }
                .transition(.opacity)
                .zIndex(50)
            }

            // ── Live Activity takeover ──────────────────────
            if let act = m.liveActivity {
                LiveActivityLockScreen(activity: act) { m.liveActivity = nil }
                    .transition(.opacity)
                    .zIndex(90)
            }

            // ── Launch splash ───────────────────────────────
            if m.launching {
                LaunchScreenView { m.launching = false }
                    .zIndex(200)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: m.searchOpen)
        .animation(.easeInOut(duration: 0.3), value: m.showAdd)
        .animation(.easeInOut(duration: 0.3), value: m.showOnboarding)
        .animation(.easeInOut(duration: 0.3), value: m.liveActivity)
        .animation(.easeInOut(duration: 0.36), value: m.openCard)
        .onChange(of: fb.shake?.id) { _, _ in
            guard let kind = fb.shake?.kind, m.motion else { return }
            runShake(big: kind == .arrival)
        }
    }

    private func runShake(big: Bool) {
        let seq: [CGFloat] = big ? [-3, 3, -2, 2, -1, 0] : [-2, 2, -1, 0]
        for (i, dx) in seq.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * (big ? 0.09 : 0.08)) {
                withAnimation(.easeInOut(duration: big ? 0.09 : 0.08)) { shakeOffset = dx }
            }
        }
    }
}
