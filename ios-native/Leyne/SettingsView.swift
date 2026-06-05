// Settings + the views it pushes to (About, Notifications, What's New).
// Ported from Flutter v2.0 lib/screens/settings_screen.dart, about_screen.dart,
// notifications_screen.dart, whats_new_screen.dart. Kept in a single file
// to avoid Xcode project surgery; logical separation by MARK sections.

import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @EnvironmentObject var m: AppModel

    @State private var showAppearanceSheet = false
    @State private var showLanguageSheet = false
    @State private var showRadiusSheet = false
    @State private var pushAbout = false
    @State private var pushNotifications = false
    /// Tracks whether the "Settings" header has scrolled off-screen so the
    /// StickyCompactBar can fade in — same pattern as Home and Nearby.
    @State private var collapsed = false

    private var t: Theme { m.t }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header.background(GeometryReader { geo in
                            Color.clear.preference(key: TitleOffsetKey.self,
                                value: geo.frame(in: .named("scroll")).minY)
                        })
                        personalizeSection
                        feedbackSection
                        aboutCard
                    }
                    .padding(.bottom, 32)
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(TitleOffsetKey.self) { y in
                    let c = y < -12
                    if c != collapsed { collapsed = c }
                }

                // Same compact bar Home and Nearby use, so all three tabs
                // share one collapsing-title vocabulary. No trailing item
                // (Settings has nothing to surface in the bar slot).
                StickyCompactBar(t: t, title: "Settings",
                    trailing: AnyView(EmptyView()),
                    visible: collapsed)
            }
            .background(t.bg.ignoresSafeArea())
            .navigationDestination(isPresented: $pushAbout) { AboutView() }
            .navigationDestination(isPresented: $pushNotifications) { NotificationsView() }
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
    }

    // MARK: header

    private var header: some View {
        Text("Settings")
            .font(t.sans(28, weight: .semibold))
            .foregroundStyle(t.fg)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
    }

    // MARK: sections

    private var personalizeSection: some View {
        section(label: "PERSONALIZE") {
            navRow(icon: "bell", title: "Notifications",
                   value: m.notificationsEnabled ? "Arrival alerts on" : "Off",
                   action: { pushNotifications = true })
            divider
            navRow(icon: "moon", title: "Appearance",
                   value: themeLabel(m.themeMode),
                   action: { showAppearanceSheet = true })
            divider
            navRow(icon: "globe", title: "Language",
                   value: languageLabel(m.localeCode),
                   action: { showLanguageSheet = true })
            divider
            navRow(icon: "scope", title: "Search radius",
                   value: radiusLabel(m.searchRadiusM),
                   action: { showRadiusSheet = true })
            divider
            toggleRow(icon: "clock", title: "24-hour time",
                      value: m.use24h ? "On" : "Off",
                      binding: Binding(get: { m.use24h }, set: { m.use24h = $0 }))
        }
    }

    private var feedbackSection: some View {
        section(label: "FEEDBACK") {
            toggleRow(icon: "iphone.radiowaves.left.and.right", title: "Haptics",
                      value: m.haptic ? "On" : "Off",
                      binding: Binding(get: { m.haptic },
                                       set: { m.haptic = $0; m.syncFeedback() }))
        }
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ABOUT")
                .font(t.mono(10, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(t.dim)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 10)
            Button { pushAbout = true } label: {
                HStack(spacing: 14) {
                    Image("AppIcon")
                        .resizable()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(t.accent)
                                .opacity(0.0)  // placeholder if image asset isn't usable
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Leyne").font(t.sans(15, weight: .semibold))
                            .foregroundStyle(t.fg)
                        Text(versionLabel)
                            .font(t.mono(11))
                            .foregroundStyle(t.dim)
                            .tracking(0.4)
                    }
                    Spacer()
                    Text("What's new").font(t.sans(12)).foregroundStyle(t.accent)
                    Image(systemName: "chevron.right").font(.system(size: 12))
                        .foregroundStyle(t.faint)
                }
                .padding(.horizontal, 14).padding(.vertical, 14)
                .background(t.glassSurface())
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(t.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)

            Text("Data from LTA DataMall.\nNot affiliated with any operator.")
                .font(t.mono(11)).foregroundStyle(t.faint)
                .tracking(0.4)
                .lineSpacing(4)
                .padding(.horizontal, 26)
                .padding(.top, 12)
        }
    }

    // MARK: row primitives

    @ViewBuilder
    private func section<C: View>(label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(t.mono(10, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(t.dim)
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
            VStack(spacing: 0) { content() }
                .background(t.glassSurface())
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(t.line, lineWidth: 1))
                .padding(.horizontal, 20)
        }
        .padding(.top, 20)
    }

    private var divider: some View {
        Rectangle().fill(t.line).frame(height: 1)
    }

    private func navRow(icon: String, title: String, value: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 18))
                    .foregroundStyle(t.dim).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(t.sans(14, weight: .medium)).foregroundStyle(t.fg)
                    if !value.isEmpty {
                        Text(value).font(t.mono(11)).foregroundStyle(t.dim).tracking(0.4)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12))
                    .foregroundStyle(t.faint)
            }
            .padding(.horizontal, 14).padding(.vertical, 14)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func toggleRow(icon: String, title: String, value: String,
                           binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 18))
                .foregroundStyle(t.dim).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(t.sans(14, weight: .medium)).foregroundStyle(t.fg)
                if !value.isEmpty {
                    Text(value).font(t.mono(11)).foregroundStyle(t.dim).tracking(0.4)
                }
            }
            Spacer()
            Toggle("", isOn: binding).labelsHidden().tint(t.accent)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    // MARK: helpers

    private var versionLabel: String {
        let v = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
        let b = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"
        return "v\(v) (\(b))"
    }

    private func themeLabel(_ m: LeyneThemeMode) -> String {
        switch m {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    private func languageLabel(_ code: String) -> String {
        switch code {
        case "", "en": return "English"
        case "zh": return "中文"
        case "ms": return "Bahasa Melayu"
        case "ta": return "தமிழ்"
        default: return code.uppercased()
        }
    }

    private func radiusLabel(_ m: Int) -> String {
        if m < 1000 { return "\(m) m" }
        let km = Double(m) / 1000
        if m % 1000 == 0 { return "\(Int(km)) km" }
        return String(format: "%.1f km", km)
    }
}

// MARK: - OptionSheet

struct OptionRow: Identifiable {
    let id = UUID()
    let label: String
    let sub: String?
    let selected: Bool
    let pick: () -> Void
}

struct OptionSheet: View {
    let title: String
    let options: [OptionRow]
    let footnote: String?
    @EnvironmentObject var m: AppModel
    @Environment(\.dismiss) private var dismiss

    private var t: Theme { m.t }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(t.sans(15, weight: .semibold))
                .foregroundStyle(t.fg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 12)

            ForEach(options) { o in
                Button {
                    o.pick()
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(o.label)
                                .font(t.sans(15, weight: o.selected ? .semibold : .regular))
                                .foregroundStyle(t.fg)
                            if let s = o.sub {
                                Text(s).font(t.mono(11)).foregroundStyle(t.dim)
                            }
                        }
                        Spacer()
                        if o.selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(t.accent)
                        }
                    }
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }

            if let f = footnote {
                Text(f).font(t.mono(11)).foregroundStyle(t.faint)
                    .lineSpacing(3).tracking(0.3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 4)
            }
            Spacer(minLength: 0)
        }
        .background(t.surface)
        .presentationDetents([.medium, .fraction(0.45)])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - NotificationsView

