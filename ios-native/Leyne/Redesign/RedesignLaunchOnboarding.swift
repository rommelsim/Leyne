// Launch splash + platform-aware onboarding (iOS).

import SwiftUI

// MARK: - App mark

/// Gradient rounded-square app mark with the bus + train glyph pair.
struct RDAppMark: View {
    var size: CGFloat = 104
    var glyph: CGFloat = 35
    var corner: CGFloat = 0.34

    var body: some View {
        RoundedRectangle(cornerRadius: size * corner, style: .continuous)
            .fill(LinearGradient(colors: [rdHex("2C72E6"), rdHex("222A38")],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                HStack(spacing: 0) {
                    RDSym("bus.fill", size: glyph, color: .white, weight: .semibold)
                    RDSym("tram.fill", size: glyph, color: .white, weight: .semibold)
                }
            )
            .shadow(color: rdHex("2C72E6").opacity(0.4), radius: 18, x: 0, y: 14)
    }
}

// MARK: - Launch

struct RDLaunchScreen: View {
    let t: RDTokens
    @State private var appeared = false
    @State private var ring = false

    var body: some View {
        ZStack {
            t.surface.ignoresSafeArea()
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .strokeBorder(t.primary, lineWidth: 2)
                        .frame(width: 140, height: 140)
                        .scaleEffect(ring ? 1.7 : 0.7)
                        .opacity(ring ? 0 : 0.5)
                    RDAppMark()
                        .scaleEffect(appeared ? 1 : 0.8)
                        .opacity(appeared ? 1 : 0)
                }
                .frame(width: 140, height: 140)
                Text("SG Transit")
                    .font(rdFont(26, .black))
                    .foregroundStyle(t.onSurface)
                    .padding(.top, 28)
                    .opacity(appeared ? 1 : 0)
            }
            VStack {
                Spacer()
                HStack(spacing: 7) {
                    RDDot(color: t.bus)
                    Text("Live arrivals · LTA DataMall")
                        .font(rdFont(12, .semibold))
                        .foregroundStyle(t.onVariant)
                }
                .padding(.bottom, 46)
                .opacity(appeared ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { appeared = true }
            withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) { ring = true }
        }
    }
}

// MARK: - Buttons

struct RDFilledButton: View {
    let label: String
    var leading: String? = nil
    var trailing: String? = nil
    var height: CGFloat = 56
    var radius: CGFloat = 18
    var fontSize: CGFloat = 16
    let t: RDTokens
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let leading { RDSym(leading, size: fontSize + 4, color: t.onPrimary) }
                Text(label).font(rdFont(fontSize, .bold)).foregroundStyle(t.onPrimary)
                if let trailing { RDSym(trailing, size: fontSize + 5, color: t.onPrimary) }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(t.primary)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct RDGhostButton: View {
    let label: String
    let t: RDTokens
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(rdFont(15, .semibold)).foregroundStyle(t.primary)
                .frame(maxWidth: .infinity).frame(height: 48)
        }
        .buttonStyle(.plain)
    }
}

private struct RDHeroBox: View {
    let symbol: String
    let bg: Color
    let fg: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(bg)
            .frame(width: 84, height: 84)
            .overlay(RDSym(symbol, size: 46, color: fg))
    }
}

// MARK: - Onboarding

