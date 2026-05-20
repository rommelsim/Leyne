// Settings tab — in-app control surface. Ported from settings.jsx.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var m: AppModel

    @State private var collapsed = false
    private var t: Theme { m.t }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    titleHeader
                    feedbackSection
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

    @ViewBuilder private var feedbackSection: some View {
        section("FEEDBACK") {
            inlineRow("Sound") { LyneSwitch(t: t, value: soundBinding) }
            Divider().overlay(t.line)
            inlineRow("Haptics") { LyneSwitch(t: t, value: hapticBinding) }
        }
    }

    @ViewBuilder private var aboutSection: some View {
        section("ABOUT") {
            inlineRow("App") {
                Text("Leyne · v1.0 · beta").font(t.mono(13)).foregroundStyle(t.dim)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            LyneMark(dim: t.fg, live: t.live, lineWidth: 6, dimOpacity: 0.4)
                .frame(width: 36, height: 36)
            Text("LEYNE · BETA").font(t.mono(11)).tracking(1.2).foregroundStyle(t.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40).padding(.bottom, 20)
    }

    // bindings that also keep Feedback in sync
    private var soundBinding: Binding<Bool> {
        Binding(get: { m.sound }, set: { m.sound = $0; m.syncFeedback() })
    }
    private var hapticBinding: Binding<Bool> {
        Binding(get: { m.haptic }, set: { m.haptic = $0; m.syncFeedback() })
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

}
