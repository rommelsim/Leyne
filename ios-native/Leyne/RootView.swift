// Root composition — Leyne 2.0 "Soft" UI is now the default and only
// experience. Wraps `SoftRoot` with the onboarding gate, theme listener,
// and notification / Spotlight deep link handler. (The auto-shown What's
// New modal and the animated launch splash were both removed 2026-07-13;
// release notes remain reachable from Settings.)

import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) var m: AppModel
    @EnvironmentObject var fb: Feedback
    @EnvironmentObject var prompts: PromptCenter

    @Environment(\.colorScheme) private var systemScheme

    private var t: Theme { m.t }

    var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()

            // ── Main UI — WhereSia "departure board" design ──
            // (design-remake branch: the WhereSia layer replaces the previous
            // "Soft" UI as the app root; swap back to SoftRoot() to revert.)
            WSRoot()

            // ── First-run permissions ───────────────────────
            // The onboarding walkthrough was removed (owner, 2026-07-11): on a
            // first launch we simply fire the three OS permission prompts one
            // after another over the live app, then mark onboarding done. No
            // custom screens. See `runFirstRunPermissions`.

            // (Launch splash animation removed — owner, 2026-07-13. The app
            // goes straight from the OS launch screen to WSRoot.)
        }
        .animation(.easeInOut(duration: 0.3), value: m.showOnboarding)
        // Contextual App Store review prompt — paced by PromptCenter.
        .sheet(item: $prompts.active) { prompt in
            PromptCard(prompt: prompt)
                .environment(m)
                .environmentObject(fb)
        }
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
        // First-run permission sequence — replaces the onboarding walkthrough.
        // Fires location → notifications → ATT/UMP consent one at a time (each
        // awaits the user's answer), then finishes onboarding.
        .task(id: m.showOnboarding) {
            guard m.showOnboarding else { return }
            _ = await LocationManager.shared.requestPermissionAwaiting()
            await m.setNotificationsEnabled(true)
            // ATT/UMP only matters when ads are on; gatherThenStart also starts
            // the ad SDK once consent is resolved.
            if AdConfig.adsEnabled { await AdConsent.gatherThenStart() }
            m.finishOnboarding()
        }
        .task {
            if !m.showOnboarding {
                await AdConsent.gatherThenStart()
                // Preload an App Open ad, then present it for this cold launch
                // once it's ready (returning users only; never the first launch,
                // and gated behind the splash + 4h cap inside the manager). Run
                // detached so its short poll doesn't hold up the rest of launch.
                AppOpenAdManager.shared.preload()
                Task { await AppOpenAdManager.shared.showOnColdLaunch(model: m) }
                // Preload an Interstitial so one is ready when the user first
                // backs out of a Stop / Bus detail.
                InterstitialAdManager.shared.preload()
                let status = await NotificationsManager.shared.currentStatus()
                if status == .notDetermined && m.notificationsEnabled {
                    await m.setNotificationsEnabled(true)
                }
                // Count this launch toward the contextual review / support
                // prompts (all pacing + caps live in PromptCenter).
                PromptCenter.shared.noteAppOpen()
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
        // Widget + Live Activity deep links (lyne:// scheme, registered in
        // LeyneInfo.plist). The Home Screen widget opens lyne://stop/<code>;
        // the Live Activity (lock screen / Dynamic Island) opens
        // lyne://bus/<stopCode>/<busNo>. Both route through the same
        // AppModel.open(...) plumbing as a notification tap, so SoftRoot pushes
        // Stop or Bus accordingly. Without this handler the registered scheme
        // had no receiver — a widget / Live Activity tap only foregrounded the
        // app instead of opening the stop or bus.
        .onOpenURL { url in
            // Widget / Live Activity tap → opening a stop/bus; skip App Open.
            AppOpenAdManager.shared.suppressNextPresentation()
            guard url.scheme == "lyne", let host = url.host else { return }
            let parts = url.pathComponents.filter { $0 != "/" }
            let ds = DataStore.shared
            // Ignore deep links to a stop code that isn't a real stop (e.g. a
            // sample/placeholder code from a widget). Stay optimistic while the
            // stop DB is still loading (empty) so genuine cold-launch links work.
            let code = parts.first ?? ""
            let knownStop = ds.stopByCode.isEmpty || ds.stopByCode[code] != nil
            switch host {
            case "bus" where parts.count >= 2 && knownStop:
                m.open(stopCode: parts[0],
                       label: ds.stopName(parts[0]),
                       busNo: parts[1],
                       feedback: false)
            case "stop" where !parts.isEmpty && knownStop:
                m.open(stopCode: parts[0],
                       label: ds.stopName(parts[0]),
                       busNo: nil,
                       feedback: false)
            default:
                break
            }
        }
    }
}
