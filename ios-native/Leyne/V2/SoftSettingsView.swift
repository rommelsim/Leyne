// SoftSettingsView — Glance Phase 5 redesign.
//
// Design (prototype screenSettings / screenAbout):
//   • Identity hero card — app-icon gradient tile + "Leyne" name + version sub
//   • Three grouped set-card sections (Preferences / Notifications / About)
//     each row uses a 30×30 coloured rounded tile (the prototype's .disclose__g /
//     g-* colours) and a trailing chevron or Toggle.
//   • Section-footer microcopy per prototype's .set-foot.
//   • "About Leyne" row navigates to a separate AboutView (prototype screenAbout).
//   • Real bindings: appearance picker (sheet), haptics toggle, hidden stops,
//     notification state read from m.notificationsEnabled.
//   • Presented as a sheet from the Now header gear (no Settings tab; Settings
//     is no longer a permanent tab per Phase 5 IA).
//
// Glyph tile colour palette — matched 1:1 to the prototype's CSS g-* classes:
//   g-green  #34C759   g-blue    #007AFF   g-indigo  #5856D6
//   g-red    #FF3B30   g-gray    #8E8E93   g-teal    #30B0C7
//   g-orange #FF9500   g-gold    #FFCC00   g-brown   #A2845E

import SwiftUI

// MARK: - Glyph tile colours (private to this file)

private extension Color {
    static let gtGreen  = Color(red: 0.204, green: 0.780, blue: 0.349)   // #34C759
    static let gtBlue   = Color(red: 0.000, green: 0.478, blue: 1.000)   // #007AFF
    static let gtIndigo = Color(red: 0.345, green: 0.337, blue: 0.839)   // #5856D6
    static let gtRed    = Color(red: 1.000, green: 0.231, blue: 0.188)   // #FF3B30
    static let gtGray   = Color(red: 0.557, green: 0.557, blue: 0.576)   // #8E8E93
    static let gtTeal   = Color(red: 0.188, green: 0.690, blue: 0.780)   // #30B0C7
    static let gtOrange = Color(red: 1.000, green: 0.584, blue: 0.000)   // #FF9500
    static let gtGold   = Color(red: 1.000, green: 0.800, blue: 0.000)   // #FFCC00
    static let gtBrown  = Color(red: 0.635, green: 0.518, blue: 0.369)   // #A2845E
}

// MARK: - SoftSettingsView