struct NotificationsView: View {
    @EnvironmentObject var m: AppModel
    private var t: Theme { m.t }

    /// Local mirror of `m.notificationsEnabled` so the Toggle can flip
    /// instantly and we control the snap-back when permission is denied.
    @State private var toggle = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Notifications")
                    .font(t.sans(28, weight: .semibold))
                    .foregroundStyle(t.fg)
                    .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 16)

                Toggle(isOn: Binding(get: { toggle },
                                     set: { newValue in
                                         toggle = newValue
                                         Task {
                                             await m.setNotificationsEnabled(newValue)
                                             // Sync the local toggle back if
                                             // permission was denied or the
                                             // model otherwise refused.
                                             toggle = m.notificationsEnabled
                                         }
                                     })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Arrival alerts").font(t.sans(14, weight: .medium))
                        Text("A notification fires ~1 minute before a tracked bus arrives — on the Lock Screen, even when Leyne is closed.")
                            .font(t.mono(11)).foregroundStyle(t.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(t.accent)
                .padding(.horizontal, 14).padding(.vertical, 14)
                .background(t.glassSurface())
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(t.line, lineWidth: 1))
                .padding(.horizontal, 20)

                // Denied-permission warning + Open Settings shortcut. Shown
                // only when iOS has explicitly denied — `.notDetermined`
                // means the user hasn't been asked yet, which the toggle
                // handles inline.
                if m.notificationAuth == .denied {
                    deniedBanner.padding(.horizontal, 20).padding(.top, 14)
                }

                Text("Times-sensitive alerts pierce Focus modes by default on iOS 15+ — adjust per-app under iOS Settings ▸ Notifications ▸ Leyne.")
                    .font(t.mono(11)).foregroundStyle(t.faint)
                    .tracking(0.3).lineSpacing(3)
                    .padding(.horizontal, 26).padding(.top, 14)
            }
            .padding(.bottom, 24)
        }
        .background(t.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await m.refreshNotificationAuth()
            toggle = m.notificationsEnabled
        }
    }

    private var deniedBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(t.warn)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text("Notifications blocked in iOS Settings")
                    .font(t.sans(13, weight: .semibold))
                    .foregroundStyle(t.fg)
                Text("Leyne needs notification permission to alert you when a bus is nearly here. Re-enable it from the iOS Settings app.")
                    .font(t.mono(11)).foregroundStyle(t.dim)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open iOS Settings")
                        .font(t.sans(12, weight: .semibold))
                        .foregroundStyle(t.bg)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(t.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(t.warnBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(t.warn.opacity(0.4), lineWidth: 1))
    }
}

