// Root composition — Leyne 2.0 "Soft" UI is now the default and only
// experience. Wraps `SoftRoot` with the launch splash, onboarding gate,
// What's New modal, theme listener, and notification / Spotlight deep
// link handler.

import SwiftUI

struct RootView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback

    @Environment(\.colorScheme) private var systemScheme

    private var t: Theme { m.t }

    var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()

            // ── Main Soft UI ────────────────────────────────
            SoftRoot()

            // ── Onboarding ──────────────────────────────────
            if m.showOnboarding {
                OnboardingView(
                    t: t, dark: m.isDark,
                    onRequestLocation: { LocationManager.shared.requestPermission() },
                    onRequestNotifications: {
                        Task { await m.setNotificationsEnabled(true) }
                    },
                    onRequestTracking: {
                        Task { await AdConsent.gatherThenStart(); m.finishOnboarding() }
                    }
                )
                .transition(.opacity)
                .zIndex(50)
            }

            // ── What's New ──────────────────────────────────
            if !m.showOnboarding,
               let v = m.whatsNewVersion,
               let entry = kChangelog[v] {
                WhatsNewView(entry: entry, onDismiss: { m.markWhatsNewSeen() })
                    .environmentObject(m)
                    .transition(.opacity)
                    .zIndex(55)
            }

            // ── Launch splash ───────────────────────────────
            if m.launching {
                LaunchScreenView { m.launching = false }
                    .zIndex(200)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: m.showOnboarding)
        .animation(.easeInOut(duration: 0.3), value: m.whatsNewVersion)
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
        .task {
            if !m.showOnboarding {
                await AdConsent.gatherThenStart()
                let status = await NotificationsManager.shared.currentStatus()
                if status == .notDetermined && m.notificationsEnabled {
                    await m.setNotificationsEnabled(true)
                }
            }
        }
        // Notification / Spotlight deep links surface as `m.openCard`; SoftRoot
        // observes this in turn and pushes Stop or Bus accordingly. We keep
        // the existing AppModel.open(...) plumbing so notification + Spotlight
        // handlers don't need to know about the new view hierarchy.
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
            m.open(stopCode: code,
                   label: DataStore.shared.stopName(code),
                   busNo: busNo,
                   feedback: false)
        }
    }
}
