// Launch splash — a quick, on-brand transit trace: an indigo vehicle runs the
// line from a green stop to a red one (echoing the bus + MRT app icon), the
// "SG Transit" wordmark rises, then the whole thing lifts away. Tappable to skip.

import SwiftUI

struct LaunchScreenView: View {
    let onDone: () -> Void

    private let trackW: CGFloat = 188
    private let vehicleW: CGFloat = 24

    @State private var progress: CGFloat = 0
    @State private var wordmarkIn = false
    @State private var captionIn = false
    @State private var arrived = false
    @State private var dotPulse = false
    @State private var leaving = false

    private let indigo = Color(hex: "6E6CF0")
    private let busGreen = Color(hex: "2FB85B")
    private let trainRed = Color(hex: "E5251C")

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "1C1F26"), Color(hex: "0C0D11")],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                routeTrace
                Text("SG Transit")
                    .font(.system(size: 33, weight: .semibold))
                    .foregroundStyle(Color(hex: "F4F2EC"))
                    .opacity(wordmarkIn ? 1 : 0)
                    .offset(y: wordmarkIn ? 0 : 12)
            }

            VStack {
                Spacer()
                HStack(spacing: 8) {
                    Circle().fill(indigo)
                        .frame(width: 5, height: 5)
                        .opacity(dotPulse ? 1 : 0.3)
                    Text("HEAD DOWN · ON TIME")
                        .font(.system(size: 10, design: .monospaced))
                        .tracking(2.2)
                        .foregroundStyle(Color(hex: "6B6459"))
                }
                .opacity(captionIn ? 1 : 0)
                .padding(.bottom, 56)
            }
        }
        .scaleEffect(leaving ? 1.05 : 1)
        .opacity(leaving ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { dismiss(after: 0.4) }
        .onAppear { run() }
    }

    /// The line + its two end-stops + the indigo vehicle tracing across it.
    private var routeTrace: some View {
        ZStack(alignment: .leading) {
            // Faint base track.
            Capsule().fill(Color.white.opacity(0.10))
                .frame(width: trackW, height: 6)
            // Indigo trail traced behind the vehicle.
            Capsule().fill(LinearGradient(colors: [indigo.opacity(0.7), indigo],
                                          startPoint: .leading, endPoint: .trailing))
                .frame(width: max(6, progress * trackW), height: 6)
            // End stops — green (bus) at the start, red (MRT) at the destination.
            endStop(busGreen).offset(x: -3)
            endStop(trainRed).offset(x: trackW - 11)
                .scaleEffect(arrived ? 1.25 : 1)
            // The vehicle.
            Capsule().fill(Color.white)
                .frame(width: vehicleW, height: 12)
                .overlay(Capsule().fill(indigo).padding(2.5))
                .shadow(color: indigo.opacity(0.7), radius: 6, y: 0)
                .offset(x: progress * (trackW - vehicleW))
        }
        .frame(width: trackW, height: 16)
    }

    private func endStop(_ color: Color) -> some View {
        Circle().fill(color)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 2.5))
            .shadow(color: color.opacity(0.6), radius: 4)
    }

    private func run() {
        withAnimation(.timingCurve(0.45, 0, 0.2, 1, duration: 1.0).delay(0.2)) {
            progress = 1
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(1.15)) {
            arrived = true
        }
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.6).delay(0.85)) {
            wordmarkIn = true
        }
        withAnimation(.easeOut(duration: 0.5).delay(1.25)) { captionIn = true }
        withAnimation(.easeInOut(duration: 1.4).delay(1.4).repeatForever(autoreverses: true)) {
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
