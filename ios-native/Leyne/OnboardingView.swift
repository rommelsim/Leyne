// Onboarding — 5-step intro. Ported from onboarding.jsx.

import SwiftUI

private struct OnbStep {
    let eyebrow: String
    let title: String
    let subtitle: String
    let cta: String
    let footnote: String?
}

struct OnboardingView: View {
    let t: Theme
    let dark: Bool
    var onRequestLocation: () -> Void = {}
    /// Fires the iOS notification permission prompt — wired from RootView
    /// to AppModel.setNotificationsEnabled(true). Called on Continue from
    /// step 3 ("STAY PRESENT") so the system prompt appears in context.
    var onRequestNotifications: () -> Void = {}
    var onRequestTracking: () -> Void = {}

    @State private var step = 0
    // Single-shot guard for the final "Ads" step. Without it, rapid taps
    // on Continue spawn multiple `Task { await AdConsent.gatherThenStart()
    // ; m.finishOnboarding() }` jobs in the host. The 2nd job sees the
    // consent flow already in progress, no-ops the await, and dismisses
    // onboarding immediately — yanking the window state out from under
    // the in-flight ATT prompt, which silently fails to present.
    @State private var trackingTapped = false

    private let steps: [OnbStep] = [
        OnbStep(eyebrow: "LEYNE", title: "Right on cue.",
                subtitle: "A small card on your home screen tells you when your bus is close — so you can stop reaching for your phone.",
                cta: "Continue", footnote: nil),
        OnbStep(eyebrow: "STEP 1 · PIN", title: "Your bus stops, always on top.",
                subtitle: "Pin the stops you actually use. Rename them. Reorder them. Live arrivals update in the background.",
                cta: "Continue", footnote: nil),
        OnbStep(eyebrow: "STEP 2 · NARROW", title: "Pick the buses you ride.",
                subtitle: "A stop can serve a dozen routes. Track only the ones you actually take — the rest stay out of your way.",
                cta: "Continue", footnote: nil),
        OnbStep(eyebrow: "STEP 3 · STAY PRESENT", title: "We’ll buzz when it’s close.",
                subtitle: "Set notify-at-2-min on any stop. Put the phone away. You’ll know in time to walk over.",
                cta: "Continue", footnote: nil),
        OnbStep(eyebrow: "STEP 4 · LOCATION", title: "See stops near you.",
                subtitle: "We use your location only to find bus stops within walking distance. It stays on your device, is never sold, and you can change this anytime in Settings.",
                cta: "Continue", footnote: "You’ll see the standard iOS location prompt next."),
        OnbStep(eyebrow: "STEP 5 · ADS", title: "Free, thanks to ads.",
                subtitle: "Leyne is free because it shows ads. With your permission they can be more relevant to you; decline and you’ll still get ads and every feature — entirely your choice.",
                cta: "Continue", footnote: "Next, iOS asks whether Leyne can track. The app works either way."),
    ]

    var body: some View {
        let s = steps[step]
        VStack(spacing: 0) {
            // top bar: back only (no skip — onboarding runs the full flow)
            HStack {
                Button { if step > 0 { step -= 1 } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold))
                        Text("Back")
                    }
                    .font(t.sans(15))
                    .foregroundStyle(step > 0 ? t.accent : .clear)
                }
                .disabled(step == 0)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 10)

            // visual
            Group {
                switch step {
                case 0: OnbVisualHero(t: t, dark: dark)
                case 1: OnbVisualStack(t: t)
                case 2: OnbVisualNarrow(t: t)
                case 3: OnbVisualNotification(t: t, dark: dark)
                case 4: OnbVisualLocation(t: t, dark: dark)
                default: OnbVisualTracking(t: t, dark: dark)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .id(step)
            .transition(.opacity.combined(with: .move(edge: .trailing)))

            // copy
            VStack(alignment: .leading, spacing: 10) {
                Text(s.eyebrow).font(t.mono(11)).tracking(1.4).foregroundStyle(t.dim)
                Text(s.title)
                    .font(t.sans(30, weight: .semibold))
                    .foregroundStyle(t.fg)
                    .fixedSize(horizontal: false, vertical: true)
                Text(s.subtitle)
                    .font(t.sans(15)).foregroundStyle(t.dim)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let fn = s.footnote {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle").font(.system(size: 11))
                        Text(fn)
                    }
                    .font(t.mono(11)).foregroundStyle(t.dim.opacity(0.85))
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28).padding(.top, 24)

            // dots + CTA
            VStack(spacing: 18) {
                HStack(spacing: 6) {
                    ForEach(steps.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == step ? t.accent : t.line)
                            .frame(width: i == step ? 20 : 6, height: 6)
                    }
                }
                Button {
                    let last = steps.count - 1
                    if step == 3 {                   // NOTIFICATIONS priming
                        onRequestNotifications()
                        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.4)) { step += 1 }
                    } else if step == last - 1 {     // LOCATION priming (2nd-to-last)
                        onRequestLocation()
                        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.4)) { step += 1 }
                    } else if step == last {         // ADS / ATT priming (last)
                        // Single-shot guard prevents rapid taps from spawning
                        // multiple consent flows — the 2nd would no-op the await
                        // and dismiss onboarding mid-prompt, killing the ATT sheet.
                        guard !trackingTapped else { return }
                        trackingTapped = true
                        // Show Google UMP + Apple ATT, start the SDK, then the
                        // host dismisses onboarding (see RootView).
                        onRequestTracking()
                    } else {
                        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.4)) { step += 1 }
                    }
                } label: {
                    Text(s.cta)
                        .font(t.sans(16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(t.accent, in: RoundedRectangle(cornerRadius: 14))
                        .opacity(step == steps.count - 1 && trackingTapped ? 0.55 : 1)
                }
                .buttonStyle(.plain)
                .disabled(step == steps.count - 1 && trackingTapped)
                .onChange(of: step) { _, newStep in
                    // Back-from-final re-arms the tap so the user can
                    // Continue again on the next visit to the final step.
                    if newStep != steps.count - 1 { trackingTapped = false }
                }
            }
            .padding(.horizontal, 24).padding(.top, 24)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(t.bg.ignoresSafeArea())
    }
}

