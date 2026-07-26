// WhereSia — MRT station (screen 5).
//
// Soft Blue "4b" (docs/soft-blue-design.md): one white card per line serving
// the station (line identity stays on the LineBullet only — colour is never
// borrowed for status), each showing both directions — platform + live
// crowd, never a fabricated per-direction countdown, because PCDRealTime
// only gives a station-wide reading and LTA has no per-direction MRT ETA
// feed — then a 5-station line-map strip centred on this station (tap a
// neighbour to jump straight to it). A disruption surfaces as a
// SoftDisruptionChip row inside the affected line's card, never a glow edge
// or a pulsing badge (both retired). A lift-maintenance card surfaces only
// when FacilitiesMaintenance actually reports one here. Below that: the bus
// stops physically at this station (unchanged data, restyled to the row
// anatomy) and the real PCDForecast crowd forecast, restyled soft-blue and
// kept whisper-quiet — never a banner (feedback_timely_over_honest). No
// exits card: the app carries no station-exit dataset, so one is never
// invented.
//
// `wsHeaderBar` chrome + `titleCollapsed` mechanics are kept AS-IS — bucket B
// system chrome, a different collapse idiom from WSBusStopView's, not to be
// unified with it.

import SwiftUI
import CoreLocation

struct WSMrtStationView: View {
    let station: MrtGeoStation
    var onBack: () -> Void

    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push

    @State private var titleCollapsed = false
    @State private var forecast: [ForecastPoint] = []

    struct ForecastPoint: Identifiable {
        let id = UUID()
        let time: String
        let fraction: CGFloat
        let isNow: Bool
        let level: CrowdLevel
    }

    private var lines: [MRTLine] {
        var out: [MRTLine] = []
        for c in station.codes { if let l = wsLine(forStationCode: c), !out.contains(l) { out.append(l) } }
        return out
    }

    private var crowdNow: CrowdLevel { store.wsCrowd(for: station) ?? .unknown }

    /// The first live disruption affecting `line`, if any.
    private func alert(for line: MRTLine) -> TrainAlert? {
        store.trainAlerts.first { $0.line == line }
    }

    /// Lift outages LTA has tagged against this station name.
    private var liftsHere: [LiftMaintenance] {
        let name = station.name.lowercased()
        return store.liftMaintenance.filter { $0.stationName.lowercased() == name }
    }

    /// Straight-line distance to the user, when location is known. Never
    /// fabricated — simply omitted without a fix.
    private var distanceCaption: String? {
        guard let loc = LocationManager.shared.location else { return nil }
        let d = haversine(loc.coordinate.latitude, loc.coordinate.longitude, station.lat, station.lon)
        // Beyond ~50 km "away" stops being navigation info — omit, same as
        // when location is unknown.
        guard d <= 50_000 else { return nil }
        return "\(fmtDistance(Int(d.rounded()))) away"
    }

    /// "2 min walk · 51m away" — how far this station is, in the app's
    /// standard order. Both halves or neither: a walk time without a distance
    /// (or the reverse) is the vaguer half of the same fact.
    private var proximityLine: String? {
        guard let loc = LocationManager.shared.location else { return nil }
        let d = haversine(loc.coordinate.latitude, loc.coordinate.longitude,
                          station.lat, station.lon)
        guard d <= 50_000 else { return nil }
        let walk = max(1, Int((d / 80).rounded()))
        return "\(walk) min walk · \(fmtDistance(Int(d.rounded()))) away"
    }

    /// How long the navigation push takes to settle. Entrance animations wait
    /// this out, otherwise they play behind the slide and are never seen.
    private let pushSettle: Double = 0.28

    /// Bus stops physically at/around the station (≤ 400 m walk).
    private var nearbyStops: [(stop: LTABusStop, distanceM: Int)] {
        store.wsStopsNear(CLLocationCoordinate2D(latitude: station.lat, longitude: station.lon), limit: 3)
            .filter { $0.distanceM <= 400 }
    }

