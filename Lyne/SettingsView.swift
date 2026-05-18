// Settings tab — in-app control surface. Ported from settings.jsx.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    let onReplayLaunch: () -> Void
    let onReplayOnboarding: () -> Void

    @State private var collapsed = false
    private var t: Theme { m.t }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    titleHeader
                    appearanceSection
                    feedbackSection
                    searchSection
                    tryItSection
                    aboutSection
                    footer
                }
                .padding(.bottom, 20)
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(TitleOffsetKey.self) { collapsed = $0 < -12 }

            StickyCompactBar(t: t, title: "Settings",
                             trailing: AnyView(EmptyView()), visible: collapsed)
        }
        .background(t.bg.ignoresSafeArea())
    }

    private var titleHeader: some View {
        Text("Settings")
            .font(t.sans(32, weight: .semibold))
            .foregroundStyle(t.fg)
            .padding(.horizontal, 20).padding(.top, 34).padding(.bottom, 8)
            .background(GeometryReader { geo in
                Color.clear.preference(key: TitleOffsetKey.self,
                    value: geo.frame(in: .named("scroll")).minY)
            })
    }

    private var appearanceSection: some View {
        section("APPEARANCE") {
            row(label: "Theme",
                sub: "Light follows daylight · Dark is easier on the eyes at night") {
                SegmentedControl(t: t, value: themeBinding,
                                 options: [("light", "Light"), ("dark", "Dark")])
            }
        }
    }

    @ViewBuilder private var feedbackSection: some View {
        section("FEEDBACK",
                hint: "The app stays quiet by default — these only fire for moments that matter (pinning a stop, an arriving bus, etc).") {
            inlineRow("Sound") { LyneSwitch(t: t, value: soundBinding) }
            Divider().overlay(t.line)
            inlineRow("Haptics") { LyneSwitch(t: t, value: hapticBinding) }
            Divider().overlay(t.line)
            inlineRow("Motion", sub: "Device shake on success / arrival") {
                LyneSwitch(t: t, value: motionBinding)
            }
            feedbackTestRow
        }
    }

    private var feedbackTestRow: some View {
        let tests: [(String, () -> Void)] = [
            ("Tap", { fb.tap() }), ("Select", { fb.select() }),
            ("Success", { fb.success() }), ("Arrival", { fb.arrival() })
        ]
        return HStack(spacing: 6) {
            ForEach(tests, id: \.0) { label, fn in
                Button(action: fn) {
                    Text(label).font(t.mono(11)).tracking(0.4)
                        .foregroundStyle(t.dim)
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .overlay(Capsule().stroke(t.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
    }

    private var searchSection: some View {
        section("SEARCH") {
            row(label: "Quick search style",
                sub: "Conservative is a clean iOS sheet · Ambitious shows live smart-parse and predictive chips") {
                SegmentedControl(t: t, value: $m.searchStyle,
                                 options: [("conservative", "Conservative"), ("ambitious", "Ambitious")])
            }
        }
    }

    @ViewBuilder private var tryItSection: some View {
        section("TRY IT") {
            buttonRow("Replay launch animation", action: onReplayLaunch)
            Divider().overlay(t.line)
            buttonRow("Replay onboarding", action: onReplayOnboarding)
        }
    }

    @ViewBuilder private var aboutSection: some View {
        section("ABOUT") {
            inlineRow("App") {
                Text("Lyne · v0.4 · beta").font(t.mono(13)).foregroundStyle(t.dim)
            }
            Divider().overlay(t.line)
            inlineRow("Build") {
                Text("18 May 2026").font(t.mono(13)).foregroundStyle(t.dim)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            LyneMark(dim: t.fg, live: t.live, lineWidth: 6, dimOpacity: 0.4)
                .frame(width: 36, height: 36)
            Text("LYNE · BETA").font(t.mono(11)).tracking(1.2).foregroundStyle(t.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40).padding(.bottom, 20)
    }

    // bindings that also keep Feedback in sync
    private var themeBinding: Binding<String> {
        Binding(get: { m.themeRaw }, set: { m.themeRaw = $0 })
    }
    private var soundBinding: Binding<Bool> {
        Binding(get: { m.sound }, set: { m.sound = $0; m.syncFeedback() })
    }
    private var hapticBinding: Binding<Bool> {
        Binding(get: { m.haptic }, set: { m.haptic = $0; m.syncFeedback() })
    }
    private var motionBinding: Binding<Bool> {
        Binding(get: { m.motion }, set: { m.motion = $0; m.syncFeedback() })
    }

    // ─── Section / row primitives ─────────────────────────
    private func section<C: View>(_ label: String, hint: String? = nil,
                                   @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(t.mono(10)).tracking(1.2).foregroundStyle(t.dim)
                .padding(.horizontal, 20).padding(.bottom, 8)
            VStack(spacing: 0) { content() }
                .background(t.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(t.line, lineWidth: 1))
                .padding(.horizontal, 16)
            if let h = hint {
                Text(h).font(t.sans(11)).foregroundStyle(t.dim).lineSpacing(1.5)
                    .padding(.horizontal, 20).padding(.top, 8)
            }
        }
        .padding(.top, 24)
    }

    private func row<C: View>(label: String, sub: String?,
                              @ViewBuilder _ control: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(t.sans(14, weight: .medium)).foregroundStyle(t.fg)
                if let sub { Text(sub).font(t.sans(11)).foregroundStyle(t.dim).lineSpacing(1) }
            }
            control()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private func inlineRow<C: View>(_ label: String, sub: String? = nil,
                                    @ViewBuilder _ control: () -> C) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(t.sans(14, weight: .medium)).foregroundStyle(t.fg)
                if let sub { Text(sub).font(t.sans(11)).foregroundStyle(t.dim) }
            }
            Spacer()
            control()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func buttonRow(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).font(t.sans(14)).foregroundStyle(t.fg)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(t.dim)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}
