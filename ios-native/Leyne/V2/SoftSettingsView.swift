// SoftSettingsView — Leyne 2.0 Settings.
// Restyled for the 2.4.0 design language: grouped List cards, icon chips,
// chevron-trailing nav rows, SoftToggle for binary settings.
// All pre-existing settings (notifications, appearance, language, 24h time,
// haptics, search radius, about) are preserved and functional.

import SwiftUI

/// Programmatic push targets for the settings nav rows.
private enum SettingsDest: Hashable { case notifications, about }

struct SoftSettingsView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback

    let onTab: (SoftTab) -> Void

    private var t: Theme { m.t }

    // Sheet state
    @State private var showAppearanceSheet = false
    @State private var showLanguageSheet    = false
    @State private var showRadiusSheet      = false
    // Push destinations — driven programmatically so nav rows use the SAME
    // trailing chevron as the sheet rows (NavigationLink's auto-chevron sat at
    // a different inset, misaligning the column).
    @State private var settingsDest: SettingsDest?

    var body: some View {
        List {
            // ── Section 1: title + primary rows ──────────────────────────
            Section {
                // Alerts & Notifications → NotificationsView
                Button {
                    settingsDest = .notifications
                } label: {
                    rowLabel(
                        icon: "bell",
                        title: "Alerts & notifications",
                        detail: m.notificationsEnabled ? "On" : "Off"
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(rowBG)

                // My Favourites → switch to favourites tab
                Button {
                    onTab(.favourites)
                } label: {
                    rowLabel(icon: "star", title: "My favourites", detail: nil)
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

                // Language → OptionSheet (backed by m.localeCode)
                Button {
                    showLanguageSheet = true
                } label: {
                    rowLabel(
                        icon: "globe",
                        title: "Language",
                        detail: languageLabel(m.localeCode)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(rowBG)

                // About → AboutView
                Button {
                    settingsDest = .about
                } label: {
                    rowLabel(icon: "info.circle", title: "About", detail: nil)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(rowBG)

            } header: {
                // Large in-content title — SoftRoot hides the nav bar at each
                // tab root, so the page title rides the first section header.
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
            case .notifications:
                NotificationsView().toolbar(.hidden, for: .tabBar)
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
        .sheet(isPresented: $showLanguageSheet) {
            OptionSheet(
                title: "Language",
                options: ["", "en", "zh", "ms", "ta"].map { code in
                    OptionRow(
                        label: languageLabel(code),
                        sub: nil,
                        selected: (m.localeIdentifier ?? "") == (code == "" ? "" : code),
                        pick: { m.localeCode = code }
                    )
                },
                footnote: "App text is in English today — more languages are rolling out. Your choice still localises dates, pickers and system text."
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

    private func languageLabel(_ code: String) -> String {
        switch code {
        case "", "en": return "English"
        case "zh":     return "中文"
        case "ms":     return "Bahasa Melayu"
        case "ta":     return "தமிழ்"
        default:       return code.uppercased()
        }
    }

    private func radiusLabel(_ m: Int) -> String {
        if m < 1000 { return "\(m) m" }
        let km = Double(m) / 1000
        if m % 1000 == 0 { return "\(Int(km)) km" }
        return String(format: "%.1f km", km)
    }
}
