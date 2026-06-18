// Onboarding — Leyne 3.0 first-run flow:
// Welcome → "Always up to the minute" (the timeliness wedge) → three primed
// iOS permission requests (Location → Notifications → ATT) → "You're all
// set" grant summary. Each primer shows in-app context, then fires the real
// system prompt; the summary reflects the actual granted states.

import SwiftUI
import CoreLocation
import UserNotifications
import AppTrackingTransparency

struct OnboardingView: View {
    let t: Theme
    let dark: Bool
    var onRequestLocation: () -> Void = {}
    var onRequestNotifications: () -> Void = {}
    /// Runs UMP + ATT consent (no longer finishes onboarding — the summary
    /// screen does, via onFinish).
    var onRequestTracking: () -> Void = {}
    var onFinish: () -> Void = {}

    @EnvironmentObject private var m: AppModel

    // 0 welcome · 1 live · 2 location · 3 notifications · 4 ATT · 5 done
    @State private var step = 0
    // Drives the push direction so a "Back" tap slides the opposite way to
    // an "advance" — keeps the slide reading as a coherent stack, not a
    // same-side cross-fade.
    @State private var goingBack = false
    // Single-shot guard so rapid taps don't spawn multiple consent flows.
    @State private var trackingTapped = false

    private var stepAnimation: Animation { .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.34) }

    // A short horizontal slide + fade — a crisp "push". `.move(edge:)` slid a
    // whole screen of content the full screen width each step, which read as
    // heavy and smeared during the cross-fade; a small fixed offset settles in
    // cleanly instead. Forward pushes both steps left, Back pushes both right.
    private func stepTransition(_ back: Bool) -> AnyTransition {
        let dx: CGFloat = 44
        return .asymmetric(
            insertion: .modifier(active: OnbSlide(dx: back ? -dx : dx, opacity: 0),
                                 identity: OnbSlide(dx: 0, opacity: 1)),
            removal: .modifier(active: OnbSlide(dx: back ? dx : -dx, opacity: 0),
                               identity: OnbSlide(dx: 0, opacity: 1))
        )
    }

    private func advance() {
        goingBack = false
        withAnimation(stepAnimation) { step += 1 }
    }

    private func goBack() {
        goingBack = true
        withAnimation(stepAnimation) { step -= 1 }
    }

    var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                // The step content carries `.id`/`.transition` directly (NOT a
                // Group, whose modifiers distribute to children and break the
                // transition). The whole subtree slides as one unit so text,
                // cards and CTA move together.
                //
                // It's wrapped in a ZStack so the outgoing and incoming steps
                // OVERLAP during a step change and slide across each other. As a
                // direct child of the outer VStack they'd be laid out stacked
                // vertically while both exist mid-transition — the VStack splits
                // the area between two `maxHeight: .infinity` siblings, squishing
                // and shifting the content so it doesn't move with the slide.
                ZStack {
                    stepContent
                        .id(step)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(stepTransition(goingBack))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.vertical, 20)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: welcome
        case 1: live
        case 2: locationPrimer
        case 3: notifPrimer
        case 4: attPrimer
        default: done
        }
    }

    private var topBar: some View {
        HStack {
            Button { if step > 0 { goBack() } } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold))
                    Text("Back")
                }
                .font(t.sans(15))
                .foregroundStyle(step > 0 && step != 5 ? t.accent : .clear)
            }
            .disabled(step == 0 || step == 5)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 10)
    }

    // MARK: 0 · Welcome

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            wordmark(size: 44)
            Text("Singapore’s buses & MRT,\nin real time.")
                .font(t.sans(20, weight: .semibold))
                .foregroundStyle(t.fg)
                .multilineTextAlignment(.center)
                .padding(.top, 24)
            Text("Live arrivals the moment they change — your bus on the map, and a nudge before it pulls in.")
                .font(t.sans(14))
                .foregroundStyle(t.dim)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 12)
                .padding(.horizontal, 8)
                .frame(maxWidth: 300)
            Spacer()
            primaryButton("Get started") { advance() }
            Text("No account needed")
                .font(t.mono(12, weight: .medium))
                .foregroundStyle(t.faint)
                .padding(.top, 14)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func wordmark(size: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: size * 0.1) {
            Text("leyne")
                .font(t.sans(size, weight: .bold))
                .foregroundStyle(t.fg)
            Circle().fill(t.accent)
                .frame(width: size * 0.16, height: size * 0.16)
                .padding(.bottom, size * 0.18)
        }
    }

    // MARK: 1 · Live (the timeliness wedge)

    private var live: some View {
        stepScaffold(dotsIndex: -1) {
            VStack(alignment: .leading, spacing: 0) {
                kicker("Why Leyne")
                Text("Always up to the minute.")
                    .font(t.sans(27, weight: .bold))
                    .foregroundStyle(t.fg)
                    .padding(.top, 8)
                Text("Real-time arrivals, refreshed continuously — so you always know when to leave and exactly where your bus is.")
                    .font(t.sans(15))
                    .foregroundStyle(t.dim)
                    .lineSpacing(3)
                    .padding(.top, 12)
                OnbVisualLive(t: t).padding(.top, 22)
            }
        } cta: {
            primaryButton("Continue") { advance() }
        }
    }

    // MARK: 2–4 · Permission primers

    private var locationPrimer: some View {
        primer(dotsIndex: 0, icon: "location.fill", kicker: "Permission 1 of 3",
               title: "Find stops around you",
               body: "Leyne uses your location to surface the nearest stops and place your bus, you and your stop on the map.",
               points: [("mappin.and.ellipse", "Nearest stops, sorted by distance"),
                        ("bus.fill", "See exactly where your stop is")],
               // Guideline 5.1.1(iv): neutral button wording ("Continue", not
               // "Allow location") and NO in-app skip/exit before the system
               // location prompt. The OS dialog is where allow/deny happens.
               primary: "Continue", onPrimary: { onRequestLocation(); advance() })
    }

    private var notifPrimer: some View {
        primer(dotsIndex: 1, icon: "bell.fill", kicker: "Permission 2 of 3",
               title: "Never miss your bus",
               body: "Get a heads-up when it’s time to leave, and a nudge the moment your bus is pulling in.",
               points: [("clock", "Leave-now alerts for your trip"),
                        ("lock.fill", "Live Activity counts down on your lock screen")],
               primary: "Enable notifications", onPrimary: { onRequestNotifications(); advance() },
               secondary: "Maybe later", onSecondary: { advance() })
    }

    private var attPrimer: some View {
        primer(dotsIndex: 2, icon: "hand.raised.fill", kicker: "Permission 3 of 3",
               title: "Keep Leyne free",
               body: "Leyne runs a few ads to stay free. Allowing tracking makes them more relevant — but it’s entirely your call, and Leyne works fully either way.",
               points: [("xmark", "Decline and nothing changes for you")],
               primary: "Continue", onPrimary: {
                   guard !trackingTapped else { return }
                   trackingTapped = true
                   onRequestTracking()
                   advance()
               })
    }

    // MARK: 5 · Done

    private var done: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(t.onAccent)
                .frame(width: 84, height: 84)
                .background(t.accent, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            Text("You’re all set")
                .font(t.sans(27, weight: .bold))
                .foregroundStyle(t.fg)
                .padding(.top, 26)
            Text("Leyne is ready. Your nearest stops are already loading.")
                .font(t.sans(14))
                .foregroundStyle(t.dim)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 10)
                .frame(maxWidth: 280)
            VStack(spacing: 8) {
                grantRow("Location", state: locationGrant)
                grantRow("Notifications", state: notifGrant)
                grantRow("Ad tracking", state: attGrant)
            }
            .padding(.top, 24)
            Spacer()
            primaryButton("Enter Leyne") { onFinish() }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Grant summary

    private enum Grant { case on, off, skipped
        var text: String { self == .on ? "On" : self == .off ? "Off" : "Skipped" }
        var granted: Bool { self == .on }
    }

    private var locationGrant: Grant {
        switch LocationManager.shared.status {
        case .authorizedWhenInUse, .authorizedAlways: return .on
        case .denied, .restricted: return .off
        default: return .skipped
        }
    }
    private var notifGrant: Grant {
        switch m.notificationAuth {
        case .authorized, .provisional, .ephemeral: return .on
        case .denied: return .off
        default: return .skipped
        }
    }
    private var attGrant: Grant {
        switch ATTrackingManager.trackingAuthorizationStatus {
        case .authorized: return .on
        case .denied, .restricted: return .off
        default: return .skipped
        }
    }

    private func grantRow(_ label: String, state: Grant) -> some View {
        HStack {
            Text(label).font(t.sans(14, weight: .semibold)).foregroundStyle(t.fg)
            Spacer()
            Text(state.text)
                .font(t.mono(12, weight: .semibold))
                .foregroundStyle(state.granted ? t.fg : t.dim)
            Image(systemName: state.granted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(state.granted ? t.accent : t.faint)
        }
        .padding(.horizontal, 15).padding(.vertical, 11)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Building blocks

    private func kicker(_ s: String) -> some View {
        Text(s.uppercased())
            .font(t.mono(11, weight: .bold)).tracking(1.2)
            .foregroundStyle(t.accent)
    }

    private func dots(_ index: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(i == index ? t.accent : t.line)
                    .frame(width: i == index ? 18 : 6, height: 6)
            }
        }
        .opacity(index < 0 ? 0 : 1)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func stepScaffold<Body: View, CTA: View>(
        dotsIndex: Int,
        @ViewBuilder content: () -> Body,
        @ViewBuilder cta: () -> CTA) -> some View {
        VStack(spacing: 0) {
            dots(dotsIndex).padding(.top, 6)
            VStack { content() }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            cta()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func primer(dotsIndex: Int, icon: String, kicker kickerText: String,
                        title: String, body: String,
                        points: [(String, String)],
                        primary: String, onPrimary: @escaping () -> Void,
                        secondary: String? = nil,
                        onSecondary: (() -> Void)? = nil) -> some View {
        stepScaffold(dotsIndex: dotsIndex) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(t.surface)
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(t.line, lineWidth: 1))
                    Image(systemName: icon)
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(t.accent)
                }
                .frame(width: 76, height: 76)

                self.kicker(kickerText).padding(.top, 26)
                Text(title)
                    .font(t.sans(27, weight: .bold))
                    .foregroundStyle(t.fg)
                    .padding(.top, 8)
                Text(body)
                    .font(t.sans(15))
                    .foregroundStyle(t.dim)
                    .lineSpacing(3)
                    .padding(.top, 12)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(points.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: points[i].0)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(t.fg)
                                .frame(width: 22, height: 22)
                                .background(t.surfaceHi, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            Text(points[i].1)
                                .font(t.sans(13.5, weight: .medium))
                                .foregroundStyle(t.fg)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.top, 20)
            }
        } cta: {
            VStack(spacing: 4) {
                primaryButton(primary, action: onPrimary)
                // The secondary "skip" button is omitted on permission primers
                // that must not offer an in-app delay/exit before the system
                // prompt (App Store Guideline 5.1.1(iv) — location). When absent
                // the only way forward is the primary button, which triggers the
                // OS dialog where the user makes the actual allow/deny choice.
                if let secondary, let onSecondary {
                    Button(action: onSecondary) {
                        Text(secondary)
                            .font(t.sans(14, weight: .semibold))
                            .foregroundStyle(t.dim)
                            .frame(maxWidth: .infinity).frame(height: 44)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func primaryButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(t.sans(16, weight: .semibold))
                .foregroundStyle(t.onAccent)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(t.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step transition modifier

/// Drives the onboarding step slide: a small horizontal offset paired with a
/// fade. Used as the active/identity endpoints of an `.asymmetric` transition.
private struct OnbSlide: ViewModifier {
    let dx: CGFloat
    let opacity: Double
    func body(content: Content) -> some View {
        content.opacity(opacity).offset(x: dx)
    }
}

// MARK: - The timeliness wedge visual (3 feature rows)

private struct OnbVisualLive: View {
    let t: Theme
    private struct Row: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let desc: String
    }
    private let rows: [Row] = [
        .init(icon: "dot.radiowaves.up.forward", title: "Live arrivals", desc: "refreshed continuously"),
        .init(icon: "map.fill",                  title: "On the map",    desc: "your bus, you and your stop"),
        .init(icon: "bell.fill",                 title: "Smart alerts",  desc: "a nudge before it pulls in"),
    ]
    var body: some View {
        VStack(spacing: 10) {
            ForEach(rows) { r in
                HStack(spacing: 12) {
                    Image(systemName: r.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(t.accent)
                        .frame(width: 40, height: 40)
                        .background(t.liveBg, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.title).font(t.sans(14, weight: .semibold)).foregroundStyle(t.fg)
                        Text(r.desc).font(t.mono(11)).foregroundStyle(t.dim)
                    }
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(t.line, lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity)
    }
}
