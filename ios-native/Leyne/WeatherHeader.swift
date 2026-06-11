// WeatherHeader — monochrome weather + time hero for SoftHomeView.
//
// Layout (top → bottom):
//   [greeting + clock]  e.g. "Good morning · 08:41"
//   [temp · condition · rain hint]  e.g. "29° · Partly Cloudy · rain ~5pm"
//   [WeatherKit attribution link]   tiny legal line below the readout
//
// The whole block sits behind a subtle greyscale vertical gradient whose
// opacity shifts by condition bucket (clear / cloudy / rain / night).
// Strict monochrome: no blue sky, no green, no coloured gradients.
// Colours come exclusively from the app's Theme tokens (fg / dim / faint).
//
// Graceful zero state: when `WeatherService.shared.snapshot == nil` the
// weather readout and backdrop are fully omitted — greeting + clock still
// render so the header never disappears.

import SwiftUI
import CoreLocation

// MARK: - WeatherHeader

struct WeatherHeader: View {
    let t: Theme

    @ObservedObject private var ws = WeatherService.shared
    @EnvironmentObject private var loc: LocationManager

    var body: some View {
        // Just the readout. The ambient weather wash lives at the SoftHomeView
        // root (a sibling of the ScrollView) so it can ignore the safe area
        // cleanly and stay put as content scrolls — see `WeatherBackdrop`.
        // Anchoring it here, inside the scrolling header, is what made it read
        // as a discrete bar.
        VStack(alignment: .leading, spacing: 6) {
            greetingRow
            if let snap = ws.snapshot {
                weatherRow(snap)
                if let attrURL = ws.attributionURL {
                    attributionLine(url: attrURL)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .onAppear {
            if let loc = loc.location {
                ws.fetchIfNeeded(location: loc)
            }
            ws.startPeriodicRefresh {
                LocationManager.shared.location
            }
        }
        .onChange(of: loc.location) { _, newLoc in
            if let l = newLoc { ws.fetchIfNeeded(location: l) }
        }
    }

    // MARK: Sub-views

    /// "Good morning · 08:41" — clock via TimelineView for minute-accurate
    /// updates without a manual Timer or @State date.
    private var greetingRow: some View {
        TimelineView(.everyMinute) { ctx in
            HStack(spacing: 6) {
                Text(greeting(for: ctx.date))
                    .font(t.sans(13, weight: .medium))
                    .foregroundStyle(t.dim)
                Text("·")
                    .font(t.sans(13))
                    .foregroundStyle(t.faint)
                    .accessibilityHidden(true)
                Text(timeString(ctx.date))
                    .font(t.mono(13, weight: .semibold))
                    .foregroundStyle(t.fg)
                    // Minute rolls over like the system clock instead of cutting.
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.4), value: timeString(ctx.date))
            }
        }
    }

    /// "{temp}° · {condition} [· {rain hint}]" + SF Symbol glyph.
    @ViewBuilder
    private func weatherRow(_ snap: WeatherSnapshot) -> some View {
        HStack(spacing: 8) {
            Image(systemName: snap.symbolName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(t.fg.opacity(0.85))
                .accessibilityHidden(true)

            HStack(spacing: 0) {
                Text("\(snap.tempC)°")
                    .font(t.mono(18, weight: .semibold))
                    .foregroundStyle(t.fg)
                Text("  ·  \(snap.conditionLabel)")
                    .font(t.sans(15))
                    .foregroundStyle(t.dim)
                if let hint = snap.rainHint {
                    Text("  ·  \(hint)")
                        .font(t.sans(15))
                        .foregroundStyle(t.fg)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(weatherA11yLabel(snap))
    }

    /// Tiny WeatherKit attribution link — required by Apple's ToS.
    /// Rendered as a system link in `t.faint` so it's present but unobtrusive.
    private func attributionLine(url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 3) {
                Image(systemName: "info.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(t.faint)
                    .accessibilityHidden(true)
                Text("Weather")
                    .font(t.mono(9))
                    .foregroundStyle(t.faint)
                    .tracking(0.3)
            }
        }
        .accessibilityLabel("WeatherKit data source")
    }

    // MARK: Helpers

    private func greeting(for date: Date) -> String {
        let h = Calendar.current.component(.hour, from: date)
        switch h {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Good night"
        }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func weatherA11yLabel(_ snap: WeatherSnapshot) -> String {
        var parts = ["\(snap.tempC) degrees Celsius", snap.conditionLabel]
        if let hint = snap.rainHint { parts.append(hint) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - WeatherAmbientLayer

/// A barely-there ambient wash pinned to the very top of the screen, fading
/// to clear at ~40 % of the height — fully gone before the first card.
///
/// Mounted at the SoftHomeView root (a sibling of the ScrollView) with
/// `.ignoresSafeArea()`, so it fills full-bleed from above the status bar and
/// stays put as content scrolls — ambient top lighting, not a band tied to
/// the header.
///
/// Two stacked ramps:
///   1. the original greyscale lightness wash (opacity varies by bucket), and
///   2. a *faint* condition hue — warm amber when clear by day, a cool slate
///      shift in rain — at opacities below the threshold of conscious notice.
/// The hue is deliberately NOT a saturated MRT-adjacent colour: amber sits at
/// ≤6 % opacity and the rain tint is a desaturated grey-cool, so the palette
/// stays effectively monochrome while the screen feels like *now*.
struct WeatherAmbientLayer: View {
    let bucket: WeatherBucket?
    let isDark: Bool

    var body: some View {
        if let bucket {
            ZStack(alignment: .top) {
                ramp(greyColor(bucket))
                if let hue = hueColor(bucket) {
                    ramp(hue)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.easeInOut(duration: 0.8), value: isDark)
        }
    }

    private func ramp(_ color: Color) -> some View {
        LinearGradient(
            stops: [
                .init(color: color, location: 0.0),
                .init(color: .clear, location: 0.40)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Greyscale lightness wash — zero hue, the pre-existing backdrop ramp.
    private func greyColor(_ bucket: WeatherBucket) -> Color {
        let opacity: Double
        switch bucket {
        case .clearDay:   opacity = isDark ? 0.07  : 0.045
        case .clearNight: opacity = isDark ? 0.12  : 0.06
        case .cloudy:     opacity = isDark ? 0.09  : 0.055
        case .rain:       opacity = isDark ? 0.13  : 0.07
        }
        return (isDark ? Color.white : Color.black).opacity(opacity)
    }

    /// The whisper of hue. Clear day = warm amber; rain = cool slate.
    /// Cloudy and night stay pure monochrome (the near-black bg already
    /// reads as night).
    private func hueColor(_ bucket: WeatherBucket) -> Color? {
        switch bucket {
        case .clearDay:
            return Color(hex: "FF9F0A").opacity(isDark ? 0.04 : 0.06)
        case .rain:
            return Color(hex: "5E6573").opacity(isDark ? 0.06 : 0.05)
        case .clearNight, .cloudy:
            return nil
        }
    }
}

// MARK: - Preview helper (not for production use)

#if DEBUG
private extension WeatherHeader {
    static func preview(isDark: Bool) -> some View {
        let t = isDark ? Theme.dark : Theme.light
        return WeatherHeader(t: t)
            .environmentObject(LocationManager.shared)
            .background(t.bg)
    }
}

#Preview("Weather Header — Dark") {
    WeatherHeader.preview(isDark: true)
}

#Preview("Weather Header — Light") {
    WeatherHeader.preview(isDark: false)
}
#endif
