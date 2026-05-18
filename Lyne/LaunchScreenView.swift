// Launch splash — ported from app.jsx LaunchScreen.
// Strokes draw on (dim then bright) → wordmark rises → caption → fade out.

import SwiftUI

struct LaunchScreenView: View {
    let onDone: () -> Void

    @State private var dimProgress: CGFloat = 0
    @State private var brightProgress: CGFloat = 0
    @State private var wordmarkIn = false
    @State private var captionIn = false
    @State private var dotPulse = false
    @State private var leaving = false

    var body: some View {
        ZStack {
            Color(hex: "1A1916").ignoresSafeArea()

            VStack(spacing: 28) {
                ZStack {
                    StrokeLine(from: CGPoint(x: 14, y: 50), to: CGPoint(x: 32, y: 18))
                        .trim(from: 0, to: dimProgress)
                        .stroke(Color(hex: "F2EFE8").opacity(0.55),
                                style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    StrokeLine(from: CGPoint(x: 32, y: 50), to: CGPoint(x: 50, y: 18))
                        .trim(from: 0, to: brightProgress)
                        .stroke(Color(hex: "5BC07A"),
                                style: StrokeStyle(lineWidth: 7, lineCap: .round))
                }
                .frame(width: 108, height: 108)

                Text("Leyne")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Color(hex: "F2EFE8"))
                    .opacity(wordmarkIn ? 1 : 0)
                    .offset(y: wordmarkIn ? 0 : 10)
            }

            VStack {
                Spacer()
                HStack(spacing: 8) {
                    Circle().fill(Color(hex: "5BC07A"))
                        .frame(width: 5, height: 5)
                        .opacity(dotPulse ? 1 : 0.35)
                    Text("HEAD DOWN · ON TIME")
                        .font(.system(size: 10, design: .monospaced))
                        .tracking(2.2)
                        .foregroundStyle(Color(hex: "5a544a"))
                }
                .opacity(captionIn ? 1 : 0)
                .padding(.bottom, 56)
            }
        }
        .scaleEffect(leaving ? 1.06 : 1)
        .opacity(leaving ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { dismiss(after: 0.45) }
        .onAppear { run() }
    }

    private func run() {
        withAnimation(.timingCurve(0.5, 0.05, 0.2, 1, duration: 0.6).delay(0.15)) {
            dimProgress = 1
        }
        withAnimation(.timingCurve(0.5, 0.05, 0.2, 1, duration: 0.6).delay(0.5)) {
            brightProgress = 1
        }
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.7).delay(0.9)) {
            wordmarkIn = true
        }
        withAnimation(.easeOut(duration: 0.6).delay(1.35)) { captionIn = true }
        withAnimation(.easeInOut(duration: 1.4).delay(1.6).repeatForever(autoreverses: true)) {
            dotPulse = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.85) { dismiss(after: 0.5) }
    }

    private func dismiss(after: Double) {
        guard !leaving else { return }
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: after)) { leaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + after) { onDone() }
    }
}

/// A straight line in the 68×68 brand viewBox, trimmable for the draw-on.
struct StrokeLine: Shape {
    let from: CGPoint
    let to: CGPoint
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 68.0
        var p = Path()
        p.move(to: CGPoint(x: from.x * s, y: from.y * s))
        p.addLine(to: CGPoint(x: to.x * s, y: to.y * s))
        return p
    }
}