struct SoftSettingsView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @Environment(\.dismiss) private var dismiss

    // The callback is still declared for callers that supply it (SoftAlertsView),
    // but after the Phase 5 IA change SoftAlertsView passes { _ in }.
    let onTab: (SoftTab) -> Void

    @State private var showAppearanceSheet = false
    @State private var showAbout = false
    @State private var settingsDest: SettingsDest?

    private var t: Theme { m.t }

    private enum SettingsDest: Hashable { case hiddenStops }

    var body: some View {
        NavigationStack {
            List {
                // ── Identity hero ───────────────────────────────────────────
                Section {
                    identityCard
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                // ── Preferences ─────────────────────────────────────────────
                Section {
                    setRow(icon: "moon.fill",
                           color: .gtIndigo,
                           label: "Appearance",
                           value: themeLabel(m.themeMode),
                           hasChevron: true) {
                        fb.select()
                        showAppearanceSheet = true
                    }

                    toggleRow(icon: "iphone.radiowaves.left.and.right",
                              color: .gtOrange,
                              label: "Haptics",
                              binding: Binding(
                                  get: { m.haptic },
                                  set: { m.haptic = $0; m.syncFeedback() }
                              ))

                    if !m.hiddenNearby.isEmpty {
                        setRow(icon: "eye.slash.fill",
                               color: .gtGray,
                               label: "Hidden stops",
                               value: "\(m.hiddenNearby.count)",
                               hasChevron: true) {
                            fb.select()
                            settingsDest = .hiddenStops
                        }
                    }

                } header: {
                    footerLabel("PREFERENCES")
                } footer: {
                    Text("Choose how Leyne looks and feels.")
                        .font(t.sans(12)).foregroundStyle(t.ink3)
                }

                // ── Notifications ────────────────────────────────────────────
                Section {
                    toggleRow(icon: "bell.fill",
                              color: .gtRed,
                              label: "Arrival alerts",
                              binding: Binding(
                                  get: { m.notificationsEnabled },
                                  set: { newVal in
                                      if newVal { Task { await m.setNotificationsEnabled(true) } }
                                      else { m.notificationsEnabled = false }
                                  }
                              ))

                } header: {
                    footerLabel("NOTIFICATIONS")
                } footer: {
                    Text("Get a heads-up before your bus arrives so you never run for it.")
                        .font(t.sans(12)).foregroundStyle(t.ink3)
                }

                // ── About ────────────────────────────────────────────────────
                Section {
                    setRow(icon: "info.circle.fill",
                           color: .gtGray,
                           label: "About Leyne",
                           value: nil,
                           hasChevron: true) {
                        fb.select()
                        showAbout = true
                    }

                    setRow(icon: "star.fill",
                           color: .gtGold,
                           label: "Rate Leyne",
                           value: nil,
                           hasChevron: true) {
                        fb.select()
                        openRateApp()
                    }

                    setRow(icon: "cup.and.saucer.fill",
                           color: .gtBrown,
                           label: "Buy me a coffee",
                           value: nil,
                           hasChevron: true) {
                        fb.select()
                        openBuyMeCoffee()
                    }

                } header: {
                    footerLabel("ABOUT")
                } footer: {
                    Text("Transit data from LTA DataMall · Made in Singapore")
                        .font(t.sans(12)).foregroundStyle(t.ink3)
                        .multilineTextAlignment(.leading)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(t.bg.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(t.sans(15, weight: .semibold))
                        .foregroundStyle(t.brand)
                }
            }
            .tint(t.brand)
            // Push destinations
            .navigationDestination(item: $settingsDest) { dest in
                switch dest {
                case .hiddenStops:
                    HiddenStopsView().toolbar(.hidden, for: .tabBar)
                }
            }
        }
        // Sheets
        .sheet(isPresented: $showAppearanceSheet) {
            OptionSheet(
                title: "Appearance",
                options: LeyneThemeMode.allCases.map { mode in
                    OptionRow(
                        label: themeLabel(mode),
                        sub: mode == .system ? "Follow the device setting" : nil,
                        selected: m.themeMode == mode,
                        pick: { m.themeMode = mode }
                    )
                },
                footnote: nil
            )
            .environmentObject(m)
        }
        .sheet(isPresented: $showAbout) {
            GlanceAboutView()
                .environmentObject(m)
                .environmentObject(fb)
        }
    }

    // MARK: - Identity hero card (prototype .id-card / .id-icon)

    private var identityCard: some View {
        HStack(spacing: 14) {
            // App icon tile — gradient square matching prototype .id-icon
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [t.brand, t.brand.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "tram.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Leyne")
                    .font(t.rounded(20, .bold))
                    .foregroundStyle(t.fg)
                Text("Singapore bus & MRT · v\(appVersion)")
                    .font(t.sans(13, weight: .regular))
                    .foregroundStyle(t.ink3)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .glanceCard(fill: t.surface)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Leyne, version \(appVersion)")
    }

    // MARK: - Row types

    /// Tappable row with coloured glyph tile — prototype's .disclose / .set-row.
    private func setRow(icon: String,
                        color: Color,
                        label: String,
                        value: String?,
                        hasChevron: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                glyphTile(icon: icon, color: color)
                Text(label)
                    .font(t.sans(15, weight: .medium))
                    .foregroundStyle(t.fg)
                Spacer(minLength: 8)
                if let v = value {
                    Text(v)
                        .font(t.sans(13))
                        .foregroundStyle(t.ink3)
                        .lineLimit(1)
                }
                if hasChevron { disclosureChevron }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Toggle row — coloured glyph tile + native Toggle.
    private func toggleRow(icon: String,
                           color: Color,
                           label: String,
                           binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            HStack(spacing: 13) {
                glyphTile(icon: icon, color: color)
                Text(label)
                    .font(t.sans(15, weight: .medium))
                    .foregroundStyle(t.fg)
            }
        }
        .tint(t.go)
    }

    // MARK: - Atoms

    /// 30×30 coloured rounded glyph tile — prototype's .disclose__g.
    private func glyphTile(icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }

    private var disclosureChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(t.ink3)
    }

    private func footerLabel(_ text: String) -> some View {
        Text(text)
            .font(t.mono(11, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(t.ink3)
            .textCase(nil)
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private func themeLabel(_ mode: LeyneThemeMode) -> String {
        switch mode {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    private func openRateApp() {
        // Opens the App Store review composer — same as PromptCenter.confirmReview.
        if let url = URL(string: "https://apps.apple.com/app/id\(AppLinks.appStoreID)?action=write-review") {
            UIApplication.shared.open(url)
        }
    }

    private func openBuyMeCoffee() {
        // Leyne's live Stripe "Buy me a coffee" payment link — shared verbatim
        // with the Android build (lib/screens/v2/soft_settings_screen.dart
        // `_kCoffeeUrl`). The old GitHub support.html page was a dead placeholder.
        if let url = URL(string: "https://buy.stripe.com/6oU3cv5689oB3PI6R68so00") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - GlanceAboutView (prototype screenAbout)
// Named GlanceAboutView to avoid colliding with the legacy AboutView in
// SettingsView.swift (the old settings screen still references that one).

/// Standalone About screen — icon hero + version + links.
/// Presented as a sheet from the "About Leyne" Settings row.
struct GlanceAboutView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var t: Theme { m.t }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private static let privacyURL = URL(string: "https://rommelsim.github.io/Leyne/privacy.html")!
    private static let supportURL = URL(string: "https://rommelsim.github.io/Leyne/support.html")!

    var body: some View {
        NavigationStack {
            List {
                // ── Icon hero ──────────────────────────────────────────────
                Section {
                    iconHero
                        .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 16, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                // ── Links ──────────────────────────────────────────────────
                Section {
                    aboutRow(icon: "checkmark.seal.fill",
                             color: .gtGreen,
                             label: "Transit data from LTA DataMall",
                             value: nil) {
                        // informational — no action
                    }

                    aboutRow(icon: "star.fill",
                             color: .gtGold,
                             label: "Rate on the App Store",
                             value: nil) {
                        fb.select()
                        if let url = URL(string: "https://apps.apple.com/app/id\(AppLinks.appStoreID)?action=write-review") {
                            openURL(url)
                        }
                    }

                    aboutRow(icon: "envelope.fill",
                             color: .gtBlue,
                             label: "Send feedback",
                             value: nil) {
                        fb.select()
                        openURL(Self.supportURL)
                    }

                    aboutRow(icon: "lock.fill",
                             color: .gtGray,
                             label: "Privacy Policy",
                             value: nil) {
                        fb.select()
                        openURL(Self.privacyURL)
                    }
                }

                // ── Footer ─────────────────────────────────────────────────
                Section {
                    Color.clear.frame(height: 0)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } footer: {
                    Text("Made in Singapore")
                        .font(t.sans(12)).foregroundStyle(t.ink3)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 12)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(t.bg.ignoresSafeArea())
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(t.sans(15, weight: .semibold))
                        .foregroundStyle(t.brand)
                }
            }
        }
    }

    // MARK: - Icon hero (prototype screenAbout centred block)

    private var iconHero: some View {
        VStack(spacing: 12) {
            // Large icon tile — 84×84, cornerRadius 22 matching prototype
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [t.brand, t.brand.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "tram.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 84, height: 84)
            .accessibilityHidden(true)

            Text("Leyne")
                .font(t.rounded(22, .bold))
                .foregroundStyle(t.fg)

            Text("Version \(appVersion) (\(buildNumber))\nLive bus & MRT arrivals for Singapore.")
                .font(t.sans(13))
                .foregroundStyle(t.ink3)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Leyne, version \(appVersion), build \(buildNumber)")
    }

    // MARK: - Row

    private func aboutRow(icon: String,
                          color: Color,
                          label: String,
                          value: String?,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)
                Text(label)
                    .font(t.sans(15, weight: .medium))
                    .foregroundStyle(t.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 8)
                if let v = value {
                    Text(v).font(t.sans(13)).foregroundStyle(t.ink3).lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(t.ink3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
