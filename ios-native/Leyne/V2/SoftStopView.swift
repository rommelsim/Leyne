// SoftStopView — Leyne 2.4.0 Stop detail: a top bar with back + pin + more
// actions, a large title block with stop name / code·road / walk distance /
// freshness, a "Buses arriving" / "● LIVE" section header, and a card-per-
// service list matching SoftNearbyStopCard's visual language. Each card has a
// green service badge, destination + following arrivals, and a prominent ETA
// pill. Confidence: "~" whisper only for ghost arrivals — never over-honesty.
//
// Swipe gestures:
//   Bus arrival row → leading swipe (right): Notify / Stop Notify
//   The trailing side is reserved for destructive delete (unused here).

import SwiftUI

/// How the stop's arrivals are ordered.
enum StopSort: Hashable {
    case arrival   // soonest first
    case distance  // nearest bus first (live GPS); ghost/no-signal last
    case service   // by bus number (natural numeric order)
}

struct SoftStopView: View {
    let stopCode: String

    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @EnvironmentObject var ds: DataStore

    let onBack: () -> Void
    let onOpenBus: (String) -> Void

    // Default to service-number order (natural sort, so 2 < 10 < 53M), not ETA.
    // The Sort menu still offers arrival/distance.
    @State private var sort: StopSort = .service
    @State private var expanded = false

    // One-tap arrival-alert toggle state.
    // The sheet flow (NotifyWhenSheet + NotifyConfirmView) has been replaced by
    // a direct toggle + an Undo toast. The Manage-alerts sheet is still reachable
    // from the active-alerts card's per-row toggle (remove) or the section
    // header chevron, but no longer presented from the per-bus button.
    @State private var alertToast: ArrivalAlertToastState?
    @State private var showManage = false

    /// How many services to show before the "Show more" expander kicks in.
    private let collapsedCount = 6

    private var t: Theme { m.t }
    private var feed: Freshness { Freshness.from(ds.lastRefresh(stopCode)) }
    private var isPinned: Bool { m.pins.contains { $0.code == stopCode } }

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Fixed top bar + title block — outside the List so they don't
                // scroll. Both are already vertically compact; no clipping risk.
                VStack(alignment: .leading, spacing: 20) {
                    topBar
                    titleBlock
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

                // WATCHING — pinned ABOVE the List (not a List row). Keeping it
                // out of the List means toggling an alert never inserts/removes a
                // List row, so the arrival rows don't fly up/down on the diff;
                // the pinned block just appears/disappears as a clean unit.
                if hasAlertsHere {
                    watchingCard
                        .padding(.horizontal, 16)
                        .padding(.top, 14)   // breathing room below the walk row
                        .padding(.bottom, 8)
                        // Slides down from the title block as you start watching
                        // (and back up when you stop) — see the .animation below.
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Scrollable content as a List so each bus row is individually
                // swipeable (SwiftUI .swipeActions requires a List context).
                List {
                    // ── Arrivals header + sort ─────────────────────────────
                    sectionHeaderRow

                    // ── Arrivals ───────────────────────────────────────────
                    arrivalRows

                    // ── Bottom padding ─────────────────────────────────────
                    Color.clear.frame(height: 40)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(t.bg)
                .refreshable { await ds.refreshArrivals(stop: stopCode) }
            }
            // Animate the WATCHING card sliding in/out (and the list shifting
            // down/up) when you start/stop watching your first/last bus here.
            // Keyed to hasAlertsHere so only this transition animates — the List
            // rows themselves never re-diff (WATCHING is pinned, not a row).
            .animation(.easeInOut(duration: 0.3), value: hasAlertsHere)
        }
        .onAppear { ds.ensureArrivals(stop: stopCode) }
        // Manage all alerts (reachable from the active-alerts card header).
        .sheet(isPresented: $showManage) {
            NavigationStack { ManageAlertsView() }
                .environmentObject(m)
                .environmentObject(fb)
                .environmentObject(ds)
        }
        // One-tap arrival-alert Undo toast.
        .arrivalAlertToastOverlay(state: $alertToast, t: t)
    }

    // MARK: - Top bar