// ─── Visual mocks ─────────────────────────────────────────
private struct OnbVisualCard: View {
    let t: Theme
    let label: String, stop: String, no: String, dest: String, eta: String
    var arriving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✎ \(label.uppercased()) · STOP \(stop)")
                    .font(t.mono(10)).tracking(0.8).foregroundStyle(t.dim)
                Spacer()
                if arriving { PulseDot(color: t.live) }
            }
            .padding(.horizontal, 16).padding(.top, 14)
            Text(dest).font(t.sans(16, weight: .semibold)).foregroundStyle(t.fg)
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
            HStack {
                Text(no).font(t.mono(20, weight: .bold)).foregroundStyle(t.fg)
                Text(dest).font(t.sans(12)).foregroundStyle(t.dim)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(eta).font(t.mono(24, weight: .medium))
                        .foregroundStyle(arriving ? t.live : t.fg)
                    Text("min").font(t.sans(11)).foregroundStyle(t.dim)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(arriving ? t.liveBg : .clear)
            .overlay(alignment: .top) { Divider().overlay(t.line) }
        }
        .frame(maxWidth: 320)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(arriving ? t.live : t.line, lineWidth: 1))
        .shadow(color: arriving ? t.live.opacity(0.19) : .black.opacity(0.05),
                radius: arriving ? 15 : 7, y: arriving ? 8 : 4)
    }
}

private struct OnbVisualStack: View {
    let t: Theme
    var body: some View {
        VStack(spacing: 10) {
            OnbVisualCard(t: t, label: "Morning", stop: "53061", no: "88", dest: "Bef Bishan Stn", eta: "2", arriving: true)
            OnbVisualCard(t: t, label: "Evening", stop: "53241", no: "174", dest: "Opp Blk 211", eta: "9")
            OnbVisualCard(t: t, label: "NUS days", stop: "01113", no: "14", dest: "Bugis Stn", eta: "6")
        }
        .frame(maxWidth: 320)
    }
}

private struct OnbVisualNarrow: View {
    let t: Theme
    private let rows: [(no: String, dest: String, eta: String, on: Bool, live: Bool)] = [
        ("88", "Bukit Panjang", "2", true, true),
        ("156", "Clementi", "9", false, false),
        ("410", "Loop", "4", false, false),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("✎ MORNING · STOP 53061").font(t.mono(10)).tracking(0.8).foregroundStyle(t.dim)
                .padding(.horizontal, 16).padding(.top, 14)
            Text("Bef Bishan Stn").font(t.sans(16, weight: .semibold)).foregroundStyle(t.fg)
                .padding(.horizontal, 16).padding(.top, 6)
            Text("Tracking 1 of 3").font(t.mono(10)).foregroundStyle(t.accent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(t.accent.opacity(0.08), in: Capsule())
                .overlay(Capsule().stroke(t.accent.opacity(0.25), lineWidth: 1))
                .padding(.horizontal, 16).padding(.top, 6)
            VStack(spacing: 0) {
                ForEach(rows, id: \.no) { r in
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(r.on ? t.accent : .clear)
                                .frame(width: 22, height: 22)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(r.on ? t.accent : t.line, lineWidth: 1.5))
                            if r.on {
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                            }
                        }
                        Text(r.no).font(t.mono(17, weight: .bold)).foregroundStyle(t.fg).frame(minWidth: 38, alignment: .leading)
                        Text("→ \(r.dest)").font(t.sans(13)).foregroundStyle(t.fg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(r.eta).font(t.mono(18, weight: .medium)).foregroundStyle(r.live ? t.live : t.fg)
                            Text("m").font(t.sans(10)).foregroundStyle(t.dim)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(r.live ? t.liveBg : .clear)
                    .opacity(r.on ? 1 : 0.4)
                    .overlay(alignment: .top) { Divider().overlay(t.line) }
                }
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: 320)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(t.line, lineWidth: 1))
    }
}

