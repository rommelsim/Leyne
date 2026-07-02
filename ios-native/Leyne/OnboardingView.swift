// Onboarding — WhereSia first-run flow:
// Welcome (wordmark + line colours) → "Always up to the minute" (the
// timeliness wedge, shown as a mini departure board) → three primed iOS
// permission requests (Location → Notifications → ATT) → "You're all set"
// grant summary. Each primer shows in-app context, then fires the real
// system prompt; the summary reflects the actual granted states.
//
// Styled entirely in WhereSia tokens (WSTheme): board surfaces, Inter/Plex
// faces, greyscale + line-colour capsules, ink CTA. Follows the system
// colour scheme like the rest of the WhereSia layer.

import SwiftUI
import CoreLocation
import UserNotifications
import AppTrackingTransparency

struct OnboardingView: View {
    var onRequestLocation: () -> Void = {}
    var onRequestNotifications: () -> Void = {}
    /// Runs UMP + ATT consent (no longer finishes onboarding — the summary
    /// screen does, via onFinish).
    var onRequestTracking: () -> Void = {}
    var onFinish: () -> Void = {}

    @Environment(AppModel.self) private var m: AppModel
    @Environment(\.colorScheme) private var scheme

    private var ws: WSTheme { .resolve(dark: scheme == .dark) }

    // 0 welcome · 1 live · 2 location · 3 notifications · 4 ATT · 5 done
    // The ATT step only exists while ads are on (AdConfig.adsEnabled) —
    // with ads off the consent flow is a no-op, so priming for it would be
    // asking for a permission the app doesn't use.
    @State private var step = 0