struct RDOnboarding: View {
    @ObservedObject var m: RedesignModel
    let t: RDTokens
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ZStack {
            t.surface.ignoresSafeArea()
            VStack {
                stepBody
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
                    .padding(.bottom, 28)
            }
            .id(m.obCurrent)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)))
        }
        .animation(.easeOut(duration: 0.32), value: m.obStep)
        .animation(.easeOut(duration: 0.32), value: m.platform)
    }

    @ViewBuilder private var stepBody: some View {
        switch m.obCurrent {
        case "welcome": welcome
        case "notif": notif
        case "location": location
        case "att": att
        default: done
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            RDAppMark(size: 96, glyph: 31, corner: 0.30)
            Text("Singapore transit,\nat a glance")
                .multilineTextAlignment(.center)
                .font(rdFont(30, .heavy)).foregroundStyle(t.onSurface)
                .padding(.top, 26)
            Text("Live bus & MRT arrivals, disruption alerts, and the fastest way out the door. Free, fast, no account.")
                .multilineTextAlignment(.center)
                .font(rdFont(15)).foregroundStyle(t.onVariant)
                .frame(maxWidth: 300)
                .padding(.top, 14)
            Spacer()
            RDFilledButton(label: "Get started", trailing: "arrow.right", t: t, action: m.obNext)
            Text("Free · no account")
                .font(rdFont(12, .medium)).foregroundStyle(t.onVariant)
                .padding(.top, 14)
        }
    }

    private var notif: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            RDHeroBox(symbol: "bell.fill", bg: t.mrtContainer, fg: t.mrt)
            Text("Never miss your\nbus or a delay")
                .font(rdFont(28, .heavy)).foregroundStyle(t.onSurface).padding(.top, 24)
            Text("Get a heads-up when your ride is arriving and a proactive alert when an MRT line you use goes down.")
                .font(rdFont(15)).foregroundStyle(t.onVariant).padding(.top, 13)
            Spacer()
            RDFilledButton(label: "Allow notifications", height: 54, radius: 17, fontSize: 15.5, t: t,
                           action: { Task { await app.setNotificationsEnabled(true) }; m.obNext() })
            RDGhostButton(label: "Not now", t: t, action: m.obNext).padding(.top, 8)
        }
    }

    private var location: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            RDHeroBox(symbol: "location.north.fill", bg: t.primaryContainer, fg: t.onPrimaryContainer)
            Text("Arrivals around\nyou, instantly")
                .font(rdFont(28, .heavy)).foregroundStyle(t.onSurface).padding(.top, 24)
            Text("We use your location to show the nearest stops and stations the moment you open the app — only while you’re using it.")
                .font(rdFont(15)).foregroundStyle(t.onVariant).padding(.top, 13)
            Spacer()
            RDFilledButton(label: "Allow while using app", leading: "location.fill", height: 54, radius: 17, fontSize: 15.5, t: t,
                           action: { LocationManager.shared.requestAndStart(); m.obNext() })
        }
    }

    private var att: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            RDHeroBox(symbol: "hand.tap.fill", bg: t.scHighest, fg: t.onSurface)
            Text("Keep ads relevant?")
                .font(rdFont(28, .heavy)).foregroundStyle(t.onSurface).padding(.top, 24)
            Text("Allow SG Transit to use app activity for more relevant ads. Ads stay light and unobtrusive either way — your choice.")
                .font(rdFont(15)).foregroundStyle(t.onVariant).padding(.top, 13)
            HStack(spacing: 6) {
                RDSym("iphone", size: 15, color: t.onVariant)
                Text("iOS App Tracking Transparency").font(rdFont(12, .semibold)).foregroundStyle(t.onVariant)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(t.scHigh).clipShape(Capsule())
            .padding(.top, 18)
            Spacer()
            RDFilledButton(label: "Allow tracking", height: 54, radius: 17, fontSize: 15.5, t: t,
                           action: { Task { await AdConsent.gatherThenStart() }; m.obNext() })
            Button(action: { Task { await AdConsent.gatherThenStart() }; m.obNext() }) {
                Text("Ask app not to track").font(rdFont(15, .bold)).foregroundStyle(t.onSurface)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(t.outline, lineWidth: 1))
            }
            .buttonStyle(.plain).padding(.top, 8)
        }
    }

    private var done: some View {
        VStack(spacing: 0) {
            Spacer()
            Circle().fill(t.primaryContainer).frame(width: 96, height: 96)
                .overlay(RDSym("checkmark", size: 50, color: t.primary, weight: .bold))
            Text("You’re all set").font(rdFont(30, .heavy)).foregroundStyle(t.onSurface).padding(.top, 24)
            Text("Showing what’s arriving around you now. Tap any bus to track it live.")
                .multilineTextAlignment(.center)
                .font(rdFont(15)).foregroundStyle(t.onVariant).frame(maxWidth: 280).padding(.top, 13)
            Spacer()
            RDFilledButton(label: "Enter SG Transit", leading: "map.fill", t: t,
                           action: { app.finishOnboarding(); LocationManager.shared.startIfAuthorized(); m.obNext() })
        }
    }
}