// MARK: - AboutView

struct AboutView: View {
    @EnvironmentObject var m: AppModel
    private var t: Theme { m.t }

    private static let thisBuild = [
        "Refreshed look — warm dark theme, mint accent, mono numerics throughout.",
        "Home leads with a hero arrival card and leave-now timing.",
        "Compact saved-route rows fit more stops on screen.",
        "Nearby shows service numbers inline and a quick map toggle.",
        "Search opens onto recents and pinned stops instead of a blank page.",
        "Bus detail: live journey timeline with a clear BOARD HERE marker.",
        "Crowding meter now fills as the bus gets fuller — no more guessing.",
        "Bus detail auto-refreshes — the marker moves, no pull needed.",
        "Live Activities and Home Screen widget — back from v1.0.",
    ]

    private static let comingSoon = [
        "Refresh interval control — trade battery for freshness.",
        "Data saver — lighter polling and map tiles on cellular.",
        "QR scan — point at a stop pole to jump straight to it.",
        "More languages across every screen.",
    ]

    private static let privacyURL =
        URL(string: "https://rommelsim.github.io/Leyne/privacy.html")!
    private static let supportURL =
        URL(string: "https://rommelsim.github.io/Leyne/support.html")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                identity
                listSection(label: "This build", items: Self.thisBuild,
                            icon: "checkmark", color: t.accent)
                listSection(label: "Coming soon", items: Self.comingSoon,
                            icon: "arrow.right", color: t.dim)
                legalSection
                Text("Data from LTA DataMall.\nNot affiliated with any operator.")
                    .font(t.mono(11)).foregroundStyle(t.faint)
                    .lineSpacing(4).tracking(0.4)
                    .padding(.horizontal, 26).padding(.top, 24)
            }
            .padding(.bottom, 40)
        }
        .background(t.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("About").font(t.sans(20, weight: .semibold))
            }
        }
    }

    private var identity: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 16)
                .fill(t.accent)
                .frame(width: 60, height: 60)
                .overlay(
                    Image(systemName: "bus.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(t.contrastFg)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text("Leyne").font(t.sans(22, weight: .semibold)).foregroundStyle(t.fg)
                Text(versionLabel).font(t.mono(12)).foregroundStyle(t.dim).tracking(0.4)
            }
            Spacer()
            Text("Made in SG").font(t.sans(12)).foregroundStyle(t.dim)
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 8)
    }

    private func listSection(label: String, items: [String], icon: String,
                              color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(t.mono(10, weight: .medium)).tracking(1.2)
                .foregroundStyle(t.dim)
                .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 10)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, line in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(color)
                            .padding(.top, 2)
                        Text(line).font(t.sans(13)).foregroundStyle(t.fg)
                            .lineSpacing(2)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(t.glassSurface())
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(t.line, lineWidth: 1))
            .padding(.horizontal, 20)
        }
    }

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LEGAL & SUPPORT")
                .font(t.mono(10, weight: .medium)).tracking(1.2)
                .foregroundStyle(t.dim)
                .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 10)

            VStack(spacing: 0) {
                linkRow(label: "Privacy Policy", url: Self.privacyURL,
                        isFirst: true, isLast: false)
                Rectangle().fill(t.line).frame(height: 1).padding(.horizontal, 14)
                linkRow(label: "Support", url: Self.supportURL,
                        isFirst: false, isLast: true)
            }
            .background(t.glassSurface())
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(t.line, lineWidth: 1))
            .padding(.horizontal, 20)
        }
    }

    private func linkRow(label: String, url: URL,
                         isFirst: Bool, isLast: Bool) -> some View {
        Link(destination: url) {
            HStack {
                Text(label).font(t.sans(13)).foregroundStyle(t.fg)
                    .lineSpacing(2)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12)).foregroundStyle(t.dim)
            }
            .padding(.horizontal, 14).padding(.vertical, 14)
            .contentShape(Rectangle())
        }
    }

    private var versionLabel: String {
        let v = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
        let b = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"
        return "v\(v) (\(b))"
    }
}

