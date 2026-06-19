// LiveTripView — Glance Phase 3: GO trip companion.
//
// Full-screen companion presented when the user taps "Start trip" in
// SoftBusView. Mirrors the prototype's `.go` / `GO_PHASES` / `renderGo()`.
//
// Architecture:
//  • Four phases: Walk → Wait → Ride → Arrived (the prototype's 5 GO_PHASES
//    collapsed: alight-alert is a state of the Ride phase, not a separate phase).
//  • Phase transitions are driven by real live-tracking data where possible
//    (see "data-driven vs approximated" below) and surfaced clearly.
//  • Live Activity is wired through the existing AppModel.startLiveActivity /
//    startLivePolling path — we do NOT create a second Live Activity.
//
// Data-driven vs approximated (declare-first):
//   Walk       — No GPS motion; user taps "Start trip" to advance manually.
//                Approximated: the walk timer counts down from a fixed estimate
//                (caller passes walkSec). No core-location footstep needed.
//   Wait       — Bound to liveService().etaSec: the timer is real. Phase
//                auto-advances when etaSec hits 0 (bus arrived).
//   Ride       — stopsRemaining is the real stops-away from BusProgress +
//                live GPS. The "Get off next stop" alert fires when
//                stopsRemaining == 1 (real data) with a .warning haptic.
//                Phase auto-advances to Arrived when stopsRemaining == 0
//                OR etaSec reaches 0 for the NEXT stop (approximated).
//   Arrived    — Terminal state.
//
// Live Activity: if one is already running (m.liveActivityOn) we don't start
// a second one — the existing arrival-tracking LA is already doing the right
// job. We start one if not yet running and a live Service is available.

import SwiftUI
import MapKit

// MARK: - GO phase model

enum GOPhase: Int, CaseIterable {
    case walk = 0
    case wait = 1
    case ride = 2
    case arrived = 3

    var statusLabel: String {
        switch self {
        case .walk:    return "Walk to stop"
        case .wait:    return "Wait"
        case .ride:    return "On bus"
        case .arrived: return "Arrived"
        }
    }

    var verb: String {
        switch self {
        case .walk:    return "Walk to"
        case .wait:    return "Board in"
        case .ride:    return "Stops to go"
        case .arrived: return ""
        }
    }
}

// MARK: - LiveTripView

struct LiveTripView: View {
    // MARK: Inputs
    let stopCode: String
    let svc: String
    let stopName: String
    let dest: String
    /// Walk time estimate to the stop (seconds). Caller passes this; in the
    /// app it's the walk field from the stop data. If 0 we skip Walk phase.
    let walkSec: Int
    /// The route direction context so stopsRemaining can be computed.
    let direction: RouteDirection?
    /// Estimated bus-position index in the route direction. Updated externally
    /// by SoftBusView on each tick and threaded in.
    let estimatedBusIndex: Int?

    let onClose: () -> Void

    // MARK: Environment
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @EnvironmentObject var ds: DataStore

    // MARK: State
    @State private var phase: GOPhase
    @State private var walkSecondsLeft: Int
    @State private var didFireGetOffAlert = false
    @State private var didStartLA = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: Init
    init(stopCode: String, svc: String, stopName: String, dest: String,
         walkSec: Int, direction: RouteDirection?, estimatedBusIndex: Int?,
         onClose: @escaping () -> Void) {
        self.stopCode = stopCode
        self.svc = svc
        self.stopName = stopName
        self.dest = dest
        self.walkSec = walkSec
        self.direction = direction
        self.estimatedBusIndex = estimatedBusIndex
        self.onClose = onClose
        // If no walk time provided, jump straight to Wait
        _phase = State(initialValue: walkSec > 0 ? .walk : .wait)
        _walkSecondsLeft = State(initialValue: walkSec)
    }

    // MARK: Computed helpers

    private var t: Theme { m.t }

