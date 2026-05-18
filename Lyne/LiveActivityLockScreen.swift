// Live Activity — full lock-screen takeover with a state machine:
// tracking → arriving → close → arrived → completed → dismissing.
// Ported from live-activity.jsx (in-app simulation, as in the prototype).

import SwiftUI

private let LA_DEMO_SPEED: Double = 4

enum LAPhase { case tracking, arriving, close, arrived, completed, dismissing }

func phaseFor(eta: Double, postArrivedMs: Double) -> LAPhase {
    if postArrivedMs > 3500 { return .dismissing }
    if postArrivedMs > 1800 { return .completed }
    if eta <= 0 { return .arrived }
    if eta <= 30 { return .close }
    if eta <= 60 { return .arriving }
    return .tracking
}

struct LiveActivityLockScreen: View {
    let activity: ActivityModel
    let onDismiss: () -> Void

    @EnvironmentObject var fb: Feedback
    @State private var now = Date()
    @State private var arrivedAt: Date?
    @State private var postArrivedMs: Double = 0
    @State private var didFireArrival = false
    @State private var leaving = false

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var eta: Double {
        max(0, activity.etaAtStart - now.timeIntervalSince(activity.startedAt) * LA_DEMO_SPEED)
    }
    private var phase: LAPhase { phaseFor(eta: eta, postArrivedMs: postArrivedMs) }

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(hex: "2a2725"), Color(hex: "14110f"), Color(hex: "08070a")],
                           center: .top, startRadius: 0, endRadius: 600)
                .ignoresSafeArea()

            // status row
            VStack {
                HStack {
                    Text("9:41")
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "cellularbars")
                        Image(systemName: "wifi")
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: "F2EFE8"))
                .padding(.horizontal, 28).padding(.top, 8)
                Spacer()
            }

            // clock
            VStack(spacing: 4) {
                Text("Monday, 18 May").font(.system(size: 16)).opacity(0.78)
                Text("9:41").font(.system(size: 86, weight: .ultraLight)).tracking(-3.2)
            }
            .foregroundStyle(Color(hex: "F2EFE8"))
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 88)

            // the activity card
            VStack {
                Spacer()
                LiveActivityCard(activity: activity, eta: eta, phase: phase, onDismiss: dismiss)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 86)
            }

            // home indicator + hint
            VStack {
                Spacer()
                VStack(spacing: 8) {
                    Text("SWIPE UP TO RETURN")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(1.4).foregroundStyle(Color(hex: "5a544a"))
                    Capsule().fill(Color(hex: "F2EFE8").opacity(0.7))
                        .frame(width: 110, height: 4)
                }
                .padding(.bottom, 30)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: dismiss)
        }
        .opacity(leaving ? 0 : 1)
        .scaleEffect(leaving ? 1.04 : 1)
        .onReceive(timer) { _ in
            now = Date()
            if eta <= 0 && arrivedAt == nil {
                arrivedAt = Date()
                if !didFireArrival { didFireArrival = true; fb.arrival() }
            }
            if let a = arrivedAt { postArrivedMs = Date().timeIntervalSince(a) * 1000 }
            if phase == .dismissing { dismiss() }
        }
    }

    private func dismiss() {
        guard !leaving else { return }
        withAnimation(.easeInOut(duration: 0.6)) { leaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onDismiss() }
    }
}

struct LiveActivityCard: View {
    let activity: ActivityModel
    let eta: Double
    let phase: LAPhase
    let onDismiss: () -> Void

    private var arriving: Bool { phase == .arriving || phase == .close }
    private var arrived: Bool { phase == .arrived }
    private var completed: Bool { phase == .completed }

    private var statusBig: String {
        switch phase {
        case .arrived: return "Bus is here"
        case .completed: return "Have a good ride"
        case .close: return "Now"
        case .arriving: return "1"
        default: return String(max(0, Int(ceil(eta / 60))))
        }
    }
    private var statusSmall: String {
        switch phase {
        case .close: return "arriving"
        case .arriving, .tracking: return "min"
        default: return ""
        }
    }
    private var progressPct: Double {
        let total = activity.etaAtStart
        let elapsed = max(0, total - eta)
        return min(100, elapsed / total * 100)
    }

    private var topRow: some View {
        HStack {
            HStack(spacing: 8) {
                LyneMark(dim: Color(hex: "F2EFE8"), live: Color(hex: "5BC07A"),
                         lineWidth: 9, dimOpacity: 0.55)
                    .frame(width: 16, height: 16)
                Text("LYNE · \(completed ? "COMPLETE" : "LIVE")")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1).foregroundStyle(Color(hex: "9a948a"))
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.bottom, 12)
    }

