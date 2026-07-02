// Launch splash — WhereSia departure board.
//
// Board rules draw across → eyebrow + wordmark rise → the six official line
// colours stagger in (the app's "colour = data" signature) → live dot pulses
// → fade out. Theme-aware (follows system light/dark); Reduce Motion gets a
// still frame and an earlier dismiss. Tap anywhere to skip.

import SwiftUI

struct LaunchScreenView: View {
    let onDone: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var ruleProgress: CGFloat = 0
    @State private var eyebrowIn = false
    @State private var wordmarkIn = false
    @State private var bulletsIn = false
    @State private var captionIn = false
    @State private var dotPulse = false
    @State private var leaving = false

    private var ws: WSTheme { .resolve(dark: colorScheme == .dark) }
    private static let lineOrder = ["NS", "EW", "NE", "CC", "DT", "TE"]

    var body: some View {
        ZStack {
            ws.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                rule
                VStack(spacing: 10) {
                    Text("SINGAPORE · BUS & MRT")
                        .font(ws.mono(11, weight: .semibold)).tracking(2.2)
                        .foregroundStyle(ws.dim)
                        .opacity(eyebrowIn ? 1 : 0)
                        .offset(y: eyebrowIn || reduceMotion ? 0 : 8)
                    Text("WhereSia")
                        .font(ws.sans(38, weight: .heavy))
                        .foregroundStyle(ws.text)
                        .opacity(wordmarkIn ? 1 : 0)
                        .offset(y: wordmarkIn || reduceMotion ? 0 : 14)
                    HStack(spacing: 7) {
                        ForEach(Array(Self.lineOrder.enumerated()), id: \.offset) { i, code in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(WSLine.colors[code] ?? WSLine.lrt)
                                .frame(width: 22, height: 5)
                                .opacity(bulletsIn ? 1 : 0)
                                .offset(y: bulletsIn || reduceMotion ? 0 : 6)
                                .animation(reduceMotion ? nil :
                                    .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.45)
                                        .delay(0.95 + Double(i) * 0.06),
                                    value: bulletsIn)
                        }
                    }
                    .padding(.top, 6)
                }
                .padding(.vertical, 26)
                rule
            }
            .padding(.horizontal, 44)

            VStack {
                Spacer()
                HStack(spacing: 8) {
                    Circle().fill(ws.accentSoft)
                        .frame(width: 5, height: 5)
                        .opacity(dotPulse ? 1 : 0.35)
                    Text("LIVE ARRIVALS · SINGAPORE")
                        .font(ws.mono(10)).tracking(2)
                        .foregroundStyle(ws.dim)
                }
                .opacity(captionIn ? 1 : 0)
                .padding(.bottom, 56)
            }
        }
        .scaleEffect(leaving && !reduceMotion ? 1.04 : 1)
        .opacity(leaving ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { dismiss(after: 0.35) }
        .onAppear { run() }
    }

    /// A board rule that draws from leading to trailing.
    private var rule: some View {
        GeometryReader { geo in
            Rectangle().fill(ws.rule)
                .frame(width: geo.size.width * ruleProgress, height: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 1)
    }

    private func run() {
        if reduceMotion {
            ruleProgress = 1
            eyebrowIn = true; wordmarkIn = true; bulletsIn = true
            captionIn = true; dotPulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { dismiss(after: 0.3) }
            return
        }
        withAnimation(.timingCurve(0.5, 0.05, 0.2, 1, duration: 0.55).delay(0.1)) { ruleProgress = 1 }
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.55).delay(0.45)) { eyebrowIn = true }
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.65).delay(0.65)) { wordmarkIn = true }
        bulletsIn = true   // each capsule animates with its own staggered delay
        withAnimation(.easeOut(duration: 0.5).delay(1.3)) { captionIn = true }
        withAnimation(.easeInOut(duration: 1.2).delay(1.5).repeatForever(autoreverses: true)) { dotPulse = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { dismiss(after: 0.45) }
    }

    private func dismiss(after: Double) {
        guard !leaving else { return }
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: after)) { leaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + after) { onDone() }
    }
}
