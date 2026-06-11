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
        ZStack(alignment: .bottom) {
            // Backdrop — only when we have weather data
            if let snap = ws.snapshot {
                WeatherBackdrop(bucket: snap.bucket, isDark: t.isDark)
            }

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
        }
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

// MARK: - WeatherBackdrop

/// A subtle greyscale gradient behind the top hero area.
/// Condition → opacity tuning (never more than 0.12 in light, 0.18 in dark):
///   clearDay   — very faint warm-light illusion via near-white top
///   clearNight — deep-black fade
///   cloudy     — mid-grey
///   rain       — darker grey, slightly stronger
///
/// The gradient fades completely to `.clear` at the bottom so it blends
/// seamlessly into the card content beneath the header.
struct WeatherBackdrop: View {
    let bucket: WeatherBucket
    let isDark: Bool

    var body: some View {
        LinearGradient(
            colors: [topColor, .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var topColor: Color {
        // All values are greyscale opacity-only — zero hue.
        let opacity: Double
        switch bucket {
        case .clearDay:
            opacity = isDark ? 0.08 : 0.06
        case .clearNight:
            opacity = isDark ? 0.16 : 0.08
        case .cloudy:
            opacity = isDark ? 0.12 : 0.07
        case .rain:
            opacity = isDark ? 0.18 : 0.10
        }
        // Dark mode: white tint; light mode: black tint — stays monochrome.
        return (isDark ? Color.white : Color.black).opacity(opacity)
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