    private var completedRow: some View {
        HStack(spacing: 14) {
            Circle().fill(Color(hex: "5BC07A")).frame(width: 44, height: 44)
                .overlay(Image(systemName: "checkmark").font(.system(size: 18, weight: .heavy)).foregroundStyle(.white))
                .shadow(color: Color(hex: "5BC07A").opacity(0.5), radius: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text("Have a good ride")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(Color(hex: "F2EFE8"))
                Text("Bus \(activity.busNo) arrived at \(activity.stopName)")
                    .font(.system(size: 12)).foregroundStyle(Color(hex: "9a948a"))
            }
            Spacer(minLength: 0)
        }
    }

    private var liveRow: some View {
        let primary = arrived || phase == .close
        return HStack(spacing: 12) {
            Text(activity.busNo)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color(hex: "5BC07A"), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text("→ \(activity.dest.uppercased())")
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(0.6).foregroundStyle(Color(hex: "9a948a"))
                Text(primary ? statusBig : "Arrives in \(statusBig) \(statusSmall)")
                    .font(.system(size: primary ? 22 : 16, weight: arrived ? .semibold : .medium))
                    .foregroundStyle(Color(hex: "F2EFE8"))
            }
            Spacer(minLength: 0)
            if phase == .tracking || phase == .arriving {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(statusBig)
                        .font(.system(size: 40, weight: .regular, design: .monospaced))
                        .foregroundStyle(arriving ? Color(hex: "5BC07A") : Color(hex: "F2EFE8"))
                    Text(statusSmall)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color(hex: "9a948a"))
                }
            }
        }
        .id(statusBig)
        .transition(.opacity)
    }

    private var footerRow: some View {
        HStack {
            Text(activity.stopName.uppercased())
            Spacer()
            Text(arrived ? "— ARRIVED —"
                 : phase == .close ? "HEAD DOWN"
                 : phase == .arriving ? "GET READY" : "TRACKING")
                .foregroundStyle(arriving ? Color(hex: "5BC07A") : Color(hex: "7d7368"))
        }
        .font(.system(size: 9.5, weight: .regular, design: .monospaced))
        .tracking(0.6).foregroundStyle(Color(hex: "7d7368"))
        .padding(.top, 10)
    }

    private var strokeColor: Color {
        arrived ? Color(hex: "5BC07A")
            : arriving ? Color(hex: "5BC07A").opacity(0.65)
            : .white.opacity(0.08)
    }
    private var shadowColor: Color {
        arrived ? Color(hex: "5BC07A").opacity(0.45)
            : arriving ? Color(hex: "5BC07A").opacity(0.22) : .black.opacity(0.32)
    }

    var body: some View {
        VStack(spacing: 0) {
            topRow
            if completed { completedRow } else { liveRow }
            if !completed {
                StopStrip(progressPct: progressPct, arrived: arrived || completed)
                    .padding(.top, 14)
                footerRow
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .background(Color(hex: "14110f").opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(strokeColor, lineWidth: arrived ? 1.5 : 1)
        )
        .shadow(color: shadowColor,
                radius: arrived ? 48 : arriving ? 28 : 18, y: 18)
        .scaleEffect(arrived ? 1.015 : 1)
        .animation(.spring(response: 0.5, dampingFraction: 0.5), value: arrived)
        .animation(.easeInOut(duration: 0.4), value: phase)
    }
}

struct StopStrip: View {
    let progressPct: Double
    let arrived: Bool
    private let stops: [Double] = [0, 16, 33, 50, 66, 83, 100]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let span = w * 0.92
            let left = w * 0.04
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.10))
                    .frame(width: span, height: 2).offset(x: left, y: 11)
                Capsule().fill(Color(hex: "5BC07A"))
                    .frame(width: span * min(1, progressPct / 100), height: 2)
                    .offset(x: left, y: 11)
                ForEach(Array(stops.enumerated()), id: \.offset) { i, p in
                    let isYou = i == stops.count - 1
                    let passed = (p / 100) < progressPct / 100
                    Circle()
                        .fill(isYou ? .clear : (passed ? Color(hex: "5BC07A") : .white.opacity(0.25)))
                        .frame(width: isYou ? 8 : 5, height: isYou ? 8 : 5)
                        .overlay(isYou ? Circle().stroke(arrived ? Color(hex: "5BC07A") : Color(hex: "F2EFE8"), lineWidth: 2) : nil)
                        .offset(x: left + span * (p / 100) - (isYou ? 4 : 2.5), y: isYou ? 8 : 8.5)
                }
                Circle().fill(Color(hex: "5BC07A"))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().fill(.black).frame(width: 6, height: 6))
                    .shadow(color: Color(hex: "5BC07A").opacity(0.6), radius: 7)
                    .offset(x: left + span * min(1, progressPct / 100) - 9, y: 3)
            }
            .animation(.timingCurve(0.5, 0.05, 0.2, 1, duration: 0.6), value: progressPct)
        }
        .frame(height: 26)
    }
}
