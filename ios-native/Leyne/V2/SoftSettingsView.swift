// SoftSettingsView — Leyne 2.0 Settings: three grouped sections
// (Routines / Personalize / Feedback).

import SwiftUI

struct SoftSettingsView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback

    let onTab: (SoftTab) -> Void

    private var t: Theme { m.t }

    var body: some View {
        ZStack(alignment: .bottom) {
            t.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Settings")
                        .font(t.sans(30, weight: .semibold))
                        .foregroundStyle(t.fg)
                        .padding(.top, 8)

                    section("Routines") {
                        row(icon: "sunrise.fill", title: "Morning commute",
                            detail: "Not set", chevron: true)
                        row(icon: "moon.stars.fill", title: "Evening commute",
                            detail: "Not set", chevron: true)
                        row(icon: "plus", title: "Add a routine",
                            detail: nil, chevron: true)
                    }

                    section("Personalize") {
                        row(icon: "bell.fill", title: "Notifications",
                            detail: m.notificationsEnabled ? "On" : "Off", chevron: true)
                        Divider().background(t.line)
                        appearanceRow
                        Divider().background(t.line)
                        row(icon: "globe", title: "Language",
                            detail: m.localeCode.isEmpty ? "Device" : m.localeCode,
                            chevron: true)
                        Divider().background(t.line)
                        toggleRow(icon: "clock", title: "24-hour time",
                                  binding: $m.use24h)
                    }

                    section("Feedback") {
                        toggleRow(icon: "speaker.wave.2.fill", title: "Sound",
                                  binding: $m.sound)
                        Divider().background(t.line)
                        toggleRow(icon: "iphone.radiowaves.left.and.right",
                                  title: "Haptics",
                                  binding: $m.haptic)
                    }

                    Text("Leyne v\(appVersion) · beta · Data from LTA DataMall.")
                        .font(t.mono(10))
                        .foregroundStyle(t.faint)
                        .padding(.top, 8)

                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(t.sans(13, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(t.dim)
            VStack(spacing: 0) { content() }
                .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func row(icon: String, title: String, detail: String?,
                     chevron: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(t.fg)
                .frame(width: 32, height: 32)
                .background(t.surfaceHi, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(t.sans(14, weight: .medium))
                .foregroundStyle(t.fg)
            Spacer()
            if let d = detail {
                Text(d).font(t.sans(13)).foregroundStyle(t.dim)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(t.faint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func toggleRow(icon: String, title: String,
                           binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(t.fg)
                .frame(width: 32, height: 32)
                .background(t.surfaceHi, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(t.sans(14, weight: .medium))
                .foregroundStyle(t.fg)
            Spacer()
            SoftToggle(t: t, value: binding)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var appearanceRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(t.fg)
                .frame(width: 32, height: 32)
                .background(t.surfaceHi, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("Appearance")
                .font(t.sans(14, weight: .medium))
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
}