private struct OnbVisualLocation: View {
    let t: Theme
    let dark: Bool
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10).fill(t.accent)
                    .frame(width: 36, height: 36)
                    .overlay(Image(systemName: "location.fill").foregroundStyle(.white).font(.system(size: 16)))
                Text("Allow “Leyne” to use your location?")
                    .font(t.sans(15, weight: .semibold)).foregroundStyle(t.fg)
                    .multilineTextAlignment(.center)
                Text("Leyne needs your location to show bus stops within walking distance. You can change this anytime in Settings.")
                    .font(t.sans(12)).foregroundStyle(t.dim)
                    .multilineTextAlignment(.center).lineSpacing(2)
            }
            .padding(.horizontal, 16).padding(.vertical, 16)
            VStack(spacing: 0) {
                ForEach(["Allow Once", "Allow While Using App", "Don’t Allow"], id: \.self) { opt in
                    Divider().overlay(t.line)
                    Text(opt)
                        .font(t.sans(14, weight: opt == "Don’t Allow" ? .regular : .medium))
                        .foregroundStyle(opt == "Don’t Allow" ? t.fg : t.accent)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                }
            }
        }
        .frame(width: 270)
        .background(dark ? Color(hex: "32302A") : Color(hex: "FCFAF3"))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 18)
    }
}

// Mock of Apple's App Tracking Transparency alert (purely illustrative,
// like OnbVisualLocation). The copy mirrors NSUserTrackingUsageDescription
// in LeyneInfo.plist so the priming screen matches the real system prompt.
private struct OnbVisualTracking: View {
    let t: Theme
    let dark: Bool
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10).fill(t.accent)
                    .frame(width: 36, height: 36)
                    .overlay(Image(systemName: "hand.raised.fill").foregroundStyle(.white).font(.system(size: 16)))
                Text("Allow “Leyne” to track your activity across other companies’ apps and websites?")
                    .font(t.sans(15, weight: .semibold)).foregroundStyle(t.fg)
                    .multilineTextAlignment(.center)
                Text("Leyne uses your device identifier to show ads relevant to you and to keep the app free.")
                    .font(t.sans(12)).foregroundStyle(t.dim)
                    .multilineTextAlignment(.center).lineSpacing(2)
            }
            .padding(.horizontal, 16).padding(.vertical, 16)
            VStack(spacing: 0) {
                ForEach(["Allow Tracking", "Ask App Not to Track"], id: \.self) { opt in
                    Divider().overlay(t.line)
                    Text(opt)
                        .font(t.sans(14, weight: .medium))
                        .foregroundStyle(t.accent)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                }
            }
        }
        .frame(width: 270)
        .background(dark ? Color(hex: "32302A") : Color(hex: "FCFAF3"))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 18)
    }
}

private struct OnbVisualNotification: View {
    let t: Theme
    let dark: Bool
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Text("88").font(t.mono(15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(t.live, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("LEYNE · NOW").font(t.mono(10)).tracking(0.6).opacity(0.55)
                    Text("Bus 88 in 2 min").font(t.sans(14, weight: .medium))
                    Text("Bef Bishan Stn · time to head down").font(t.sans(11)).opacity(0.6)
                }
                .foregroundStyle(Color(hex: "F2EFE8"))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(dark ? Color(hex: "2A2925") : Color(hex: "1A1916"),
                        in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(t.live, lineWidth: 1))
            .shadow(color: t.live.opacity(0.2), radius: 18, y: 14)

            Text("INSTEAD OF").font(t.mono(11)).tracking(1).foregroundStyle(t.dim)

            HStack(spacing: 10) {
                Image(systemName: "iphone").font(.system(size: 18)).foregroundStyle(t.fg)
                Text("Checking your phone every 30 seconds").font(t.sans(13)).foregroundStyle(t.fg)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(t.line, lineWidth: 1))
            .opacity(0.55)
        }
        .frame(maxWidth: 320)
    }
}

private struct OnbVisualHero: View {
    let t: Theme
    let dark: Bool
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text("Monday, 18 May").font(t.sans(11)).opacity(0.78)
                Text("9:41").font(.system(size: 56, weight: .ultraLight)).tracking(-2.2)
            }
            .foregroundStyle(dark ? .white : Color(hex: "111111"))
            .padding(.top, 32).padding(.bottom, 20)

            OnbVisualCard(t: t, label: "Morning", stop: "53061", no: "88",
                          dest: "Bef Bishan Stn", eta: "2", arriving: true)
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 18)
        .frame(maxWidth: 280)
        .background(
            (dark
             ? AnyShapeStyle(RadialGradient(colors: [Color(hex: "2a2725"), Color(hex: "14110f"), Color(hex: "08070a")],
                                            center: .top, startRadius: 0, endRadius: 320))
             : AnyShapeStyle(RadialGradient(colors: [Color(hex: "f8eedb"), Color(hex: "e9d8b8"), Color(hex: "c9b696")],
                                            center: .top, startRadius: 0, endRadius: 320)))
        )
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .shadow(color: .black.opacity(dark ? 0.45 : 0.18), radius: 25, y: 20)
    }
}
