// WhereSia — Me (screen 10).
//
// Profile, Preferences (notifications, open-on, appearance), Accessibility (flag
// wheelchair buses, larger text), About (data source = LTA DataMall, version).
// Wired to AppModel prefs.

import SwiftUI

struct WSMeView: View {
    @Environment(AppModel.self) private var m: AppModel
    @Environment(\.ws) private var ws

    @AppStorage("ws.flagWab") private var flagWab = true

    private var version: String {
        m.currentVersion ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
    }
    private var appearance: String {
        switch m.themeMode { case .system: return "System"; case .light: return "Light"; case .dark: return "Dark" }
    }

    var body: some View {
        // notificationsEnabled/notificationAuth are only read inside the
        // Notifications row's `Binding(get:set:)` closure below, which
        // SwiftUI invokes lazily when it renders the Toggle rather than
        // synchronously during this body call — that's not a guaranteed
        // Observation dependency. Reading them directly here ties the
        // Notifications toggle to the async `.task` refresh below (and to
        // `setNotificationsEnabled`'s permission flow), so a grant/deny
        // reliably repaints the switch.
        let _ = (m.notificationsEnabled, m.notificationAuth)
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 14) {
                    profile
                    preferences
                    accessibility
                    about
                    Color.clear.frame(height: 16)
                }
                .padding(.bottom, 8)
            }
            .wsEntrance()
        }
        .background(ws.bg)
        .task { await m.refreshNotificationAuth() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("ACCOUNT").font(ws.sans(11, weight: .heavy)).tracking(1.4).foregroundStyle(ws.dim)
                Text("Me").font(ws.sans(22, weight: .heavy)).foregroundStyle(ws.text)
            }
            Spacer()
        }
        .padding(.horizontal, 22).padding(.top, 8)
    }

    private var profile: some View {
        HStack(spacing: 15) {
            Circle().fill(ws.panel2)
                .frame(width: 56, height: 56)
                .overlay(Circle().stroke(ws.rule, lineWidth: 1))
                .overlay(WSIcon(glyph: .me, size: 28, color: ws.dim))
            VStack(alignment: .leading, spacing: 4) {
                Text("Commuter").font(ws.sans(19, weight: .heavy)).foregroundStyle(ws.text)
                Text("Local profile · data by LTA DataMall")
                    .font(ws.mono(11.5)).tracking(0.2).foregroundStyle(ws.dim)
            }
            Spacer()
        }
        .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 6)
    }

    // MARK: preferences

    private var preferences: some View {
        WSCard(title: "Preferences") {
            VStack(spacing: 0) {
                SetRow(glyph: .alerts, label: "Notifications", last: false) {
                    WSToggle(isOn: Binding(
                        get: { m.notificationsEnabled && m.notificationAuth != .denied },
                        set: { on in Task { await m.setNotificationsEnabled(on) } }))
                }
                SetRow(glyph: .home, label: "Open on", last: false) {
                    valueChevron("Nearby")
                }
                Button { cycleAppearance() } label: {
                    SetRow(glyph: .sun, label: "Appearance", last: true) { valueChevron(appearance) }
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
    }

    private func cycleAppearance() {
        switch m.themeMode {
        case .system: m.themeMode = .light
        case .light:  m.themeMode = .dark
        case .dark:   m.themeMode = .system
        }
    }

    // MARK: accessibility

    private var accessibility: some View {
        WSCard(title: "Accessibility") {
            VStack(spacing: 0) {
                SetRow(glyph: .wheelchair, label: "Flag wheelchair-access buses", last: false) {
                    WSToggle(isOn: $flagWab)
                }
                SetRow(glyph: .textSize, label: "Larger text", last: true) {
                    valueChevron("System")
                }
            }
        }
        .padding(.horizontal, 22)
    }

    // MARK: about

    private var about: some View {
        WSCard(title: "About") {
            VStack(spacing: 0) {
                SetRow(glyph: .database, label: "Data source", last: false) {
                    valueChevron("LTA DataMall")
                }
                SetRow(glyph: .info, label: "About WhereSia", last: true) {
                    valueChevron("v\(version)")
                }
            }
        }
        .padding(.horizontal, 22)
    }

    private func valueChevron(_ value: String) -> some View {
        HStack(spacing: 9) {
            Text(value).font(ws.mono(12)).foregroundStyle(ws.dim)
            WSIcon(glyph: .chevron, size: 16, color: ws.faint)
        }
    }
}

// MARK: - Settings row

private struct SetRow<Trailing: View>: View {
    let glyph: WSGlyph
    let label: String
    var last: Bool
    @ViewBuilder var trailing: Trailing
    @Environment(\.ws) private var ws
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                WSIcon(glyph: glyph, size: 18)
                    .frame(width: 34, height: 34)
                    .background(ws.panel2)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(ws.rule, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(label).font(ws.sans(14.5, weight: .semibold)).foregroundStyle(ws.text)
                Spacer()
                trailing
            }
            .padding(.vertical, 14)
            if !last { WSRowDivider() }
        }
        .contentShape(Rectangle())
    }
}