    /// Back · (spacer) · star · ellipsis — circular 44×44 buttons.
    private var topBar: some View {
        HStack(spacing: 10) {
            // Back
            Button { fb.select(); onBack() } label: {
                circleButton(icon: "chevron.left")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer(minLength: 0)

            // Save toggle — pins/unpins this stop. A star fills when saved;
            // to save a specific bus instead, open the bus and toggle its
            // (bus-glyph) save there.
            Button {
                fb.select(); m.togglePin(code: stopCode)
            } label: {
                Image(systemName: isPinned ? "star.fill" : "star")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isPinned ? t.soon : t.fg)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: isPinned)
                    .frame(width: 44, height: 44)
                    .background(t.surface, in: Circle())
                    .overlay(Circle().stroke(t.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPinned ? "\(stopName) saved. Tap to remove."
                                         : "Save stop \(stopName)")

        }
        .padding(.top, 4)
    }

    /// A 44×44 circular icon button using the standard surface/line style.
    private func circleButton(icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(t.fg)
            .frame(width: 44, height: 44)
            .background(t.surface, in: Circle())
            .overlay(Circle().stroke(t.line, lineWidth: 1))
    }

    // MARK: - Title block

    /// Large stop name, code·road subtitle, walk + distance row, freshness.
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Stop name — large bold
            Text(stopName)
                .font(t.sans(31, weight: .bold))
                .foregroundStyle(t.fg)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.75)

            // Code · road
            Text(subtitle)
                .font(t.mono(13))
                .foregroundStyle(t.dim)
                .lineLimit(1)

            // Walk + distance + freshness in one row
            HStack(spacing: 0) {
                // Walk info (only if location is available)
                if let walkInfo = walkDistanceInfo {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(t.soon)
                        Text(walkInfo.walk)
                            .font(t.mono(13, weight: .medium))
                            .foregroundStyle(t.soon)
                        Text("·")
                            .font(t.mono(13))
                            .foregroundStyle(t.faint)
                        Text(walkInfo.dist)
                            .font(t.mono(13))
                            .foregroundStyle(t.dim)
                    }
                }
                Spacer(minLength: 0)
                // LIVE when the feed is live; otherwise the freshness label.
                if feed == .live {
                    HStack(spacing: 4) {
                        Circle().fill(t.soon).frame(width: 6, height: 6)
                        Text("LIVE")
                            .font(t.mono(10, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(t.soon)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Live feed")
                } else if let label = updatedLabel {
                    Text(label)
                        .font(t.mono(12))
                        .foregroundStyle(t.dim)
                }
            }
            .padding(.top, 2)
        }
    }

    // MARK: - List rows

    /// "WATCHING" section — each active alert at this stop is one List row
    /// wrapped in the same surface card look as before. The entire block is
    /// True when ≥1 arrival alert is set for this stop (drives the pinned
    /// WATCHING card's visibility).
    private var hasAlertsHere: Bool {
        m.alerts.contains { $0.kind == .arrival && $0.stopCode == stopCode }
    }

