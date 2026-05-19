// Root composition — the App() equivalent from app.jsx.
// On a real device the phone IS the frame, so there's no IOSDevice chrome:
// the status bar / Dynamic Island / home indicator come from iOS itself.

import SwiftUI

struct RootView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback

    @State private var shakeOffset: CGFloat = 0

    private var t: Theme { m.t }

    /// Tab changes route through the model (keeps the select haptic). The
    /// search tab is an action: it opens the search sheet and the content
    /// selection stays on the current tab.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { m.tab },
            set: { next in
                if next == .search {
                    fb.select()
                    m.searchOpen = true
                } else {
                    m.setTab(next)
                }
            })
    }

    var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()

            // ── Native iOS 26 Liquid Glass tab bar ──────────
            // Home/Nearby/Settings sit in the main glass pill; Search uses the
            // .search role so iOS 26 renders it as its own detached pill.
            TabView(selection: tabSelection) {
                Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                    HomeView()
                }
                Tab("Nearby", systemImage: "smallcircle.filled.circle", value: AppTab.nearby) {
                    NearbyView()
                }
                Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                    SettingsView(
                        onReplayLaunch: { m.launching = true },
                        onReplayOnboarding: { m.showOnboarding = true }
                    )
                }
                Tab(value: AppTab.search, role: .search) {
                    Color.clear   // never shown — selection is intercepted
                }
            }
            .tint(t.accent)
            .bottomAdBanner(t)          // Home / Nearby / Settings
            .offset(x: shakeOffset)

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
                .overlayAdBanner(t)         // Search overlay (above the TabView)
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
            // Mounted under the launch splash (zIndex 50 < 200) so when the
            // splash fades it reveals onboarding, never a flash of Home.
            if m.showOnboarding {
                OnboardingView(
                    t: t, dark: m.isDark,
                    onRequestLocation: { LocationManager.shared.requestPermission() },
                    onRequestTracking: {
                        // Priming screen is up; now run Google UMP + Apple ATT,
                        // start the Ads SDK, then dismiss onboarding.
                        Task { await AdConsent.gatherThenStart(); m.finishOnboarding() }
                    }
                ) {
                    m.finishOnboarding()        // Skip — consent deferred to next launch
                }
                .transition(.opacity)
                .zIndex(50)
            }

            // Live Activity is now a real iOS Live Activity (ActivityKit) —
            // it lives on the Lock Screen / Dynamic Island, not in-app.

            // ── Launch splash ───────────────────────────────
            if m.launching {
                LaunchScreenView { m.launching = false }
                    .zIndex(200)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: m.searchOpen)
        .animation(.easeInOut(duration: 0.3), value: m.showAdd)
        .animation(.easeInOut(duration: 0.3), value: m.showOnboarding)
        .animation(.easeInOut(duration: 0.36), value: m.openCard)
        .onChange(of: fb.shake?.id) { _, _ in
            guard let kind = fb.shake?.kind, m.motion else { return }
            runShake(big: kind == .arrival)
        }
        // First-run users gather ad consent from the onboarding "Ads" step.
        // Returning users (no onboarding) gather it here, once. Skippers fall
        // through to here on their next launch. AdConsent is idempotent.
        .task {
            if !m.showOnboarding { await AdConsent.gatherThenStart() }
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
