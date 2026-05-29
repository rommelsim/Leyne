// SoftSettingsView — Leyne 2.0 Settings. Native inset-grouped List so we
// get correct navigation rows, tap targets, and a11y for free, while the
// warm Soft theme is preserved via row-background tinting + a hidden
// scroll-content background. Cells keep the Soft icon-chip styling.

import SwiftUI

struct SoftSettingsView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback

    let onTab: (SoftTab) -> Void

    private var t: Theme { m.t }

    var body: some View {
        List {
            Section {
                // Real destination — ports the legacy NotificationsView,
                // which already drives setNotificationsEnabled / authorization
                // and shows the denied-permission banner.
                NavigationLink {
                    NotificationsView()
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    rowLabel(icon: "bell.fill", title: "Notifications",
                             detail: m.notificationsEnabled ? "On" : "Off")
                }
                .listRowBackground(t.surface)

                appearanceRow
                    .listRowBackground(t.surface)

                toggleRow(icon: "clock", title: "24-hour time",
                          binding: $m.use24h)
                    .listRowBackground(t.surface)
            } header: {
                // In-content title — SoftRoot hides the nav bar at each tab
                // root, so the large Soft title rides the first section header.
                VStack(alignment: .leading, spacing: 12) {
                    Text("Settings")
                        .font(t.sans(30, weight: .semibold))
                        .foregroundStyle(t.fg)
                        .textCase(nil)
                    sectionHeader("Personalize")
                }
                .padding(.bottom, 4)
            }

            Section {
                toggleRow(icon: "speaker.wave.2.fill", title: "Sound",
                          binding: $m.sound)
                    .listRowBackground(t.surface)
                toggleRow(icon: "iphone.radiowaves.left.and.right",
                          title: "Haptics", binding: $m.haptic)
                    .listRowBackground(t.surface)
            } header: {
                sectionHeader("Feedback")
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
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(t.sans(13, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(t.dim)
    }

    /// Shared label content for tappable rows. Native List supplies the
    /// chevron for NavigationLink rows — we never draw one by hand, so no
    /// dead chevrons can appear.
    private func rowLabel(icon: String, title: String,
                          detail: String?) -> some View {
        HStack(spacing: 12) {
            iconChip(icon)
            Text(title)
                .font(t.sans(15, weight: .medium))
                .foregroundStyle(t.fg)
            Spacer()
            if let d = detail {
                Text(d).font(t.sans(13)).foregroundStyle(t.dim)
            }
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

    private var appearanceRow: some View {
        HStack(spacing: 12) {
            iconChip("moon.fill")
            Text("Appearance")
                .font(t.sans(15, weight: .medium))
                .foregroundStyle(t.fg)
            Spacer()
            Picker("", selection: $m.themeMode) {
                Text("Auto").tag(LeyneThemeMode.system)
                Text("Light").tag(LeyneThemeMode.light)
                Text("Dark").tag(LeyneThemeMode.dark)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 180)
        }
    }

    private func iconChip(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(t.fg)
            .frame(width: 32, height: 32)
            .background(t.surfaceHi, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
}