    /// The "WATCHING" card — buses being alerted at this stop. Pinned ABOVE the
    /// List (see body), NOT a List row, so toggling it never reflows the arrival
    /// rows. Each row has a ✕ to stop watching (with an Undo toast).
    private var watchingCard: some View {
        let active = m.alerts.filter { $0.kind == .arrival && $0.stopCode == stopCode }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("WATCHING")
                    .font(t.mono(11, weight: .bold)).tracking(1.2)
                    .foregroundStyle(t.soon)
                Text("alerted 3 & 1 min before")
                    .font(t.mono(10)).foregroundStyle(t.dim)
            }
            .padding(.leading, 2)
            VStack(spacing: 0) {
                ForEach(Array(active.enumerated()), id: \.element.id) { i, a in
                    if i > 0 { rowDivider }
                    HStack(spacing: 12) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(t.soon)
                            .frame(width: 32, height: 32)
                            .background(t.soonBg,
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        HStack(spacing: 6) {
                            Text("Bus \(a.busNo)")
                                .font(t.sans(14, weight: .bold))
                                .foregroundStyle(t.fg)
                            if !a.dest.isEmpty {
                                Text("· To \(a.dest)")
                                    .font(t.sans(13))
                                    .foregroundStyle(t.dim)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        // Remove (✕) button — removes with an Undo toast.
                        Button {
                            alertToast = m.toggleArrivalAlertWithToast(
                                busNo: a.busNo, stopCode: a.stopCode,
                                stopName: a.stopName, dest: a.dest)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(t.dim)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove alert for Bus \(a.busNo)")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(t.line, lineWidth: 1))
        }
    }

    /// Swipe hint: shown only when no alerts are active at this stop.
    /// Arrivals header — short title + a visible Sort control (replaces the old
    /// top-right "..." overflow, which only carried sort). Sits right above the
    /// list so it's easy to reach.
    private var sectionHeaderRow: some View {
        HStack(spacing: 8) {
            Text("Arrivals")
                .font(t.sans(15, weight: .semibold))
                .foregroundStyle(t.dim)
            Spacer(minLength: 8)
            sortMenu
        }
        .padding(.leading, 2)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// Sort control — a pill showing the current order; tap to change it.
    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sort) {
                Label("By ETA", systemImage: "clock").tag(StopSort.arrival)
                Label("By bus number", systemImage: "number").tag(StopSort.service)
                Label("By distance", systemImage: "location").tag(StopSort.distance)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                Text(sortLabel)
                    .font(t.sans(13, weight: .semibold))
            }
            .foregroundStyle(t.fg)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(t.surface, in: Capsule())
            .overlay(Capsule().stroke(t.line, lineWidth: 1))
        }
        .onTapGesture { fb.tap() }
        .accessibilityLabel("Sort arrivals")
    }

    private var sortLabel: String {
        switch sort {
        case .arrival:  return "ETA"
        case .service:  return "Bus no."
        case .distance: return "Distance"
        }
    }

    /// All arrival content emitted directly as List rows.
    @ViewBuilder
    private var arrivalRows: some View {
        switch ds.arrivals[stopCode] {
        case .some(.loaded(let services)) where !services.isEmpty:
            let sorted = sortedServices(services)
            let canCollapse = sorted.count > collapsedCount
            let shown = (expanded || !canCollapse) ? sorted
                                                   : Array(sorted.prefix(collapsedCount))

            // Mid-list ad injection: when the full list is expanded with ≥6 rows,
            // split at the midpoint and insert ONE ad between the halves.
            // This replaces the bottom MREC (stopAdRow hides itself via isShowingMidAd).
            let midIdx = isShowingMidAd ? max(1, shown.count / 2) : shown.count

            // ── First half of rows ──────────────────────────────────────
            ForEach(Array(shown.prefix(midIdx).enumerated()), id: \.element.no) { i, bus in
                busRow(bus)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        let isOn = m.alert(kind: .arrival, busNo: bus.no, stopCode: stopCode) != nil
                        Button {
                            fb.select()
                            // No withAnimation here: animating the List re-layout
                            // (WATCHING row inserting / hint removing) made the
                            // per-row cards slide over each other. Apply instantly.
                            alertToast = m.toggleArrivalAlertWithToast(
                                busNo: bus.no, stopCode: stopCode,
                                stopName: stopName, dest: bus.dest)
                        } label: {
                            Label(isOn ? "Stop" : "Notify",
                                  systemImage: isOn ? "eye.slash.fill" : "eye.fill")
                        }
                        // Fixed greys (not t.soon): the swipe label is auto-white,
                        // and t.soon is white in dark mode → white-on-white blank.
                        .tint(isOn ? Color(white: 0.32) : .gray)
                    }
            }

            // ── Mid-list ad (expanded ≥6 rows only) ────────────────────
            if isShowingMidAd {
                MediumRectAd()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            // ── Second half of rows (only when mid-ad is active) ────────
            if isShowingMidAd {
                ForEach(Array(shown.dropFirst(midIdx).enumerated()), id: \.element.no) { i, bus in
                    busRow(bus)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            let isOn = m.alert(kind: .arrival, busNo: bus.no, stopCode: stopCode) != nil
                            Button {
                                fb.select()
                                alertToast = m.toggleArrivalAlertWithToast(
                                    busNo: bus.no, stopCode: stopCode,
                                    stopName: stopName, dest: bus.dest)
                            } label: {
                                Label(isOn ? "Stop" : "Notify",
                                      systemImage: isOn ? "eye.slash.fill" : "eye.fill")
                            }
                            // Fixed greys (not t.soon): the swipe label is auto-white,
                        // and t.soon is white in dark mode → white-on-white blank.
                        .tint(isOn ? Color(white: 0.32) : .gray)
                        }
                }
            }

            // ── Show more/less ──────────────────────────────────────────
            if canCollapse {
                showMoreRow(total: sorted.count)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            // ── Footer ──────────────────────────────────────────────────
            footer
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            // ── Bottom MREC (collapsed state or short list) ─────────────
            stopAdRow

        case .some(.empty):
            emptyArrivals(message: "No buses in operation right now.")
                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        case .some(.error(let e)):
            emptyArrivals(message: e)
                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        default:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    /// Inline 300×250 medium rectangle below the arrivals.
    /// When the full list is expanded (≥6 rows), the ad is injected at the
    /// midpoint of the list instead (see `arrivalRows`) so the stop screen
    /// always shows exactly ONE ad total. `MediumRectAd` self-suppresses when
    /// ads are off / in screenshot mode.
    @ViewBuilder
    private var stopAdRow: some View {
        if AdConfig.adsEnabled && !AdConfig.screenshotMode && !isShowingMidAd {
            MediumRectAd()
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    /// True when the expanded full list is shown AND there are enough rows to
    /// warrant the midpoint injection (≥6). In this mode the bottom ad is
    /// hidden and the mid-list ad takes its place.
    private var isShowingMidAd: Bool {
        guard expanded, AdConfig.adsEnabled, !AdConfig.screenshotMode else { return false }
        guard case .some(.loaded(let services)) = ds.arrivals[stopCode] else { return false }
        return services.count >= 6
    }

    /// Full-bleed hairline separating rows inside the grouped WATCHING card.
    private var rowDivider: some View {
        Rectangle().fill(t.line).frame(height: 1)
    }

    // MARK: - Bus row

    /// One service row — a self-contained surface card with bus badge, destination,
    /// and up to three ETA columns. Trailing notify button removed; use leading
    /// swipe (right) to toggle arrival alert instead.
    private func busRow(_ bus: Service) -> some View {
        let conf = ArrivalConfidence.of(monitored: bus.monitored, feed: feed)
        let isLive = conf == .live || conf == .stale

        return Button {
            fb.select()
            onOpenBus(bus.no)
        } label: {
            HStack(spacing: 12) {
                // Badge keeps its standard look — proximity is not colour-coded.
                ServiceBadge(svc: bus.no, t: t, size: .md)

                // Destination + accessibility/vehicle glyphs
                VStack(alignment: .leading, spacing: 3) {
                    Text(destLabel(bus))
                        .font(t.sans(14, weight: .semibold))
                        .foregroundStyle(t.fg)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)

                    // WAB / double-deck indicators — only shown for live/stale
                    // arrivals. Quiet secondary tint so they never fight the ETA.
                    if isLive && (bus.wab || bus.deck == .DD) {
                        HStack(spacing: 6) {
                            if bus.wab {
                                Image(systemName: "figure.roll")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(t.dim)
                                    .accessibilityLabel("Wheelchair accessible")
                            }
                            if bus.deck == .DD {
                                Image(systemName: "bus.doubledecker")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(t.dim)
                                    .accessibilityLabel("Double-deck bus")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                Spacer(minLength: 8)

                etaColumns(bus, confidence: conf)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(t.surface,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel("Bus \(bus.no) to \(bus.dest), \(arrivalA11y(bus, conf))")
        .accessibilityHint("Opens bus \(bus.no)")
    }

    /// Up to three arrival columns ("Arr · 13 · 24 min") split by hairlines.
    /// The lead column carries proximity colour + a live signal; the rest ink.
    private func etaColumns(_ bus: Service, confidence: ArrivalConfidence) -> some View {
        let etas = arrivalTimes(bus)
        return HStack(spacing: 0) {
            ForEach(Array(etas.enumerated()), id: \.offset) { i, sec in
                if i > 0 {
                    Rectangle().fill(t.line).frame(width: 1, height: 30)
                        .padding(.horizontal, 6)
                }
                etaColumn(sec, lead: i == 0, confidence: confidence)
            }
        }
    }

    private func etaColumn(_ sec: Int, lead: Bool, confidence: ArrivalConfidence) -> some View {
        let eta = fmtETA(sec)
        let arriving = eta.big == "Arr"
        // ETA ink is uniform — soon-ness is not colour-coded. Scheduled/ghost
        // times read faint (the honesty whisper), everything else standard ink.
        let color = confidence == .unconfirmed ? t.dim : t.fg
        let ghost = confidence == .unconfirmed
        return VStack(spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                if ghost {
                    Text("~").font(t.mono(11, weight: .regular))
                        .foregroundStyle(t.faint).accessibilityHidden(true)
                }
                Text(arriving ? "Arr" : eta.big)
                    .font(t.mono(20, weight: .semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if lead && arriving && confidence == .live {
                    Image(systemName: "dot.radiowaves.up.forward")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(t.soon)
                        .offset(y: -7)
                        .accessibilityHidden(true)
                }
            }
            Text(arriving ? "now" : eta.small)
                .font(t.mono(10))
                .foregroundStyle(t.dim)
        }
        .frame(minWidth: 30)
    }

    /// "Show more" / "Show less" expander row.
    private func showMoreRow(total: Int) -> some View {
        Button {
            fb.tap()
            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(expanded ? "Show less" : "Show more")
                    .font(t.sans(14, weight: .semibold))
                    .foregroundStyle(t.fg)
                Spacer(minLength: 0)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.dim)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(t.surface,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(expanded ? "Show fewer buses" : "Show all \(total) buses")
    }

    // MARK: - Helpers

    private func destLabel(_ bus: Service) -> String {
        bus.dest.isEmpty ? "Bus \(bus.no)" : "To \(bus.dest)"
    }

    /// 1–3 upcoming arrival times (seconds) for a service, dropping any that
    /// aren't strictly later than the previous one.
    private func arrivalTimes(_ bus: Service) -> [Int] {
        var out = [bus.etaSec]
        if bus.followingSec > bus.etaSec { out.append(bus.followingSec) }
        if let d = bus.thirdDate {
            let third = Int(d.timeIntervalSinceNow)
            if third > (out.last ?? 0) { out.append(max(0, third)) }
        }
        return out
    }

    private func arrivalA11y(_ bus: Service, _ conf: ArrivalConfidence) -> String {
        let eta = fmtETA(bus.etaSec)
        let when = eta.big == "Arr" ? "arriving now" : "\(eta.big) \(eta.small)"
        switch conf {
        case .live:        return when
        case .stale:       return "\(when), estimated"
        case .unconfirmed: return "\(when), scheduled only"
        case .none:        return "no service"
        }
    }

    private func sortedServices(_ s: [Service]) -> [Service] {
        switch sort {
        case .arrival:
            return s.sorted { $0.etaSec < $1.etaSec }
        case .distance:
            return s.sorted { busDistance($0) < busDistance($1) }
        case .service:
            return s.sorted { $0.no.localizedStandardCompare($1.no) == .orderedAscending }
        }
    }

    private func busDistance(_ bus: Service) -> Double {
        guard let lat = bus.busLat, let lon = bus.busLon,
              let stop = ds.stopByCode[stopCode] else { return .greatestFiniteMagnitude }
        return haversine(lat, lon, stop.Latitude, stop.Longitude)
    }

    // MARK: - Data helpers

    private var stopName: String {
        let n = ds.stopName(stopCode)
        return n.isEmpty ? stopCode : n
    }

    private var subtitle: String {
        let road = ds.roadName(stopCode)
        return road.isEmpty ? "Stop \(stopCode)" : "Stop \(stopCode) · \(road)"
    }

    private struct WalkInfo { let walk: String; let dist: String }

    /// Walk + distance info if the user's location is known.
    private var walkDistanceInfo: WalkInfo? {
        guard let here = LocationManager.shared.location,
              let stop = ds.stopByCode[stopCode] else { return nil }
        let d = haversine(here.coordinate.latitude, here.coordinate.longitude,
                          stop.Latitude, stop.Longitude)
        let walkMin = max(1, Int((d / 80).rounded()))   // ~80 m/min walking pace
        let distStr = fmtDistance(Int(d.rounded()))
        return WalkInfo(walk: "\(walkMin) min walk", dist: distStr)
    }

    private var updatedLabel: String? {
        guard let last = ds.lastRefresh(stopCode) else { return nil }
        let s = Int(Date().timeIntervalSince(last))
        if s < 5  { return "Updated now" }
        if s < 60 { return "Updated \(s)s ago" }
        let m = s / 60
        return "Updated \(m) min ago"
    }

    // MARK: - Footer / empty

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
            Text("Bus arrival times are estimates from LTA and may vary.")
                .font(t.sans(11))
        }
        .foregroundStyle(t.faint)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func emptyArrivals(message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "tram.fill")
                .font(.system(size: 22))
                .foregroundStyle(t.dim)
            Text(message)
                .font(t.sans(14))
                .foregroundStyle(t.fg)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
