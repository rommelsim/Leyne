// SoftSettingsView — Leyne 2.0 Settings.
// Restyled for the 2.4.0 design language: grouped List cards, icon chips,
// chevron-trailing nav rows, SoftToggle for binary settings.
// Settings: manage alerts, appearance, 24h time, haptics, search radius,
// about. Notification permission is requested once at first launch (no
// in-app on/off toggle); the app ships English-only (no language picker).

import SwiftUI

/// Programmatic push targets for the settings nav rows.
private enum SettingsDest: Hashable { case manageAlerts, hiddenStops, about }

/// Where the "Buy me a coffee" row opens — the Stripe Payment Link for the
/// "Support Leyne" product (accepts PayNow + cards + Apple Pay, settles SGD to
/// bank). Leyne is ad-funded, not paywalled; this is an optional way to chip in.
private let kCoffeeURL = AppLinks.coffee

struct SoftSettingsView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @Environment(\.openURL) private var openURL

    let onTab: (SoftTab) -> Void

    private var t: Theme { m.t }

    // Sheet state
    @State private var showAppearanceSheet = false
    @State private var showRadiusSheet      = false
    // Push destinations — driven programmatically so nav rows use the SAME
    // trailing chevron as the sheet rows (NavigationLink's auto-chevron sat at
    // a different inset, misaligning the column).
    @State private var settingsDest: SettingsDest?

    var body: some View {
        List {
            // ── Section 1: primary rows ──────────────────────────────────
            Section {
                // Manage alerts → ManageAlertsView (the central alert list).
                // Notification permission itself is requested once at first
                // launch, so there is no separate in-app on/off toggle.
                Button {
                    settingsDest = .manageAlerts
                } label: {
                    rowLabel(
                        icon: "bell.badge",
                        title: "Manage alerts",
                        detail: m.alerts.isEmpty ? nil : "\(m.alerts.count)"
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(rowBG)

                // Appearance → OptionSheet (same as legacy SettingsView)
                Button {
                    showAppearanceSheet = true
                } label: {
                    rowLabel(
                        icon: "moon",
                        title: "Appearance",
                        detail: themeLabel(m.themeMode)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(rowBG)

                // Hidden stops → HiddenStopsView. Only surfaces once you've
                // hidden something from Nearby (long-press → Hide From Nearby).
                if !m.hiddenNearby.isEmpty {
                    Button {
                        settingsDest = .hiddenStops
                    } label: {
                        rowLabel(
                            icon: "eye.slash",
                            title: "Hidden stops",
                            detail: "\(m.hiddenNearby.count)"
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(rowBG)
                }

                // About → AboutView
                Button {
                    settingsDest = .about
                } label: {
                    rowLabel(icon: "info.circle", title: "About", detail: nil)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(rowBG)

                // Buy me a coffee → opens the donation link in the browser. An
                // optional, friendly way to support development; the app is
                // ad-funded, not paywalled. Monochrome row + external-link arrow
                // to match the design language (no loud branded button).
                Button {
                    fb.tap()
                    openURL(kCoffeeURL)
                } label: {
                    coffeeRow
                }
                .buttonStyle(.plain)
                .listRowBackground(rowBG)

            } header: {
                // Large in-content title rides the first section header
                // (the nav bar is hidden at each tab root).
                VStack(alignment: .leading, spacing: 12) {
                    Text("Settings")
                        .font(t.sans(32, weight: .bold))
                        .foregroundStyle(t.fg)
                        .textCase(nil)
                    sectionLabel("Preferences")
                }
                .padding(.bottom, 4)
            }

            // ── Section 2: time & haptics ─────────────────────────────────
            Section {
                toggleRow(
                    icon: "clock",
                    title: "24-hour time",
                    binding: $m.use24h
                )
                .listRowBackground(rowBG)

                toggleRow(
                    icon: "iphone.radiowaves.left.and.right",
                    title: "Haptics",
                    binding: Binding(
                        get: { m.haptic },
                        set: { m.haptic = $0; m.syncFeedback() }
                    )
                )
                .listRowBackground(rowBG)

                // Search radius → OptionSheet
                Button {
                    showRadiusSheet = true
                } label: {
                    rowLabel(
                        icon: "scope",
                        title: "Search radius",
                        detail: radiusLabel(m.searchRadiusM)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(rowBG)
            } header: {
                sectionLabel("Time & Feedback")
            } footer: {
                Text("Leyne v\(appVersion) · Data from LTA DataMall.")
                    .font(t.mono(10))
                    .foregroundStyle(t.faint)
                    .padding(.top, 8)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(t.bg.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .tint(t.accent)
        .navigationDestination(item: $settingsDest) { dest in
            switch dest {
            case .manageAlerts:
                ManageAlertsView().toolbar(.hidden, for: .tabBar)
            case .hiddenStops:
                HiddenStopsView().toolbar(.hidden, for: .tabBar)
            case .about:
                AboutView().toolbar(.hidden, for: .tabBar)
            }
        }
        // ── Sheets ────────────────────────────────────────────────────────
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
        .sheet(isPresented: $showRadiusSheet) {
            OptionSheet(
                title: "Search radius",
                options: [250, 500, 1000, 2000].map { r in
                    OptionRow(
                        label: radiusLabel(r),
                        sub: nil,
                        selected: m.searchRadiusM == r,
                        pick: { m.searchRadiusM = r }
                    )
                },
                footnote: "When you search a 6-digit postal code, bus stops within this distance of that address are shown."
            )
            .environmentObject(m)
        }
    }

    // MARK: - Primitives

    /// Tinted row background — t.surface via a view so it refreshes on theme change.
    private var rowBG: some View {
        t.surface
    }

    /// Uniform chevron for sheet-triggered rows (NavigationLink rows
    /// already get a chevron from the List for free).
    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(t.faint)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(t.sans(13, weight: .semibold))
            .tracking(0.3)
            .foregroundStyle(t.dim)
            .textCase(nil)
    }

    /// Icon + title + optional trailing detail. Used as the label for both
    /// NavigationLink rows and sheet-trigger Button rows. The caller is
    /// responsible for adding a chevron when no NavigationLink provides one.
    private func rowLabel(icon: String, title: String, detail: String?) -> some View {
        HStack(spacing: 10) {
            iconChip(icon)
            Text(title)
                .font(t.sans(15, weight: .medium))
                .foregroundStyle(t.fg)
            Spacer(minLength: 8)
            if let d = detail {
                Text(d)
                    .font(t.sans(13))
                    .foregroundStyle(t.dim)
                    .lineLimit(1)
            }
            // Chevron is a real trailing element (not an overlay) so it never
            // sits on top of the detail value like "System" / "English".
            chevron
        }
    }

    /// "Buy me a coffee" support row — icon chip, title + subtitle, and an
    /// external-link arrow (instead of a chevron) to signal it leaves the app.
    private var coffeeRow: some View {
        HStack(spacing: 10) {
            iconChip("cup.and.saucer.fill")
            VStack(alignment: .leading, spacing: 1) {
                Text("Buy me a coffee")
                    .font(t.sans(15, weight: .medium))
                    .foregroundStyle(t.fg)
                Text("Support Leyne's development")
                    .font(t.sans(12))
                    .foregroundStyle(t.dim)
            }
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.forward")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(t.faint)
        }
        .contentShape(Rectangle())
        .accessibilityLabel("Buy me a coffee. Opens in browser.")
    }

    private func toggleRow(icon: String, title: String,
                           binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            iconChip(icon)
            Text(title)
                .font(t.sans(15, weight: .medium))
                .foregroundStyle(t.fg)
            Spacer()
            SoftToggle(t: t, value: binding)
        }
    }

    private func iconChip(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(t.fg)
            .frame(width: 32, height: 32)
            .background(
                t.surfaceHi,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
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

    private func radiusLabel(_ m: Int) -> String {
        if m < 1000 { return "\(m) m" }
        let km = Double(m) / 1000
        if m % 1000 == 0 { return "\(Int(km)) km" }
        return String(format: "%.1f km", km)
    }
}