    var body: some View {
        // m.tick keeps the disruption/crowd reads advancing under @Observable's
        // per-property tracking (see original file's note on this pattern).
        let _ = m.tick
        ScrollView {
            // The entrance is delayed past the push transition (owner
            // 2026-07-25: "no animation for this mrt view too"). It WAS
            // animating — the whole stagger just played underneath the
            // navigation slide, so by the time the screen arrived it had
            // already finished. `pushSettle` holds it until the push lands.
            VStack(spacing: 14) {
                header.padding(.top, 12).wsEntrance(delay: pushSettle)
                ForEach(Array(lines.enumerated()), id: \.element) { i, line in
                    lineCard(line)
                        .padding(.horizontal, 18)
                        .wsEntrance(delay: pushSettle + Double(i + 1) * 0.07)
                }
                ForEach(Array(liftsHere.enumerated()), id: \.element.id) { i, lift in
                    liftCard(lift)
                        .padding(.horizontal, 18)
                        .wsEntrance(delay: pushSettle + Double(lines.count + i + 1) * 0.07)
                }
                busSection
                    .padding(.horizontal, 18)
                    .wsEntrance(delay: pushSettle + Double(lines.count + liftsHere.count + 1) * 0.07)
                forecastSection
                    .padding(.horizontal, 18)
                    .wsEntrance(delay: pushSettle + Double(lines.count + liftsHere.count + 2) * 0.07)
                // `wsDetailAdBanner` is a bottom safeAreaInset — the scroll
                // view already clears it, so this is breathing room only.
                Color.clear.frame(height: 12)
            }
        }
        .onScrollGeometryChange(for: Bool.self) { g in
            g.contentOffset.y + g.contentInsets.top > 44
        } action: { _, isPast in
            titleCollapsed = isPast
        }
        .wsDetailAdBanner()
        // NO screen-level .wsEntrance() here: it faded the whole scroll view
        // in at once, which cancelled out the per-card stagger below it.
        .background(SoftBlue.bg.ignoresSafeArea())
        .wsHeaderBar(eyebrow: "MRT station", title: station.name,
                     collapsed: titleCollapsed, onBack: onBack) {
            // Favourite = star; blue is the one accent (§1) — the app's
            // interactive/live-surface colour — for the "saved" state,
            // rather than reintroducing a colour outside the 4b palette.
            Button { m.toggleMrtSaved(station) } label: {
                Image(systemName: m.isMrtSaved(station) ? "star.fill" : "star")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(m.isMrtSaved(station) ? SoftBlue.blue : SoftBlue.ink.opacity(0.75))
                    .frame(width: 34, height: 34)
                    .background(SoftBlue.card, in: Circle())
                    .shadow(color: SoftBlue.shadow, radius: 6, y: 3)
                    .contentShape(Circle())
            }
            .buttonStyle(SoftPressStyle())
            .accessibilityLabel(m.isMrtSaved(station) ? "Remove from favourites" : "Save station")
        }
        .sensoryFeedback(.impact(weight: .light), trigger: m.isMrtSaved(station))
        .onAppear {
            store.wsWarmCrowd(for: [station])
            store.refreshLiftMaintenanceIfStale()
            for l in lines { store.refreshForecast(line: l) }
            for item in nearbyStops { store.ensureArrivals(stop: item.stop.BusStopCode, silent: true) }
            loadForecast()
        }
    }