// MARK: - WhatsNewView

struct WhatsNewView: View {
    let entry: WhatsNewEntry
    let onDismiss: () -> Void
    @EnvironmentObject var m: AppModel
    private var t: Theme { m.t }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("What's new")
                        .font(t.mono(11, weight: .medium))
                        .tracking(1.4)
                        .foregroundStyle(t.dim)
                        .padding(.horizontal, 26).padding(.top, 32)

                    Text(entry.headline)
                        .font(t.sans(28, weight: .semibold))
                        .foregroundStyle(t.fg)
                        .padding(.horizontal, 26).padding(.top, 8).padding(.bottom, 28)

                    ForEach(Array(entry.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 16) {
                            ZStack {
                                Circle().fill(t.accent.opacity(0.15))
                                    .frame(width: 40, height: 40)
                                Image(systemName: item.icon)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(t.accent)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(t.sans(15, weight: .semibold))
                                    .foregroundStyle(t.fg)
                                Text(item.body)
                                    .font(t.sans(13)).foregroundStyle(t.dim)
                                    .lineSpacing(3)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22).padding(.bottom, 22)
                    }
                }
            }
            Button(action: onDismiss) {
                Text("Continue")
                    .font(t.sans(15, weight: .semibold))
                    .foregroundStyle(t.contrastFg)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(t.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 22).padding(.vertical, 22)
        }
        .background(t.bg.ignoresSafeArea())
    }
}
