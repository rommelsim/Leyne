// Home Screen widgets: live next-bus arrivals for one (Small/Medium) or two
// (Large) pinned stops. The widget reads as a snippet of the app — the same
// monochrome surfaces, mono digits, and arrival-green signal as the app's
// Theme — so muscle memory transfers from in-app PinnedCardView.
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
// Lets the user pick which pinned stop powers the widget. The Large
// family supports a second stop for the AM/PM commute layout.
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
        "Choose which pinned stop this widget shows. The Large size can show a second stop too."
    )

    @Parameter(title: "Stop")
    var stop: StopChoice?

    @Parameter(title: "Second stop (Large only)")
    var stop2: StopChoice?
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
    let secondary: StopBlock?     // populated only for Large
}

struct StopProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StopEntry {
        StopEntry(
            date: .now,
            primary: StopBlock(name: "Bef Bishan Stn", code: "53061",
                               rows: [.init(id: "88", eta1: 2, eta2: 9),
                                      .init(id: "156", eta1: 9, eta2: 19),
                                      .init(id: "410", eta1: 4, eta2: 16)]),
            secondary: StopBlock(name: "Opp Blk 211", code: "53241",
                                 rows: [.init(id: "174", eta1: 9, eta2: 21),
                                        .init(id: "88", eta1: 17, eta2: 28)])
        )
    }

    func snapshot(for configuration: SelectStopIntent, in context: Context) async -> StopEntry {
        await entry(for: configuration, family: context.family)
    }

    func timeline(for configuration: SelectStopIntent, in context: Context)
        async -> Timeline<StopEntry> {
        let e = await entry(for: configuration, family: context.family)
        // Refresh roughly every minute (system may throttle further).
        let next = Date().addingTimeInterval(60)
        return Timeline(entries: [e], policy: .after(next))
    }

    private func fetchRows(for pick: StopChoice?) async -> [WLTA.Row] {
        guard let pick else { return [] }
        return await WLTA.arrivals(stop: pick.id)
    }

    private func entry(for configuration: SelectStopIntent,
                       family: WidgetFamily) async -> StopEntry {
        let pins = loadPinnedStops()
        // Primary: the configured stop, falling back to the first pin.
        let primaryPick = configuration.stop
            ?? pins.first.map { StopChoice(id: $0.id, name: $0.name) }
        // Secondary: only the Large family uses it. Falls back to the next
        // distinct pin so the widget is useful without configuration.
        let secondaryPick: StopChoice? = (family == .systemLarge)
            ? (configuration.stop2
               ?? pins.first(where: { $0.id != primaryPick?.id })
                   .map { StopChoice(id: $0.id, name: $0.name) })
            : nil

        async let pRows = fetchRows(for: primaryPick)
        async let sRows = fetchRows(for: secondaryPick)
        let primaryRows = await pRows
        let secondaryRows = await sRows

        let p = primaryPick.map {
            StopBlock(name: $0.name, code: $0.id, rows: primaryRows)
        }
        let s = secondaryPick.map {
            StopBlock(name: $0.name, code: $0.id, rows: secondaryRows)
        }
        return StopEntry(date: .now, primary: p, secondary: s)
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
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(wFg)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(schedPrefix(next.mon1, next.eta1) + etaLabel(next.eta1))
                        .font(.system(size: etaLabel(next.eta1) == "Arr" ? 30 : 40,
                                      weight: .medium, design: .monospaced))
                        .foregroundStyle(arriving ? wLive : wFg)
                        // Arriving is the primary signal — keep it tinted (not
                        // desaturated) under StandBy / Lock Screen accenting.
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
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(wDim)
                    }
                    Spacer()
                    if block.rows.count > 1 {
                        Text("+\(block.rows.count - 1)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
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

// ─── Service row — matches in-app PinnedCardView ServiceRow ─
private struct WServiceRow: View {
    let row: WLTA.Row
    // Arriving = imminent AND live. A scheduled (non-GPS) guess never gets
    // the confident mint-arriving treatment, even at <=1 min.
    private var arriving: Bool { row.mon1 && (row.eta1 ?? 99) <= 1 }

    var body: some View {
        HStack(spacing: 9) {
            // Mint-filled service badge — quotes the in-app V2/ServiceBadge so
            // a glance at the widget reads as a glance at the app.
            WServiceBadge(no: row.id, compact: true)

            Spacer(minLength: 0)

            // Hero ETA + up to two follow-up columns ("2  18  35"), matching
            // the Stop Arrivals mockup.
            WEtaColumns(row: row, heroSize: 22)
        }
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(arriving ? wLiveBg : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// ─── Medium widget — full stop card ──────────────────────
// A direct visual quote of in-app PinnedCardView: stop name header,
// thin divider, up to 3 ServiceRows. Tapping any row could be routed
// to the bus's detail via deep link in a later pass.
private struct MediumStopView: View {
    let block: StopBlock?

    var body: some View {
        if let block {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(wLive)
                        .widgetAccentable()
                    Text(block.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(wFg)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(wFaint)
                }
                Rectangle().fill(wLine).frame(height: 1).padding(.top, 6)

                if block.rows.isEmpty {
                    Spacer()
                    Text("No live arrivals")
                        .font(.system(size: 12)).foregroundStyle(wDim)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    VStack(spacing: 2) {
                        ForEach(Array(block.rows.prefix(3))) { r in
                            WServiceRow(row: r)
                        }
                    }
                    .padding(.top, 4)
                    Spacer(minLength: 0)
                }
            }
            .widgetURL(stopURL(block.code))
        } else {
            EmptyStopView()
        }
    }
}

// ─── Large widget — AM/PM commute layout ─────────────────
// Two stop blocks stacked. The user picks both via the widget's edit
// sheet (or the widget auto-fills from the first two pins).
private struct LargeCommuteView: View {
    let primary: StopBlock?
    let secondary: StopBlock?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let p = primary {
                StopChunk(block: p, maxRows: secondary == nil ? 5 : 3)
            }
            if primary != nil && secondary != nil {
                Rectangle().fill(wLine).frame(height: 1)
            }
            if let s = secondary {
                StopChunk(block: s, maxRows: 3)
            }
            if primary == nil && secondary == nil { EmptyStopView() }
            Spacer(minLength: 0)
        }
        .widgetURL(stopURL(primary?.code ?? ""))
    }

    private struct StopChunk: View {
        let block: StopBlock
        let maxRows: Int
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 10)).foregroundStyle(wLive)
                        .widgetAccentable()
                    Text(block.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(wFg).lineLimit(1)
                    Spacer(minLength: 0)
                }
                if block.rows.isEmpty {
                    Text("No live arrivals")
                        .font(.system(size: 11)).foregroundStyle(wDim)
                } else {
                    VStack(spacing: 2) {
                        ForEach(Array(block.rows.prefix(maxRows))) { r in
                            WServiceRow(row: r)
                        }
                    }
                }
            }
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
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallStopView(block: entry.primary)
            case .systemMedium:
                MediumStopView(block: entry.primary)
            case .systemLarge:
                LargeCommuteView(primary: entry.primary, secondary: entry.secondary)
            default:
                MediumStopView(block: entry.primary)
            }
        }
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
        .description("Live arrivals for a stop you pinned in Leyne. Large size shows two stops.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