    // MARK: header — name · "MRT" · line badges · distance

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Station codes sit INLINE with the name, not on their own row
            // below it. Stacked, the amber CC20 pill landed ~30pt above the
            // amber CCL pill on the first line card and the two read as one
            // fighting pair (owner 2026-07-25, "CCL and CC20 very near each
            // other"). On the title line the code is unmistakably part of the
            // station's identity, and the card's line badge is the only badge
            // in its own band.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(station.name).font(ws.sans(22, weight: .bold)).foregroundStyle(SoftBlue.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing: 5) {
                    ForEach(station.codes, id: \.self) { LineBullet(code: $0) }
                }
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                Text("MRT").font(ws.sans(13, weight: .medium)).foregroundStyle(SoftBlue.sub)
                Spacer(minLength: 0)
            }

            // Distance belongs TO the station, so it sits under the station's
            // name as its property. It used to be a centred caption ABOVE the
            // name, which dropped "51m away" into the gap between the nav
            // bar's "MRT STATION" eyebrow and the title — text stranded
            // between two things it belonged to neither of (owner
            // 2026-07-26). Same "N min walk · Xm" wording the bus stop card
            // and the widget use.
            if let proximity = proximityLine {
                Text(proximity)
                    .font(ws.sans(12.5, weight: .medium)).monospacedDigit()
                    .foregroundStyle(SoftBlue.sub)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
    }

    // MARK: per-line card

    @ViewBuilder
    private func lineCard(_ line: MRTLine) -> some View {
        let disrupted = alert(for: line)
        let seq = lineSequence(for: line)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                LineBullet(code: line.pcdLineCode, isLineCode: true)
                Text(line.displayName).font(ws.sans(14, weight: .semibold)).foregroundStyle(SoftBlue.ink)
                Spacer()
                if disrupted != nil {
                    Text("Delays").font(ws.sans(11, weight: .semibold)).foregroundStyle(SoftBlue.amber)
                } else {
                    Text("Normal service").font(ws.sans(11, weight: .semibold)).foregroundStyle(SoftBlue.sub)
                }
            }
            .padding(.top, 16)
            .padding(.horizontal, 18)

            // Disruption is a text capsule, not a glow edge or pulsing badge
            // (soft-blue-design.md §5 — both are retired).
            if let disrupted {
                HStack {
                    SoftDisruptionChip(text: "⚠ \(disrupted.detail)")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
            }

            // The route strip CARRIES the directions now (owner 2026-07-25:
            // "why not just design the route such that those info are there,
            // instead of using text"). The two "to <terminus> — Low" rows are
            // gone: the strip already runs from one terminus towards the
            // other, so the terminus names belong on its ends, and the crowd
            // reading — which LTA publishes per STATION, not per direction, so
            // printing it twice was the same number said twice — belongs on
            // this station's own node.
            if seq.window.count > 1 {
                SoftLineMapStrip(lineColor: WSLine.color(forLineCode: line.pcdLineCode),
                                 window: seq.window, currentID: station.id,
                                 towardsLeft: seq.left?.name, towardsRight: seq.right?.name,
                                 crowd: crowdNow) { st in
                    push(.mrtStation(st))
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }

            // Quiet reference footnote — not a departure time, so it doesn't
            // get the mono data treatment.
            Text(hoursLine)
                .font(ws.sans(11)).monospacedDigit().foregroundStyle(SoftBlue.sub)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 14)
                .padding(.bottom, 14)
        }
        .softCard(radius: 20)
    }

    /// Standard network-wide hours (owner decision 2026-07-03) — the app
    /// carries no per-station timetable, so every station shows the same
    /// window rather than an invented per-station first/last train.
    private var hoursLine: String {
        m.use24h ? "05:30 – 00:00" : "5:30 AM – 12:00 AM"
    }

    // MARK: line sequencing (real dataset order — never invented)

    /// Ordered stations sharing `line`'s code prefix on this station (e.g.
    /// "EW"), a 5-wide window centred on this station, and the terminus in
    /// each direction — `left`/`right` matching the window's own order, so the
    /// strip can label its ends. A terminus station has only one of them.
    private func lineSequence(for line: MRTLine)
        -> (prefix: String, window: [MrtGeoStation],
            left: MrtGeoStation?, right: MrtGeoStation?) {
        guard let code = station.codes.first(where: { wsLine(forStationCode: $0) == line }) else {
            return (line.pcdLineCode, [station], nil, nil)
        }
        let prefix = String(code.prefix(2)).uppercased()
        let seq = MrtGeo.all
            .compactMap { st -> (MrtGeoStation, Int)? in
                guard let c = st.codes.first(where: { $0.uppercased().hasPrefix(prefix) }) else { return nil }
                let digits = c.dropFirst(prefix.count)
                return (st, Int(digits) ?? 0)
            }
            .sorted { $0.1 < $1.1 }
            .map { $0.0 }
        guard let idx = seq.firstIndex(where: { $0.id == station.id }) else {
            return (prefix, [station], nil, nil)
        }
        let lo = max(0, idx - 2)
        let hi = min(seq.count - 1, idx + 2)
        let window = Array(seq[lo...hi])
        // Codes ascend left→right in the window, so the low-code terminus is
        // the left end and the high-code one the right; at a terminus the
        // corresponding side has no onward direction.
        return (prefix, window,
                idx > 0 ? seq.first : nil,
                idx < seq.count - 1 ? seq.last : nil)
    }

    // MARK: lift maintenance

    private func liftCard(_ lift: LiftMaintenance) -> some View {
        HStack(alignment: .top, spacing: 10) {
            WSIcon(glyph: .lift, size: 14, color: SoftBlue.amber)
                .frame(width: 26, height: 26)
                .background(SoftBlue.amber.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Lift maintenance")
                    .font(ws.sans(12.5, weight: .semibold)).foregroundStyle(SoftBlue.amber)
                Text(wsFacilityText(lift.detail))
                    .font(ws.sans(11.5, weight: .medium)).foregroundStyle(SoftBlue.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 13)
        .softCard(radius: 14)
    }

    // MARK: bus connections

    @ViewBuilder private var busSection: some View {
        let near = nearbyStops
        if !near.isEmpty {
            // Spacing (owner 2026-07-25: "no padding and proper spacing for
            // this section"): the section sat flush against the card above it
            // with a tight head-to-card gap, so it read as an appendix to the
            // lift card rather than its own section. It now gets the same
            // rhythm as the cards above — breathing room before the heading,
            // and the heading indented to the cards' own text inset.
            VStack(alignment: .leading, spacing: 12) {
                // No extra inset here — SoftSectionHead already carries the
                // app's 4pt heading indent, and stacking 2pt on top pushed
                // this heading out of line with every other section's.
                SoftSectionHead(title: "Bus stops at this station")
                VStack(spacing: 0) {
                    ForEach(near.indices, id: \.self) { i in
                        let item = near[i]
                        Button { push(.busStop(code: item.stop.BusStopCode, service: nil)) } label: {
                            HStack(spacing: 12) {
                                // Same tinted bus tile the Nearby rows use —
                                // without it these rows were indistinguishable
                                // from the MRT content above and only read as
                                // bus stops if you already knew the names
                                // (owner 2026-07-25).
                                WSIcon(glyph: .busSingle, size: 16, color: SoftBlue.blue)
                                    .frame(width: 38, height: 38)
                                    .background(SoftBlue.chipBg,
                                                in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.stop.Description)
                                        .font(ws.sans(14.5, weight: .semibold)).foregroundStyle(SoftBlue.ink)
                                        .lineLimit(1)
                                    SoftStopCode(code: item.stop.BusStopCode, suffix: fmtDistance(item.distanceM))
                                }
                                Spacer(minLength: 8)
                                WSIcon(glyph: .chevron, size: 13, color: SoftBlue.sub)
                            }
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(SoftPressStyle())
                        if i < near.count - 1 { SoftRowDivider() }
                    }
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .softCard(radius: 20)
            }
        }
    }

    // MARK: crowd forecast — quiet, soft-blue, never fabricated

    // The section appears only when there IS a forecast — a titled card
    // announcing "unavailable" is exactly the loud uncertainty banner the
    // app forbids (owner principle: uncertainty stays whisper-quiet).
    @ViewBuilder private var forecastSection: some View {
        if !forecast.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SoftSectionHead(title: "Crowd forecast")
                VStack(alignment: .leading, spacing: 6) {
                    // A bare bar chart of unlabelled heights answers nothing:
                    // low WHAT (owner 2026-07-26)? Say what is being measured
                    // and which way is worse, before the chart — the reader
                    // shouldn't have to infer a scale from the picture.
                    Text("How crowded the platform is expected to be — taller means busier.")
                        .font(ws.sans(11.5, weight: .medium))
                        .foregroundStyle(SoftBlue.sub)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(forecast) { p in
                            SoftForecastBar(fraction: p.fraction, time: p.time,
                                            isNow: p.isNow, level: p.level)
                        }
                    }
                    .padding(.top, 8)
                    if let busiest = busiestNote {
                        (Text("Busiest around ").foregroundStyle(SoftBlue.sub)
                         + Text(busiest).fontWeight(.bold).foregroundStyle(SoftBlue.ink)
                         + Text(". Leave a little earlier to beat the crowd.").foregroundStyle(SoftBlue.sub))
                            .font(ws.sans(11.5, weight: .medium))
                            .padding(.top, 12)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .softCard(radius: 20)
            }
        }
    }

    private var busiestNote: String? {
        guard let peak = forecast.max(by: { $0.fraction < $1.fraction }), peak.fraction > 0 else { return nil }
        // A flat window has no meaningful "busiest" — suppress the note
        // rather than crown an arbitrary slot (Android `_peakOf` parity).
        let known = forecast.filter { $0.level != .unknown }
        guard !known.allSatisfy({ $0.level == known.first?.level }) else { return nil }
        return peak.isNow ? "now" : peak.time
    }

    private func loadForecast() {
        guard let line = lines.first else { return }
        let code = station.codes.first { wsLine(forStationCode: $0) == line } ?? ""
        Task {
            guard let intervals = try? await LTAService.shared.stationForecast(trainLine: line.pcdLineCode)
            else { return }
            let now = Date()
            let mine = intervals
                .filter { $0.station == code }
                .sorted { $0.start < $1.start }
            // Service day over? (now past the final slot's start + 30 min.)
            // Show the closed line instead of a stale tail — mirrors
            // ForecastWindow.build's closed gate on Android.
            if let last = mine.last, now >= last.start.addingTimeInterval(30 * 60) {
                await MainActor.run { forecast = [] }
                return
            }
            // Take the upcoming window (from the last past interval through the
            // next five), so "now" anchors the chart.
            let upcomingIdx = mine.firstIndex { $0.start >= now } ?? max(0, mine.count - 1)
            let start = max(0, upcomingIdx - 1)
            let window = Array(mine[start..<min(mine.count, start + 6)])
            let pts = window.map { iv -> ForecastPoint in
                let level = CrowdLevel.from(iv.crowdLevel)
                let isNow = iv.start <= now && (mine.first { $0.start > iv.start }?.start ?? .distantFuture) > now
                return ForecastPoint(
                    time: isNow ? "now" : WSFmt.clock(iv.start, use24h: m.use24h),
                    fraction: level.wsFraction, isNow: isNow, level: level)
            }
            await MainActor.run { forecast = pts }
        }
    }
}

// MARK: - Line map strip (5-station window, dots + growing bars, tappable)

private struct SoftLineMapStrip: View {
    /// Official MRT line colour — identity, never repurposed for status
    /// (soft-blue-design.md §1).
    let lineColor: Color
    let window: [MrtGeoStation]
    let currentID: String
    /// Terminus in each direction — printed on the matching end of the strip,
    /// which is what replaced the old "to <terminus>" text rows.
    var towardsLeft: String? = nil
    var towardsRight: String? = nil
    /// This station's live crowd, shown on its own node. `.unknown` prints
    /// nothing — uncertainty stays quiet.
    var crowd: CrowdLevel = .unknown
    var onSelect: (MrtGeoStation) -> Void

    @Environment(\.ws) private var ws
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    private var crowdColor: Color {
        switch crowd {
        case .moderate: return SoftBlue.amber
        case .high:     return SoftBlue.red
        default:        return SoftBlue.sub
        }
    }

    private let dotSize: CGFloat = 19

    var body: some View {
        VStack(spacing: 8) {
            // Direction ends. An arrow pointing off the strip says "the line
            // continues this way to …" without spending a row on it.
            HStack(spacing: 8) {
                if let towardsLeft {
                    directionCap(name: towardsLeft, trailingArrow: false)
                }
                Spacer(minLength: 8)
                if let towardsRight {
                    directionCap(name: towardsRight, trailingArrow: true)
                }
            }

            // ONE column per station holding both the node and its name, with
            // the connecting line drawn behind at the node's centre. The dots
            // and the labels used to be two separate HStacks with different
            // width rules, so the names drifted out from under their nodes
            // (owner 2026-07-25: "node and string below the node are not
            // aligned"). Columns can't drift — a node and its name are now
            // literally the same column.
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(window.enumerated()), id: \.element.id) { i, st in
                    stationColumn(index: i, station: st)
                        .frame(maxWidth: .infinity)
                }
            }
            .background(alignment: .top) {
                GeometryReader { geo in
                    // Inset by half a column so the rail starts and ends at the
                    // first/last node's centre, never overshooting them.
                    let inset = geo.size.width / CGFloat(max(window.count, 1)) / 2
                    Rectangle()
                        .fill(lineColor)
                        .frame(height: 3)
                        .padding(.horizontal, inset)
                        .offset(y: dotSize / 2 - 1.5)
                        .scaleEffect(x: grown ? 1 : 0, anchor: .leading)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: grown)
                }
            }

            // The neighbouring nodes have always been buttons, but nothing on
            // screen said so — a diagram reads as a picture until told
            // otherwise (owner 2026-07-26). One quiet line is enough; it is
            // dropped at a terminus-only window where there is nothing else
            // to tap.
            if window.count > 1 {
                HStack(spacing: 4) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 9, weight: .semibold))
                        // A hint that never moves is a hint people stop
                        // seeing. One small bounce every few seconds catches
                        // the eye on a glance without ever becoming a
                        // flashing thing to ignore (owner 2026-07-26).
                        .symbolEffect(.bounce,
                                      options: .repeat(.periodic(delay: 4.5)),
                                      isActive: !reduceMotion)
                    Text("Tap a station to open it")
                        .font(ws.sans(10.5, weight: .medium))
                }
                .foregroundStyle(SoftBlue.sub)
                .padding(.top, 2)
                .accessibilityHidden(true)   // each node already says its own name
            }
        }
        .onAppear { grown = true }
    }

    private func directionCap(name: String, trailingArrow: Bool) -> some View {
        HStack(spacing: 4) {
            if !trailingArrow {
                Image(systemName: "arrow.left").font(.system(size: 9, weight: .bold))
            }
            Text(name)
                .font(ws.sans(11.5, weight: .semibold))
                .lineLimit(1)
            if trailingArrow {
                Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold))
            }
        }
        .foregroundStyle(lineColor)
        .accessibilityLabel("Towards \(name)")
    }

    @ViewBuilder
    private func stationColumn(index i: Int, station st: MrtGeoStation) -> some View {
        let isCurrent = st.id == currentID
        // The node itself is tappable (owner-reported: names alone were tiny
        // targets) — 34pt hit area around the dot.
        Button {
            if !isCurrent { onSelect(st) }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    if isCurrent {
                        Circle().fill(.white).frame(width: dotSize, height: dotSize)
                        Circle().strokeBorder(lineColor, lineWidth: 3)
                            .frame(width: dotSize, height: dotSize)
                    } else {
                        Circle().fill(lineColor).frame(width: 9, height: 9)
                    }
                }
                .frame(width: dotSize, height: dotSize)
                .scaleEffect(grown ? 1 : 0.4)
                .opacity(grown ? 1 : 0)
                .animation(reduceMotion ? nil :
                    .easeOut(duration: 0.35).delay(Double(i) * 0.08), value: grown)

                Text(st.name)
                    .font(ws.sans(9, weight: isCurrent ? .bold : .regular))
                    .foregroundStyle(isCurrent ? SoftBlue.ink : SoftBlue.sub)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 60)

                // Crowd rides THIS station's node — LTA publishes it per
                // station, so it belongs to the place, not to a direction.
                // "Low" on its own answered nothing — low WHAT (owner
                // 2026-07-26)? It's how crowded this station is right now, so
                // the chip says so. Colour still carries the severity, but the
                // word never depends on the colour being understood.
                if isCurrent, crowd != .unknown {
                    Text("\(crowd.wsWord) crowd")
                        .font(ws.sans(9.5, weight: .bold))
                        .foregroundStyle(crowdColor)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(crowdColor.opacity(0.12), in: Capsule())
                }
            }
            // TOP alignment is load-bearing: `minHeight` on its own CENTRES a
            // short column, so a one-line station name (36pt of content) sank
            // ~10pt while the current station — taller, because of its crowd
            // chip — stayed put. That's what dropped the small dots below the
            // rail (owner 2026-07-26). Every column now hangs from the top, so
            // every node sits on the line regardless of what's under it.
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
        .disabled(isCurrent)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
        .accessibilityLabel(isCurrent && crowd != .unknown
                            ? "\(st.name), current station, crowd \(crowd.wsWord)"
                            : st.name)
    }
}