    private var showsATT: Bool { AdConfig.adsEnabled }
    private var permCount: Int { showsATT ? 3 : 2 }
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
            ws.bg.ignoresSafeArea()
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
        // WS components used inside (RouteTile, CrowdGauge, WSLiveBadge…)
        // read the theme from the environment — onboarding sits above WSRoot,
        // so it resolves + injects its own.
        .environment(\.ws, ws)
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
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold))
                    Text("Back")
                }
                .font(ws.sans(14, weight: .semibold))
                .foregroundStyle(step > 0 && step != 5 ? ws.dim : .clear)
            }
            .disabled(step == 0 || step == 5)
            Spacer()
        }
        .padding(.horizontal, 22).padding(.top, 10)
    }

    // MARK: 0 · Welcome

    /// Wordmark block — quotes the launch screen: eyebrow, WhereSia, the six
    /// official line colours as capsules (the app's "colour = data" signature).
    private static let lineOrder = ["NS", "EW", "NE", "CC", "DT", "TE"]

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Text("SINGAPORE · BUS & MRT")
                    .font(ws.sans(11, weight: .heavy)).tracking(2.2)
                    .foregroundStyle(ws.dim)
                Text("WhereSia")
                    .font(ws.sans(40, weight: .heavy))
                    .foregroundStyle(ws.text)
                HStack(spacing: 6) {
                    ForEach(Self.lineOrder, id: \.self) { code in
                        Capsule().fill(WSLine.color(forStationCode: code))
                            .frame(width: 22, height: 5)
                    }
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("Every bus and train,\nin real time.")
                .font(ws.sans(19, weight: .bold))
                .foregroundStyle(ws.text)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 26)
            Text("Live arrivals the moment they change — your bus on the map, and a nudge before it pulls in.")
                .font(ws.sans(14, weight: .medium))
                .foregroundStyle(ws.dim)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
            Spacer()
            primaryButton("Get started") { advance() }
            Text("NO ACCOUNT NEEDED")
                .font(ws.mono(10, weight: .medium)).tracking(1.2)
                .foregroundStyle(ws.faint)
                .padding(.top, 14)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 1 · Live (the timeliness wedge)

    private var live: some View {
        stepScaffold(dotsIndex: -1) {
            VStack(alignment: .leading, spacing: 0) {
                kicker("Why WhereSia")
                Text("Always up to the minute.")
                    .font(ws.sans(26, weight: .heavy))
                    .foregroundStyle(ws.text)
                    .padding(.top, 8)
                Text("Real-time arrivals, refreshed continuously — so you always know when to leave and exactly where your bus is.")
                    .font(ws.sans(15, weight: .medium))
                    .foregroundStyle(ws.dim)
                    .lineSpacing(3)
                    .padding(.top, 12)
                boardPreview.padding(.top, 24)
            }
        } cta: {
            primaryButton("Continue") { advance() }
        }
    }

    /// A mini departure board — the actual app idiom (route tile, live badge,
    /// big mono ETA, crowd gauge + word) instead of an abstract feature list.
    private var boardPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("NEARBY")
                    .font(ws.sans(10.5, weight: .heavy)).tracking(1.4)
                    .foregroundStyle(ws.dim)
                WSLiveBadge()
                Rectangle().fill(ws.rule).frame(height: 1)
            }
            .padding(.bottom, 12)
            previewRow(no: "174", dest: "Towards Clementi", eta: "3", load: .sea)
            WSRowDivider().padding(.vertical, 11)
            previewRow(no: "961M", dest: "Towards Marina Ctr", eta: "7", load: .sda)
        }
        .padding(16)
        .background(ws.panel)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ws.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of live arrivals")
    }

    private func previewRow(no: String, dest: String, eta: String, load: Load) -> some View {
        HStack(spacing: 12) {
            RouteTile(text: no)
            Text(dest).font(ws.sans(14, weight: .bold)).foregroundStyle(ws.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            (Text(eta).font(ws.mono(17, weight: .bold)).foregroundStyle(ws.text)
             + Text(" min").font(ws.mono(10, weight: .semibold)).foregroundStyle(ws.dim))
            CrowdGauge(fraction: load.wsFraction, width: 22)
            Text(load.wsWord).font(ws.mono(10)).foregroundStyle(ws.dim)
        }
    }

    // MARK: 2–4 · Permission primers

    private var locationPrimer: some View {
        primer(dotsIndex: 0, glyph: .location, kicker: "Permission 1 of \(permCount)",
               title: "Find stops around you",
               body: "WhereSia uses your location to surface the nearest stops and place your bus, you and your stop on the map.",
               points: [(.scope, "Nearest stops, sorted by distance"),
                        (.busSingle, "See exactly where your stop is")],
               // Guideline 5.1.1(iv): neutral button wording ("Continue", not
               // "Allow location") and NO in-app skip/exit before the system
               // location prompt. The OS dialog is where allow/deny happens.
               primary: "Continue", onPrimary: { onRequestLocation(); advance() })
    }

    /// Advance past the notifications step — skips the ATT primer entirely
    /// when ads are off.
    private func advanceAfterNotif() {
        goingBack = false
        withAnimation(stepAnimation) { step = showsATT ? 4 : 5 }
    }

    private var notifPrimer: some View {
        primer(dotsIndex: 1, glyph: .alerts, kicker: "Permission 2 of \(permCount)",
               title: "Never miss your bus",
               body: "Get a heads-up when it’s time to leave, and a nudge the moment your bus is pulling in.",
               points: [(.clock, "Leave-now alerts for your trip"),
                        (.live, "Live Activity counts down on your lock screen")],
               primary: "Enable notifications", onPrimary: { onRequestNotifications(); advanceAfterNotif() },
               secondary: "Maybe later", onSecondary: { advanceAfterNotif() })
    }

    private var attPrimer: some View {
        primer(dotsIndex: 2, glyph: .info, kicker: "Permission 3 of 3",
               title: "Keep WhereSia free",
               body: "WhereSia runs a few ads to stay free. Allowing tracking makes them more relevant — but it’s entirely your call, and WhereSia works fully either way.",
               points: [(.close, "Decline and nothing changes for you")],
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
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(ws.bg)
                .frame(width: 84, height: 84)
                .background(ws.text, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            Text("You’re all set")
                .font(ws.sans(26, weight: .heavy))
                .foregroundStyle(ws.text)
                .padding(.top, 26)
            Text("WhereSia is ready. Your nearest stops are already loading.")
                .font(ws.sans(14, weight: .medium))
                .foregroundStyle(ws.dim)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 10)
                .frame(maxWidth: 280)
            VStack(spacing: 8) {
                grantRow("Location", state: locationGrant)
                grantRow("Notifications", state: notifGrant)
                if showsATT { grantRow("Ad tracking", state: attGrant) }
            }
            .padding(.top, 24)
            Spacer()
            primaryButton("Enter WhereSia") { onFinish() }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Grant summary

    private enum Grant { case on, off, skipped
        var text: String { self == .on ? "ON" : self == .off ? "OFF" : "SKIPPED" }
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
            Text(label).font(ws.sans(14, weight: .bold)).foregroundStyle(ws.text)
            Spacer()
            Text(state.text)
                .font(ws.mono(11, weight: .semibold)).tracking(0.6)
                .foregroundStyle(state.granted ? ws.text : ws.dim)
            Image(systemName: state.granted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(state.granted ? ws.accentSoft : ws.faint)
        }
        .padding(.horizontal, 15).padding(.vertical, 12)
        .background(ws.panel)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(ws.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Building blocks

    private func kicker(_ s: String) -> some View {
        Text(s.uppercased())
            .font(ws.sans(11, weight: .heavy)).tracking(1.6)
            .foregroundStyle(ws.dim)
    }

    private func dots(_ index: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<permCount, id: \.self) { i in
                Capsule()
                    .fill(i == index ? ws.accent : ws.rule)
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

    private func primer(dotsIndex: Int, glyph: WSGlyph, kicker kickerText: String,
                        title: String, body: String,
                        points: [(WSGlyph, String)],
                        primary: String, onPrimary: @escaping () -> Void,
                        secondary: String? = nil,
                        onSecondary: (() -> Void)? = nil) -> some View {
        stepScaffold(dotsIndex: dotsIndex) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(ws.panel)
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(ws.rule, lineWidth: 1))
                    WSIcon(glyph: glyph, size: 30, color: ws.text)
                }
                .frame(width: 72, height: 72)

                self.kicker(kickerText).padding(.top, 26)
                Text(title)
                    .font(ws.sans(26, weight: .heavy))
                    .foregroundStyle(ws.text)
                    .padding(.top, 8)
                Text(body)
                    .font(ws.sans(15, weight: .medium))
                    .foregroundStyle(ws.dim)
                    .lineSpacing(3)
                    .padding(.top, 12)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(points.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 10) {
                            WSIcon(glyph: points[i].0, size: 13, color: ws.text)
                                .frame(width: 24, height: 24)
                                .background(ws.panel2, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            Text(points[i].1)
                                .font(ws.sans(13.5, weight: .semibold))
                                .foregroundStyle(ws.text)
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
                            .font(ws.sans(14, weight: .semibold))
                            .foregroundStyle(ws.dim)
                            .frame(maxWidth: .infinity).frame(height: 44)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    /// The WhereSia primary CTA — the ink-filled button (same idiom as Track
    /// Bus's "Alert me"): text-colour fill, board-colour label.
    private func primaryButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(ws.sans(15, weight: .heavy))
                .foregroundStyle(ws.bg)
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(ws.text, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
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