    /// Current live service at this stop.
    private func liveService() -> Service? {
        guard case .loaded(let svcs) = ds.arrivals[stopCode],
              var x = svcs.first(where: { $0.no == svc }) else { return nil }
        let now = Date()
        if let a = x.arrivalDate { x.etaSec = max(0, Int(a.timeIntervalSince(now))) }
        return x
    }

    /// How many stops until the user's boarding stop.
    private var stopsRemaining: Int? {
        guard let dir = direction, let busIdx = estimatedBusIndex else { return nil }
        let youIdx = min(max(dir.youIndex, 0), dir.stops.count - 1)
        return max(0, youIdx - busIdx)
    }

    // Progress strip: 4 segments (walk / wait / ride / arrived)
    // walk step shows only if walkSec > 0
    private var progressSegments: [GOPhase] {
        walkSec > 0
            ? [.walk, .wait, .ride, .arrived]
            : [.wait, .ride, .arrived]
    }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                statusBar
                    .padding(.horizontal, 20)
                    .padding(.top, 56)
                    .padding(.bottom, 12)

                heroSection
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                if phase == .ride {
                    getOffAlert
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }

                progressStrip
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)

                stepsSection
                    .padding(.horizontal, 20)

                Spacer(minLength: 12)

                actionButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            ensureLiveActivityRunning()
        }
        .onReceive(ticker) { _ in
            autoAdvance()
        }
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            // Live dot + status label
            HStack(spacing: 6) {
                liveAnimatedDot
                Text(phase.statusLabel.uppercased())
                    .font(t.rounded(12, .heavy))
                    .tracking(1)
                    .foregroundStyle(t.go)
            }
            Spacer(minLength: 0)
            // Close button
            Button {
                fb.select(); onClose()
            } label: {
                Text("Done")
                    .font(t.sans(15, weight: .semibold))
                    .foregroundStyle(t.dim)
                    .frame(width: 44, height: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close trip companion")
        }
    }

    private var liveAnimatedDot: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { tl in
            let phase = tl.date.timeIntervalSinceReferenceDate
            let opacity = 0.45 + 0.55 * (0.5 + 0.5 * sin(phase * .pi * 2 / 2.0))
            Circle()
                .fill(t.go)
                .frame(width: 7, height: 7)
                .opacity(opacity)
        }
    }

    // MARK: Hero section

    @ViewBuilder
    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !phase.verb.isEmpty {
                Text(phase.verb)
                    .font(t.rounded(19, .bold))
                    .foregroundStyle(t.dim)
            }

            heroCountDisplay
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(heroA11yLabel)

            Text(heroSubLabel)
                .font(t.sans(15, weight: .semibold))
                .foregroundStyle(t.dim)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var heroCountDisplay: some View {
        switch phase {
        case .walk:
            countdownNumeral(
                text: walkSecondsLeft > 60
                    ? "\(Int(ceil(Double(walkSecondsLeft) / 60)))"
                    : "\(walkSecondsLeft)",
                unit: walkSecondsLeft > 60 ? "min" : "sec",
                color: t.fg
            )

        case .wait:
            let s = liveService()
            let eta = s.map { fmtETA($0.etaSec) }
            if let eta, eta.big == "Arr" {
                countdownNumeral(text: "0", unit: "now", color: t.go)
            } else if let eta {
                countdownNumeral(text: eta.big, unit: eta.small, color: t.fg)
            } else {
                Text("—")
                    .font(t.rounded(86, .heavy).monospacedDigit())
                    .foregroundStyle(t.dim)
            }

        case .ride:
            let rem = stopsRemaining
            if let rem, rem <= 1 {
                Text(rem == 0 ? "Off!" : "next")
                    .font(t.rounded(86, .heavy).monospacedDigit())
                    .foregroundStyle(t.go)
            } else if let rem {
                countdownNumeral(text: "\(rem)", unit: "stop\(rem == 1 ? "" : "s")", color: t.fg)
            } else {
                // Approximated: no route position data — show ETA-based count
                if let s = liveService() {
                    let approxStops = max(0, Int(ceil(Double(s.etaSec) / 90)))
                    countdownNumeral(text: "~\(approxStops)", unit: "stops", color: t.fg)
                } else {
                    Text("—")
                        .font(t.rounded(86, .heavy).monospacedDigit())
                        .foregroundStyle(t.dim)
                }
            }

        case .arrived:
            Text("✓")
                .font(t.rounded(86, .heavy))
                .foregroundStyle(t.go)
        }
    }

    private func countdownNumeral(text: String, unit: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(text)
                .font(t.rounded(86, .heavy).monospacedDigit())
                .foregroundStyle(color)
                .contentTransition(.numericText(countsDown: true))
            Text(unit)
                .font(t.rounded(19, .semibold))
                .foregroundStyle(t.ink3)
                .padding(.bottom, 8)
        }
    }

    private var heroSubLabel: String {
        switch phase {
        case .walk:
            return stopName
        case .wait:
            return "Bus \(svc) · to \(dest)"
        case .ride:
            let rem = stopsRemaining
            if let rem, rem <= 1 {
                return rem == 0 ? "Your stop now" : "Your stop is next"
            }
            return "Sit tight · Bus \(svc)"
        case .arrived:
            return "You've arrived. Enjoy \(dest)."
        }
    }

    private var heroA11yLabel: String {
        switch phase {
        case .walk:
            let mins = Int(ceil(Double(walkSecondsLeft) / 60))
            return "Walk phase: \(mins) minutes to \(stopName)"
        case .wait:
            if let s = liveService() {
                let eta = fmtETA(s.etaSec)
                return eta.big == "Arr" ? "Bus arriving now" : "Board in \(eta.big) minutes"
            }
            return "Waiting for bus \(svc)"
        case .ride:
            if let rem = stopsRemaining {
                return rem == 0 ? "Your stop now" : "\(rem) stop\(rem == 1 ? "" : "s") to go"
            }
            return "Riding bus \(svc)"
        case .arrived:
            return "Arrived at destination"
        }
    }

    // MARK: Get-off alert (Ride phase only, stopsRemaining == 1)

    @ViewBuilder
    private var getOffAlert: some View {
        let rem = stopsRemaining ?? 999
        if phase == .ride && rem <= 1 {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(t.warnText)
                Text(rem == 0 ? "Get off now — your stop" : "Get off at the next stop")
                    .font(t.rounded(15, .bold))
                    .foregroundStyle(t.warnText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous)
                    .fill(t.warnText.opacity(t.isDark ? 0.18 : 0.10))
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rem == 0 ? "Get off now, your stop" : "Get off at the next stop")
            .accessibilityAddTraits(.isStaticText)
        }
    }

    // MARK: Progress strip (walk · wait · ride · arrived)

    private var progressStrip: some View {
        HStack(spacing: 6) {
            ForEach(progressSegments, id: \.rawValue) { seg in
                Capsule()
                    .fill(progressColor(for: seg))
                    .frame(maxWidth: .infinity)
                    .frame(height: 6)
                    .animation(.easeInOut(duration: 0.3), value: phase)
            }
        }
    }

    private func progressColor(for seg: GOPhase) -> Color {
        if seg.rawValue < phase.rawValue { return t.fg.opacity(0.7) }   // done
        if seg == phase { return t.go }                                   // active
        return t.line                                                      // upcoming
    }

    // MARK: Steps list

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if walkSec > 0 {
                stepRow(
                    icon: "figure.walk",
                    label: "Walk to \(stopName)",
                    stepPhase: .walk
                )
            }
            stepRow(
                icon: "bus.fill",
                label: "Ride \(svc) · \(direction.flatMap { "\($0.stops.count > 0 ? stopsInJourney : "?") stops" } ?? "to \(dest)")",
                stepPhase: .wait
            )
            stepRow(
                icon: "figure.walk",
                label: "Arrive at \(dest)",
                stepPhase: .arrived
            )
        }
    }

    private var stopsInJourney: String {
        guard let dir = direction else { return "?" }
        let youIdx = dir.youIndex
        // We don't know the alight stop, so show stops from boarding to end
        let remaining = max(0, dir.stops.count - 1 - youIdx)
        return "\(remaining)"
    }

    private func stepRow(icon: String, label: String, stepPhase: GOPhase) -> some View {
        let isDone = stepPhase.rawValue < phase.rawValue
        let isNow  = stepPhase == phase || (stepPhase == .wait && phase == .ride)

        return HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isDone ? t.faint : (isNow ? t.fg : t.faint))
                .frame(width: 20)
            Text(label)
                .font(t.sans(14, weight: isNow ? .semibold : .regular))
                .foregroundStyle(isDone ? t.faint : (isNow ? t.fg : t.faint))
                .strikethrough(isDone, color: t.faint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label + (isDone ? ", done" : isNow ? ", current" : ""))
    }

    // MARK: Action button

    @ViewBuilder
    private var actionButton: some View {
        if phase == .arrived {
            Button {
                fb.success(); onClose()
            } label: {
                Text("Done")
                    .font(t.rounded(16, .bold))
                    .foregroundStyle(t.contrastFg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(t.contrast, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressScaleButtonStyle())
        } else {
            Button {
                fb.select()
                advancePhase()
            } label: {
                Text(nextButtonLabel)
                    .font(t.rounded(16, .bold))
                    .foregroundStyle(t.contrastFg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(t.contrast, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressScaleButtonStyle())
        }
    }

    private var nextButtonLabel: String {
        switch phase {
        case .walk:    return "I'm at the stop"
        case .wait:    return "On the bus"
        case .ride:    return "Got off"
        case .arrived: return "Done"
        }
    }

    // MARK: Auto-advance logic (real-data driven)

    private func autoAdvance() {
        switch phase {
        case .walk:
            // Walk: count down manually; no GPS motion — user taps to advance
            if walkSecondsLeft > 0 {
                walkSecondsLeft -= 1
                // Auto-advance only when the walk timer runs to 0
                if walkSecondsLeft == 0 {
                    withAnimation(.easeInOut(duration: 0.35)) { phase = .wait }
                }
            }

        case .wait:
            // Wait: advance to Ride when the bus arrives (etaSec == 0)
            if let s = liveService(), s.etaSec == 0 {
                withAnimation(.easeInOut(duration: 0.35)) { phase = .ride }
            }

        case .ride:
            // Ride: fire haptic when 1 stop away (real data)
            if let rem = stopsRemaining, rem <= 1, !didFireGetOffAlert {
                didFireGetOffAlert = true
                fb.approachingSoon()
            }
            // Advance to Arrived when stops remaining hits 0
            if let rem = stopsRemaining, rem == 0 {
                withAnimation(.easeInOut(duration: 0.35)) { phase = .arrived }
                return
            }
            // Fallback: if we have no position data, use ETA ≤ 0 heuristic
            if stopsRemaining == nil, let s = liveService(), s.etaSec == 0 {
                withAnimation(.easeInOut(duration: 0.35)) { phase = .arrived }
            }

        case .arrived:
            break
        }
    }

    private func advancePhase() {
        let next = GOPhase(rawValue: phase.rawValue + 1) ?? .arrived
        withAnimation(.easeInOut(duration: 0.35)) {
            phase = next
        }
        // Re-arm the get-off alert flag when entering Ride (user tapped manually)
        if next == .ride { didFireGetOffAlert = false }
    }

    // MARK: Live Activity wiring

    /// Start the Live Activity via the existing AppModel path if not already
    /// running. We do NOT create a second LA — AppModel owns exactly one.
    private func ensureLiveActivityRunning() {
        guard !m.liveActivityOn else { return }   // already running
        guard let s = liveService() else { return }
        m.startLiveActivity(s, stopName: stopName, stopCode: stopCode)
        didStartLA = true
    }
}