// MARK: - Crowd forecast bar (soft-blue: blue fill on a chipBg track)

/// Same anatomy as the shared `ForecastBar` / the retired `WSMintForecastBar`
/// (grows on appear, "now" gets a ring) — restyled to the 4b palette: mint is
/// banned entirely (soft-blue-design.md §1), so the fill is `SoftBlue.blue`
/// on a `SoftBlue.chipBg` track, and the "now" marker outlines in `ink`
/// rather than glowing.
private struct SoftForecastBar: View {
    let fraction: CGFloat
    let time: String
    var isNow: Bool = false
    /// Named under the "now" bar, so the chart's scale is anchored to a word
    /// at least once instead of leaving every height to interpretation.
    var level: CrowdLevel = .unknown
    @Environment(\.ws) private var ws
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        VStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 7)
                .fill(SoftBlue.chipBg)
                .frame(height: 46)
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(SoftBlue.blue.opacity(isNow ? 0.95 : 0.55))
                        .frame(height: 46 * fraction)
                        .scaleEffect(y: shown ? 1 : 0, anchor: .bottom)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isNow ? SoftBlue.ink : .clear, lineWidth: 1.5)
                        .padding(-3)
                )
            VStack(spacing: 1) {
                Text(time).font(ws.mono(10)).foregroundStyle(SoftBlue.sub)
                // The word line is ALWAYS laid out, even when blank. Only the
                // "now" column has something to say there, and rendering it
                // conditionally made that column one line taller — which, in
                // a bottom-aligned row, pushed its bar up and its time label
                // out of line with the rest (owner 2026-07-26).
                Text(isNow && level != .unknown ? level.wsWord : " ")
                    .font(ws.sans(9.5, weight: .bold))
                    .foregroundStyle(isNow ? SoftBlue.ink : .clear)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level == .unknown ? time
                            : "\(time), \(level.wsWord) crowd")
        .onAppear {
            if reduceMotion { shown = true }
            else { withAnimation(SoftMotion.drift) { shown = true } }
        }
    }
}
