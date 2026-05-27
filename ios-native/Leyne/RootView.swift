// Root composition — the App() equivalent from app.jsx.
// On a real device the phone IS the frame, so there's no IOSDevice chrome:
// the status bar / Dynamic Island / home indicator come from iOS itself.

import SwiftUI

struct RootView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback

    // The theme follows the iOS system appearance (no in-app toggle).
    @Environment(\.colorScheme) private var systemScheme

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
                    SettingsView()
                }
                Tab(value: AppTab.search, role: .search) {
                    Color.clear   // never shown — selection is intercepted
                }
            }
            .tint(t.accent)
            .bottomAdBanner(t)          // Home / Nearby / Settings

            // ── Detail ──────────────────────────────────────
            // If the tapped stop is one of several pinned stops, wrap
            // DetailView in a horizontal pager so the user can swipe to
            // sibling pinned stops without backing out. Singletons and
            // non-pinned stops (e.g. opened from search) bypass the pager.
            if let card = m.openCardLive() {
                let isPinned = m.pins.contains { $0.code == card.stopCode }
                Group {
                    if isPinned && m.pins.count > 1 {
                        DetailPager(
                            initialStopCode: card.stopCode,
                            initialBusNo: card.initialSelectedNo,
                            t: t, dark: m.isDark,
                            onClose: { m.openCard = nil }
                        )
                    } else {
                        DetailView(card: card, t: t, dark: m.isDark) { m.openCard = nil }
                    }
                }
                // iOS-native leading-edge swipe-back. Activates only within
                // the first 24 pt from the left, so DetailPager's TabView
                // keeps the rest of the screen for paging between stops.
                .modifier(EdgeSwipeBack { m.openCard = nil })
                .zIndex(30)
            }

            // ── Search sheet ────────────────────────────────
            if m.searchOpen {
                SearchSheetA(t: t, dark: m.isDark,
                             onClose: { m.searchOpen = false },
                             onPick: { m.openFromSearch(stopCode: $0) })
                // Don't apply .overlayAdBanner here — SearchSheetA folds
                // the AdBanner into its own bottom safeAreaInset. Stacking
                // two bottom safeAreaInsets collapses the ScrollView on
                // iOS 26 (the no-search-results bug).
                .transition(.opacity)
                .zIndex(45)
            }

            // ── Add sheet ───────────────────────────────────
            // Always mounted; it animates itself in/out off m.showAdd so the
            // dim can fade while the card springs up from the bottom.
            AddStopSheet(t: t, onClose: { m.showAdd = false }) { code, tracked in
                m.addPin(code: code, tracked: tracked)
            }
            .zIndex(40)

            // ── Onboarding ──────────────────────────────────
            // Mounted under the launch splash (zIndex 50 < 200) so when the
            // splash fades it reveals onboarding, never a flash of Home.
            if m.showOnboarding {
                OnboardingView(
                    t: t, dark: m.isDark,
                    onRequestLocation: { LocationManager.shared.requestPermission() },
                    onRequestNotifications: {
                        // Step 3's Continue button: fire the iOS notification
                        // permission prompt, then advance. setNotificationsEnabled
                        // handles request + schedule + denial snap-back.
                        Task { await m.setNotificationsEnabled(true) }
                    },
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

            // ── What's New ──────────────────────────────────
            // After onboarding, a returning user who just updated into a build
            // with release notes sees them once. zIndex 55 keeps the modal
            // above onboarding/tabs but under the launch splash.
            if !m.showOnboarding,
               let v = m.whatsNewVersion,
               let entry = kChangelog[v] {
                WhatsNewView(entry: entry, onDismiss: { m.markWhatsNewSeen() })
                    .environmentObject(m)
                    .transition(.opacity)
                    .zIndex(55)
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
        .animation(.easeInOut(duration: 0.3), value: m.showOnboarding)
        .animation(.easeInOut(duration: 0.3), value: m.whatsNewVersion)
        // Spring matches UIKit's UINavigationController push/pop curve more
        // closely than a flat ease — the snap on the way in and gentle
        // settle on the way out is what makes the detail screen read as a
        // native hierarchical drill-down rather than a fade.
        .animation(.spring(response: 0.42, dampingFraction: 0.86),
                   value: m.openCard)
        // Mirror the iOS appearance — system, or overridden by the user's
        // Settings ▸ Appearance pick — into the model so the custom Theme
        // (m.t / m.isDark) follows the resolved palette.
        .onChange(of: systemScheme, initial: true) { _, scheme in
            switch m.themeMode {
            case .system: m.isDark = (scheme == .dark)
            case .light:  m.isDark = false
            case .dark:   m.isDark = true
            }
        }
        .onChange(of: m.themeMode) { _, mode in
            switch mode {
            case .system: m.isDark = (systemScheme == .dark)
            case .light:  m.isDark = false
            case .dark:   m.isDark = true
            }
        }
        // First-run users gather ad consent from the onboarding "Ads" step.
        // Returning users (no onboarding) gather it here, once. Skippers fall
        // through to here on their next launch. AdConsent is idempotent.
        //
        // Also fire the notification permission prompt for users past
        // onboarding who have never been asked — covers the upgrade path
        // from a build that didn't have onboarding step 3 as a permission
        // ask. iOS shows the system dialog only once across the install,
        // so calling requestAuthorization on every launch is safe.
        .task {
            if !m.showOnboarding {
                await AdConsent.gatherThenStart()
                let status = await NotificationsManager.shared.currentStatus()
                if status == .notDetermined && m.notificationsEnabled {
                    await m.setNotificationsEnabled(true)
                }
            }
        }
        // Tap on an arrival / alight notification → drill into the bus.
        // LeyneAppDelegate posts the userInfo dictionary; we resolve
        // stopCode (directly for arrival, via activeAlight for alight)
        // and call AppModel.open which opens the relevant DetailView
        // with the bus pre-selected.
        .onReceive(NotificationCenter.default.publisher(
                    for: .leyneOpenStopFromNotification)) { notif in
            let info = notif.userInfo ?? [:]
            let kind = info["kind"] as? String ?? "arrival"
            let busNo = info["busNo"] as? String
            let stopCode: String?
            if kind == "alight" {
                stopCode = m.activeAlight?.stopCode
            } else {
                stopCode = info["stopCode"] as? String
            }
            guard let code = stopCode else { return }
            // Close any sheet that might be over the home, otherwise
            // open() lands behind it.
            m.searchOpen = false
            m.showAdd = false
            m.open(stopCode: code,
                   label: DataStore.shared.stopName(code),
                   busNo: busNo,
                   feedback: false)
        }
    }
}

// MARK: - EdgeSwipeBack
//
// iOS-style leading-edge swipe-back. Mirrors UIKit's
// `UIScreenEdgePanGestureRecognizer`: only claims gestures that start
// within the first ~24 pt from the left edge of the screen, then drags the
// content along with the finger and calls `onClose()` once the user has
// committed (by distance or velocity). This lets us reproduce the system
// pop gesture inside a SwiftUI overlay (DetailView / DetailPager) without
// refactoring the whole drill-down into a NavigationStack.
//
// Coexists with DetailPager's `.tabViewStyle(.page)`: page swipes start in
// the middle of the screen and don't match the edge predicate, so they
// still hand off to the TabView's own horizontal pager.
struct EdgeSwipeBack: ViewModifier {
    let onClose: () -> Void

    /// Width of the leading edge zone that captures the gesture, in points.
    /// 24 pt mirrors UIKit's default screen-edge recognizer trigger area.
    private let edgeWidth: CGFloat = 24

    /// How far the user must drag (rightward) before the screen pops on
    /// release. Anything below this snaps back into place.
    private let commitDistance: CGFloat = 80

    @State private var offset: CGFloat = 0
    @State private var trackingEdge = false

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    .onChanged { g in
                        if !trackingEdge {
                            // Claim the gesture only if it starts at the
                            // leading edge AND is moving rightward — guards
                            // against vertical scrolls and TabView page
                            // swipes that begin further inboard.
                            if g.startLocation.x < edgeWidth,
                               g.translation.width > 0 {
                                trackingEdge = true
                            }
                        }
                        if trackingEdge {
                            // Light resistance past the screen edge keeps
                            // the drag feeling tactile if the user pulls
                            // hard, but otherwise the content tracks 1:1.
                            offset = max(0, g.translation.width)
                        }
                    }
                    .onEnded { g in
                        defer { trackingEdge = false }
                        guard trackingEdge else { return }
                        let velocity = g.predictedEndTranslation.width
                            - g.translation.width
                        let pastThreshold = g.translation.width > commitDistance
                        let flickedOut = velocity > 120
                            && g.translation.width > 30
                        if pastThreshold || flickedOut {
                            // Reset offset before the parent transition
                            // tears the view down so the outgoing
                            // `move(edge: .trailing)` starts from the
                            // resting position, not from the dragged
                            // offset (which would otherwise be added on
                            // top of the transition's own translation).
                            offset = 0
                            onClose()
                        } else {
                            withAnimation(.spring(response: 0.30,
                                                  dampingFraction: 0.86)) {
                                offset = 0
                            }
                        }
                    }
            )
    }
}
