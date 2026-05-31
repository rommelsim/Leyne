// Onboarding — Leyne 3.0 first-run flow, matching Onboarding.html:
// Welcome → "Honest about your wait" (the confidence wedge) → three primed
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

    // 0 welcome · 1 honest · 2 location · 3 notifications · 4 ATT · 5 done
    @State private var step = 0
    // Single-shot guard so rapid taps don't spawn multiple consent flows.
    @State private var trackingTapped = false

    private func advance() {
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.4)) { step += 1 }
    }

    var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Group {
                    switch step {
                    case 0: welcome
                    case 1: honest
                    case 2: locationPrimer
                    case 3: notifPrimer
                    case 4: attPrimer
                    default: done
                    }
                }
                .id(step)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            .padding(.vertical, 20)
        }
    }

    private var topBar: some View {
        HStack {
            Button { if step > 0 { withAnimation { step -= 1 } } } label: {
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
            Text("Singapore’s buses & MRT,\ntold honestly.")
                .font(t.sans(20, weight: .semibold))
                .foregroundStyle(t.fg)
                .multilineTextAlignment(.center)
                .padding(.top, 24)
            Text("Every app reads the same live feed. Leyne is the one that admits when it’s unsure — so you’re never left guessing.")
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

    // MARK: 1 · Honest (the confidence wedge)

    private var honest: some View {
        stepScaffold(dotsIndex: -1) {
            VStack(alignment: .leading, spacing: 0) {
                kicker("Why Leyne")
                Text("Honest about your wait.")
                    .font(t.sans(27, weight: .bold))
                    .foregroundStyle(t.fg)
                    .padding(.top, 8)
                Text("Live feeds drop out. Buses run without signal. Leyne shows you exactly how much it knows:")
                    .font(t.sans(15))
                    .foregroundStyle(t.dim)
                    .lineSpacing(3)
                    .padding(.top, 12)
                OnbVisualConfidence(t: t).padding(.top, 22)
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
               primary: "Allow location", onPrimary: { onRequestLocation(); advance() },
               secondary: "Not now", onSecondary: { advance() })
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
               },
               secondary: "Skip", onSecondary: { advance() })
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
                        secondary: String, onSecondary: @escaping () -> Void) -> some View {
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
                Button(action: onSecondary) {
                    Text(secondary)
                        .font(t.sans(14, weight: .semibold))
                        .foregroundStyle(t.dim)
                        .frame(maxWidth: .infinity).frame(height: 44)
                }.buttonStyle(.plain)
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

// MARK: - The confidence wedge visual (3 mini-states)

private struct OnbVisualConfidence: View {
    let t: Theme
    private struct Row: Identifiable {
        let id = UUID()
        let conf: ArrivalConfidence
        let label: String
        let desc: String
        let sec: Int
    }
    private let rows: [Row] = [
        .init(conf: .live,        label: "Live",      desc: "fresh · GPS-tracked",   sec: 180),
        .init(conf: .stale,       label: "Estimated", desc: "live signal is aging",  sec: 180),
        .init(conf: .unconfirmed, label: "Scheduled", desc: "ghost bus · no GPS",    sec: 540),
    ]
    var body: some View {
        VStack(spacing: 10) {
            ForEach(rows) { r in
                HStack(spacing: 12) {
                    ConfidenceDot(confidence: r.conf, t: t, size: 9)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.label).font(t.sans(14, weight: .semibold)).foregroundStyle(t.fg)
                        Text(r.desc).font(t.mono(11)).foregroundStyle(t.dim)
                    }
                    Spacer(minLength: 8)
                    ConfidenceETA(eta: fmtETA(r.sec), confidence: r.conf,
                                  t: t, size: 22, weight: .semibold)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(t.line, lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity)
    }
}
