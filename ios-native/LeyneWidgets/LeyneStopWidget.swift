// Home Screen widget: live next-bus arrivals for a pinned stop (Small only).
// Reads as a snippet of the app — same monochrome ink surface, monospacedDigit
// ETAs — so muscle memory transfers from in-app PinnedCardView.
//
// Self-contained: the widget extension can't import the app module. It
// reads pinned stops from the shared App Group and calls LTA DataMall
// directly (same live source the app uses).

import WidgetKit
import SwiftUI
import AppIntents
import UIKit

// Palette, App Group readers, the WLTA client, helpers, and the shared UI
// atoms (WServiceBadge, WEtaColumns) all live in WidgetShared.swift.

// ─── Widget configuration intent ─────────────────────────
// Lets the user pick which pinned stop powers the widget.
struct StopChoice: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Pinned Stop"
    // No "STOP <code>" subtitle — the stop name is the only identity that
    // matters to the user; the 5-digit code is an LTA artifact.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
    static var defaultQuery = StopChoiceQuery()
}

struct StopChoiceQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [StopChoice] {
        loadPinnedStops().filter { identifiers.contains($0.id) }
            .map { StopChoice(id: $0.id, name: $0.name) }
    }
    func suggestedEntities() async throws -> [StopChoice] {
        loadPinnedStops().map { StopChoice(id: $0.id, name: $0.name) }
    }
    func defaultResult() async -> StopChoice? {
        loadPinnedStops().first.map { StopChoice(id: $0.id, name: $0.name) }
    }
}

struct SelectStopIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Pick stop"
    static var description = IntentDescription(
        "Choose which pinned stop this widget shows."
    )

    @Parameter(title: "Stop")
    var stop: StopChoice?
}

// ─── Timeline entry ──────────────────────────────────────
struct StopBlock: Hashable {
    let name: String
    let code: String
    let rows: [WLTA.Row]
}

struct StopEntry: TimelineEntry {
    let date: Date
    let primary: StopBlock?
}

struct StopProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StopEntry {
        StopEntry(
            date: .now,
            primary: StopBlock(name: "Bef Bishan Stn", code: "53061",
                               rows: [.init(id: "88", eta1: 2, eta2: 9),
                                      .init(id: "156", eta1: 9, eta2: 19),
                                      .init(id: "410", eta1: 4, eta2: 16)])
        )
    }

    func snapshot(for configuration: SelectStopIntent, in context: Context) async -> StopEntry {
        await entry(for: configuration)
    }

    func timeline(for configuration: SelectStopIntent, in context: Context)
        async -> Timeline<StopEntry> {
        let e = await entry(for: configuration)
        // Refresh roughly every minute (system may throttle further).
        let next = Date().addingTimeInterval(60)
        return Timeline(entries: [e], policy: .after(next))
    }

    private func entry(for configuration: SelectStopIntent) async -> StopEntry {
        let pins = loadPinnedStops()
        // Primary: the configured stop, falling back to the first pin.
        let primaryPick = configuration.stop
            ?? pins.first.map { StopChoice(id: $0.id, name: $0.name) }
        let rows = primaryPick != nil
            ? await WLTA.arrivals(stop: primaryPick!.id)
            : []
        let p = primaryPick.map { StopBlock(name: $0.name, code: $0.id, rows: rows) }
        return StopEntry(date: .now, primary: p)
    }
}

// Helpers (etaLabel / schedPrefix / stopURL) and the WServiceBadge /
// WEtaColumns atoms live in WidgetShared.swift.

// ─── Small widget — hero next-bus card ───────────────────
// Layout intent: collapse one full pinned card down to its most useful
// signal. The stop name sits at the top (no STOP code — the user picked
// it; the code is plumbing). The next bus's number + ETA is the hero;
// the following bus is a thin "then X" line; remaining services collapse
// to a "+N" chip.
private struct SmallStopView: View {
    let block: StopBlock?

    var body: some View {
        if let block, let next = block.rows.first {
            let arriving = next.mon1 && (next.eta1 ?? 99) <= 1
            VStack(alignment: .leading, spacing: 0) {
                Text(block.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(wFg).lineLimit(1)

                Spacer(minLength: 4)

                Text(next.id)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(wFg)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(schedPrefix(next.mon1, next.eta1) + etaLabel(next.eta1))
                        .font(.system(size: etaLabel(next.eta1) == "Arr" ? 30 : 40,
                                      weight: arriving ? .bold : .medium)
                              .monospacedDigit())
                        .foregroundStyle(wFg)
                        // Arriving: ink weight (bold) is the signal — no hue.
                        // Keep widgetAccentable so StandBy/Lock Screen can tint.
                        .widgetAccentable(arriving)
                    if etaLabel(next.eta1) != "Arr" {
                        Text("min")
                            .font(.system(size: 13)).foregroundStyle(wDim)
                    }
                }
                .contentTransition(.numericText(countsDown: true))

                Spacer(minLength: 0)

                HStack {
                    if let eta2 = next.eta2 {
                        Text("then \(etaLabel(eta2))\(eta2 <= 0 ? "" : "m")")
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(wDim)
                    }
                    Spacer()
                    if block.rows.count > 1 {
                        Text("+\(block.rows.count - 1)")
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(wFaint)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .overlay(Capsule().stroke(wLine, lineWidth: 1))
                    }
                }
            }
            .widgetURL(stopURL(block.code))
        } else {
            EmptyStopView()
        }
    }
}

// ─── Empty state ─────────────────────────────────────────
private struct EmptyStopView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 18))
                .foregroundStyle(wDim)
            Text("Pin a stop in Leyne")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(wFg)
            Text("Long-press the widget to choose one")
                .font(.system(size: 10))
                .foregroundStyle(wDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ─── Top-level widget view ───────────────────────────────
private struct StopWidgetView: View {
    let entry: StopEntry

    var body: some View {
        SmallStopView(block: entry.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(wBg, for: .widget)
    }
}

// ─── Widget configuration ────────────────────────────────
struct LeyneStopWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.leyne.Leyne.StopWidget",
                               intent: SelectStopIntent.self,
                               provider: StopProvider()) { entry in
            StopWidgetView(entry: entry)
        }
        .configurationDisplayName("Pinned Stop")
        .description("Live arrivals for a stop you pinned in Leyne.")
        .supportedFamilies([.systemSmall])
    }
}
