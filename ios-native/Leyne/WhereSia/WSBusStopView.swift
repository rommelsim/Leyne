// WhereSia — Bus stop (Departly green-dark redesign, design-greendark branch).
//
// A "featured bus" hero card up top — the soonest service by default, or
// whichever ALL SERVICES row was last tapped — with the big glowing ETA, a
// progress track toward your stop, crowd, and an expandable route timeline.
// Below it, every other service as a dense, swipeable list (swipe left to
// arm a one-tap arrival alert without leaving the row). Mint is reserved for
// live data + armed alerts; amber/red stay for disruptions and packed crowd.
//
// Alert note: the app's arrival-alert engine (`AppModel.toggleArrivalAlert`
// / `AlertTiming.arrivalLeads`) fires a FIXED 3-min-then-1-min schedule —
// there is no per-alert lead picker today. The "Alert me" pill arms/disarms
// in ONE tap with no confirm sheet (owner 2026-07-25); the pill state flip
// + haptic are the feedback.

import SwiftUI
import CoreLocation
import MapKit   // Apple Maps hand-off from the closed-stop state

struct WSBusStopView: View {
    let code: String
    /// Pre-pins a service into the hero card (notification / widget deep
    /// links and saved lines — the Track Bus screen is retired).
    var initialService: String? = nil

    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var location: LocationManager

    @State private var refreshTick = false
    /// nil = default (the soonest service). Set when a row in ALL SERVICES
    /// is tapped, promoting that service into the hero card. Seeded from
    /// `initialService` for deep links.
    @State private var featuredNo: String? = nil
    @State private var seededInitial = false
    @State private var routeExpanded = false
    /// The bus sheet starts half-height and grows to full when the route opens.
    @State private var sheetDetent: PresentationDetent = .medium
    /// Route timeline normally starts at the bus's position; this reveals
    /// every stop back to the route's origin (owner request 2026-07-25).
    @State private var showPreviousStops = false
    @State private var routeInfo: RouteInfo?
    @State private var routeLoadedFor: String?
    /// First/last bus per service at THIS stop — loaded lazily, only when the
    /// stop turns out to have no live arrivals (the closed-for-the-night
    /// state is the only place it's shown).
    @State private var stopWindows: [(service: String, window: OperatingWindow)] = []
    /// Brief dip-and-recover on the hero ETA when fresh data lands — the
    /// "updated 2s ago" caption is gone (owner decision); the data itself
    /// signals its own freshness instead.
    @State private var dataPulse = false
    /// Service number whose detail sheet is open, nil when none.
    @State private var sheetNo: String?

    private var isPinned: Bool { m.pins.contains { $0.code == code } }
    /// The feed answered and there is genuinely nothing running here.
    private var arrivalsAreEmpty: Bool {
        if case .empty = store.arrivals[code] { return true }
        if case .loaded(let s) = store.arrivals[code] { return s.isEmpty }
        return false
    }
    private var interchange: (name: String, codes: [String])? {
        wsInterchange(forStopName: store.stopName(code))
    }

    /// All live services, number-sorted (as `servicesFor` already returns).
    private var services: [Service]? {
        if case .loaded(let s) = store.arrivals[code] { return s }
        return nil
    }
    private var featured: Service? {
        guard let services, !services.isEmpty else { return nil }
        if let no = featuredNo, let hit = services.first(where: { $0.no == no }) { return hit }
        return wsSoonest(services) ?? services.first
    }

    var body: some View {
        let _ = m.tick
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    // Either the stop has departures — hero, route, list — or
                    // it has none, and then it gets ONE empty state. It used
                    // to render both: a placeholder card AND the all-services
                    // section's own bare sentence underneath, the same words
                    // twice with different padding, which is what read as
                    // "items randomly placed" (owner 2026-07-25).
                    if featured != nil {
                        // The route card used to sit here, between the stop
                        // card and the list, showing whichever service was
                        // soonest. It answered a question nobody asks at this
                        // point — you look for A BUS first — so it moved into
                        // that bus's sheet, where the route is what you came
                        // for (owner 2026-07-26).
                        allServicesSection
                            .padding(.top, 14)
                    } else {
                        heroPlaceholder.padding(.horizontal, 18).padding(.top, 14)
                    }

                    // The ad banner is already a bottom safeAreaInset
                    // (`wsDetailAdBanner`), so the scroll view is inset for it
                    // automatically — the old 90pt spacer stacked a second
                    // clearance on top and left a dead band under the list
                    // (owner 2026-07-25).
                    Color.clear.frame(height: 12)
                }
            }
            .refreshable {
                await store.refreshArrivals(stop: code)
                refreshTick.toggle()
            }
        }
        .wsDetailAdBanner()
        .wsEntrance(delay: 0.28)   // wait out the push slide, else the entrance plays unseen
        .background(SoftBlue.bg.ignoresSafeArea())
        // NATIVE nav bar (owner 2026-07-25). The screen used to hide the
        // system bar and hand-draw a floating back circle, a big title and a
        // second "compact bar" that faded in on scroll — reimplementing, less
        // well, exactly what a large title does. The system now owns the
        // title, the collapse, the back button (so the edge-swipe gesture
        // works without the `enableSwipeBack()` workaround) and the star.
        .navigationTitle(store.stopName(code))
        .navigationBarTitleDisplayMode(.inline)   // owner 2026-07-25: large titles left a big empty band at the top
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isPinned ? "Remove from Saved" : "Save stop",
                       systemImage: isPinned ? "star.fill" : "star",
                       action: togglePin)
                .tint(isPinned ? SoftBlue.blue : nil)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: isPinned)
        .sensoryFeedback(.success, trigger: refreshTick)
        // Medium detent first: the board answers the question without hiding
        // the list it came from; drag up for the rest.
        .sheet(item: Binding(get: { sheetNo.map(WSSheetService.init) },
                             set: { sheetNo = $0?.id
                                    if $0 == nil { routeExpanded = false } })) { item in
            serviceSheet(item.id)
                .presentationDetents([.medium, .large], selection: $sheetDetent)
                .presentationDragIndicator(.visible)
                .presentationBackground(SoftBlue.bg)
        }
        .animation(reduceMotion ? nil : SoftMotion.flow, value: featuredNo)
        .onAppear {
            if !seededInitial {
                seededInitial = true
                if let svc = initialService { featuredNo = svc }
            }
            store.ensureArrivals(stop: code, force: true)
            store.ensureRoutes()
            if let ic = interchange, let st = MrtGeo.station(forCode: ic.codes.first ?? "") {
                store.wsWarmCrowd(for: [st])
            }
        }
        // AppModel's tick loop only keeps pinned/alerted stops fresh — an
        // open unpinned stop never re-fetched (owner: stale until
        // pull-to-refresh). The freshness window + inflight guard inside
        // ensureArrivals make this a no-op on most ticks (~every 25s it
        // actually fetches).
        .onChange(of: m.tick) { _, _ in store.ensureArrivals(stop: code) }
        // Load the timetable only once the feed says this stop is closed —
        // it's a full BusRoutes scan, wasted on the 99% of visits that have
        // live arrivals to show.
        .task(id: arrivalsAreEmpty) {
            guard arrivalsAreEmpty, stopWindows.isEmpty else { return }
            stopWindows = await store.firstLastAtStop(code)
        }
        // Returning from background: the tick loop was paused, so the data
        // can be minutes old — refetch immediately.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.ensureArrivals(stop: code, force: true) }
        }
        // Fresh data landed → pulse the hero ETA once (instant dip, smooth
        // recovery). Replaces the "updated Xs ago" caption.
        .onChange(of: store.lastRefresh(code)) { _, _ in
            guard !reduceMotion else { return }
            dataPulse = true
            withAnimation(.easeOut(duration: 0.7)) { dataPulse = false }
        }
        // (Route collapse on service change happens in the promote action —
        // an onChange here also fired when the route button pins the hero,
        // closing the route the moment it opened.)
    }

    // MARK: - Metadata line (the title and the star live in the nav bar now)

    // ALL metadata on one quiet line — Stop code · walk · distance · MRT
    // interchange (owner 2026-07-25: "messy at the top"; the old standalone
    // interchange row and floating distance caption are folded in here).
    // Rebuilt 2026-07-25 (owner: "why is the text so small and at that
    // location"): the stop's facts were one 11.5pt grey sentence stranded in
    // the whitespace under the nav bar. They're now readable CHIPS — each
    // fact its own capsule at 13pt, so the row reads as the stop's properties
    // instead of a caption nobody can see, and the MRT interchange sits in
    // the same row as an obviously tappable chip.
    /// ONE card, not a scatter of loose capsules (owner 2026-07-26). Free-
    /// floating chips read as three unrelated objects drifting on the ground;
    /// the same three facts inside a single card read as one thing: this
    /// stop's identity. Hairlines divide the facts, and the MRT interchange —
    /// the only tappable item — gets its own full-width row underneath, where
    /// a chevron actually means "go here".
    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                factCell(icon: "number", value: code, label: "Stop")
                factDivider
                factCell(icon: "figure.walk", value: walkValue, label: "Walk")
                factDivider
                factCell(icon: "location", value: distanceValue, label: "Away")
            }
            .padding(.vertical, 12)

            // Directions. The "Walk here" action existed only inside the
            // arrivals EMPTY state, so on a normal stop — the 99% case — there
            // was no way to navigate to it at all (owner 2026-07-26). It
            // belongs here: the card already answers "how far", and this is
            // the action that follows from that answer. Same full-width
            // row-with-a-chevron pattern as the interchange below it, because
            // both mean "this takes you somewhere else".
            // A real BUTTON, not a sentence with a chevron (owner 2026-07-26:
            // "don't put a string of text and call it a day"). Filled accent
            // capsule, white ink, the direction arrow in its own translucent
            // tile, and the walk time carried inside the button so the action
            // states its own cost. This is the card's one action, so it gets
            // the card's one piece of solid colour.
            Button(action: openDirections) {
                HStack(spacing: 10) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.22),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Walk here")
                            .font(ws.sans(14, weight: .bold))
                        Text(walkMinutes.map { "\($0) min · Apple Maps" } ?? "Apple Maps")
                            .font(ws.sans(11, weight: .medium)).opacity(0.85)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .opacity(0.9)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(SoftBlue.blue,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(SoftPressStyle())
            .padding(.horizontal, 12).padding(.bottom, 12)
            .accessibilityLabel("Walk here — directions to this stop in Apple Maps")

            if let ic = interchange {
                SoftRowDivider(inset: 0)
                Button {
                    if let station = MrtGeo.station(forCode: ic.codes.first ?? "") {
                        push(.mrtStation(station))
                    }
                } label: {
                    HStack(spacing: 8) {
                        ForEach(ic.codes.prefix(2), id: \.self) { LineBullet(code: $0) }
                        Text(ic.name)
                            .font(ws.sans(13.5, weight: .semibold))
                            .foregroundStyle(SoftBlue.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        WSIcon(glyph: .chevron, size: 12, color: SoftBlue.sub)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SoftPressStyle())
                .accessibilityLabel("\(ic.name) MRT station")
            }
        }
        .softCard(radius: 18)
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    /// One fact in the identity card: icon, value, and the word that says what
    /// the value IS — a bare "68m" needs its label as much as the code does.
    private func factCell(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SoftBlue.blue)
                Text(label.uppercased())
                    .font(ws.sans(9.5, weight: .bold)).kerning(0.5)
                    .foregroundStyle(SoftBlue.sub)
            }
            Text(value)
                .font(ws.sans(14, weight: .bold)).monospacedDigit()
                .foregroundStyle(SoftBlue.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }

    private var factDivider: some View {
        Rectangle().fill(SoftBlue.hairline)
            .frame(width: 1, height: 30)
    }

    /// Straight-line metres to this stop; nil only when we genuinely can't
    /// say — no fix, or beyond ~50 km, where "away" stops being navigation
    /// information.
    ///
    /// The old <50 m cut-off is gone for the fact card (owner 2026-07-26:
    /// "if the distance is super near, don't put Walk — put the distance in
    /// metres and time to walk there"). Suppressing the number when you're
    /// close was exactly backwards: near the stop is when the metres matter
    /// most, and a card built to hold three facts shouldn't blank two of them
    /// at the moment they're most relevant. `distanceLabel` — the floating
    /// caption the 50 m rule was actually written for — keeps its own cut-off
    /// below.
    private var distanceM: Int? {
        guard let loc = location.location, let stop = store.stopByCode[code] else { return nil }
        let m = Int(haversine(loc.coordinate.latitude, loc.coordinate.longitude,
                              stop.Latitude, stop.Longitude).rounded())
        return m <= 50_000 ? m : nil
    }

    /// Walk minutes at ~80 m/min — the same rate Nearby and Saved use.
    private var walkMinutes: Int? {
        distanceM.map { max(1, Int((Double($0) / 80).rounded())) }
    }

    // With the 50 m suppression lifted these are real numbers whenever there
    // is a fix at all — including, and especially, when you're standing at
    // the stop. "—" now means one thing only: we genuinely don't know.
    private var walkValue: String { walkMinutes.map { "\($0) min" } ?? "—" }
    private var distanceValue: String { distanceM.map(fmtDistance) ?? "—" }

    private var distanceLabel: String? {
        guard let loc = location.location, let stop = store.stopByCode[code] else { return nil }
        let m = Int(haversine(loc.coordinate.latitude, loc.coordinate.longitude,
                              stop.Latitude, stop.Longitude).rounded())
        // Within ~50 m you're AT the stop — "26m away" is noise, drop it
        // (owner decision 2026-07-24). Beyond ~50 km "away" stops being
        // navigation info (travelling, or a simulator location) — drop the
        // caption rather than print "13566km".
        guard m > 50, m <= 50_000 else { return nil }
        // Shared format (owner 2026-07-25): MIN WALK · METRES AWAY, after the
        // labelled code SoftStopCode prints. ~80 m/min, same rate as Nearby.
        return "\(max(1, Int((Double(m) / 80).rounded()))) min walk · \(fmtDistance(m)) away"
    }

    private func togglePin() {
        if let i = m.pins.firstIndex(where: { $0.code == code }) { m.pins.remove(at: i) }
        else { m.pins.append(Pin(code: code, nickname: "")) }
    }

    // MARK: - Service sheet

    /// One bus, in depth — the sheet a row tap opens.
    ///
    /// This is the old hero card's departure board, moved rather than lost:
    /// the board itself was good, it just shouldn't have been sitting at the
    /// top of the screen permanently promoting one service (owner
    /// 2026-07-26). As a bottom sheet it appears only when asked for, keeps
    /// the list underneath in place, and is dismissed by the gesture every
    /// iOS user already knows.
    @ViewBuilder
    private func serviceSheet(_ no: String) -> some View {
        if let svc = (services ?? []).first(where: { $0.no == no }) {
            let entries = pillEntries(svc)
            let alerted = m.alert(kind: .arrival, busNo: svc.no, stopCode: code) != nil

            ScrollView {
                // Breathing room throughout (owner 2026-07-26): identity,
                // board and actions were sitting shoulder to shoulder. 20pt
                // between blocks, 18pt card padding, 12pt between the board's
                // own rows — one step up from the in-page cards, because a
                // sheet is read at arm's length with nothing else on screen.
                VStack(alignment: .leading, spacing: 20) {
                    // Row 1: number tile · destination · Alert-me pill
                    HStack(alignment: .center, spacing: 12) {
                        Text(svc.no)
                            .font(ws.sans(19, weight: .heavy)).foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .frame(width: 46, height: 46)
                            .background(Color.white.opacity(0.22),
                                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("to \(svc.dest)")
                                .font(ws.sans(14, weight: .bold)).lineLimit(1)
                            let road = store.roadName(code)
                            if !road.isEmpty {
                                Text("via \(road)").font(ws.sans(11)).opacity(0.85).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 6)
                        // One tap arms/disarms — no confirm sheet in between;
                        // the pill's state flip + haptic ARE the feedback.
                        alertPill(alerted: alerted) {
                            _ = m.toggleArrivalAlert(busNo: svc.no, stopCode: code,
                                                     stopName: store.stopName(code), dest: svc.dest)
                        }
                    }

                    // Row 2: NEXT / THEN / LATER. Every slot uses the same type
                    // sizes so labels, times and crowd chips each sit on one
                    // line across the board; NEXT is emphasised by opacity, not
                    // by being a size bigger.
                    let slots = Array(entries.prefix(3))
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(slots.enumerated()), id: \.offset) { i, entry in
                            if i > 0 { boardDivider }
                            VStack(alignment: .leading, spacing: 9) {
                                Text(i == 0 ? "NEXT" : i == 1 ? "THEN" : "LATER")
                                    .font(ws.sans(10, weight: .bold)).kerning(0.6)
                                    .opacity(i == 0 ? 0.85 : 0.6)
                                boardTime(entry.eta.big)
                                    .contentTransition(.numericText(countsDown: true))
                                    .opacity(i == 0 ? 1 : 0.88)
                                    .softArrivalPulse(i == 0 && entry.eta.big == "Arr")
                                crowdChip(entry.load)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.trailing, i == slots.count - 1 ? 0 : 10)
                            .padding(.leading, i == 0 ? 0 : 16)
                        }
                        // Only ONE bus timed: say so rather than leaving two
                        // dead columns of gradient. LTA simply has nothing more.
                        if slots.count == 1 {
                            boardDivider
                            Text("No later bus timed yet")
                                .font(ws.sans(12, weight: .medium)).opacity(0.75)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 14)
                        }
                    }
                }
                .foregroundStyle(.white)
                .padding(18)
                .background(SoftBlue.heroGradient,
                            in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 18).padding(.top, 14)

                // Actions for THIS bus. The route opens BEHIND the sheet so
                // the timeline gets the full screen rather than half of it.
                // Favouriting lives here now that the rows no longer carry a
                // context menu (see ServiceRow).
                VStack(spacing: 0) {
                    Button {
                        let expand = !routeExpanded
                        if !expand { showPreviousStops = false }
                        if reduceMotion { routeExpanded = expand }
                        else { withAnimation(SoftMotion.flow) { routeExpanded = expand } }
                        if expand {
                            featuredNo = svc.no
                            sheetDetent = .large   // the timeline needs the room
                            Task { await loadRoute(for: svc.no) }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            WSIcon(glyph: .map, size: 14, color: SoftBlue.blue)
                            Text(routeExpanded ? routeToggleTitle(svc) : "View route")
                                .font(ws.sans(14, weight: .semibold))
                                .foregroundStyle(SoftBlue.ink)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Image(systemName: routeExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(SoftBlue.blue)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SoftPressStyle())

                    // The route opens HERE, under the bus it belongs to,
                    // rather than on a separate card back on the stop screen.
                    if routeExpanded {
                        routeTimeline(for: svc.no)
                            .padding(.horizontal, 16).padding(.bottom, 14)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity))
                    }

                    SoftRowDivider(inset: 16)

                    let fav = m.isFavService(no: svc.no, stop: code)
                    Button { m.toggleFavService(no: svc.no, stop: code) } label: {
                        HStack(spacing: 8) {
                            WSIcon(glyph: fav ? .bookmarkFilled : .bookmark, size: 14,
                                   color: SoftBlue.blue)
                            Text(fav ? "Saved to Favourites" : "Favourite bus \(svc.no)")
                                .font(ws.sans(14, weight: .semibold))
                                .foregroundStyle(SoftBlue.ink)
                            Spacer(minLength: 8)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SoftPressStyle())
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .softCard(radius: 16)
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 18)
            }
            .background(SoftBlue.bg)
            .sensoryFeedback(.success, trigger: alerted)
        }
    }

    /// Hairline between board slots.
    private var boardDivider: some View {
        Rectangle().fill(Color.white.opacity(0.28))
            .frame(width: 1)
            .padding(.vertical, 2)
    }

    /// Board slot time: heavy numeral + small "min" unit, ONE size for every
    /// slot so the three times share a baseline. "Now", not the "Arr"
    /// abbreviation — in a stacked slot "Arr" read as a word in a column of
    /// words, not as a time. "—" stands alone.
    private func boardTime(_ big: String) -> Text {
        guard big != "Arr" else {
            return Text("Now").font(ws.sans(27, weight: .heavy))
        }
        let numeral = Text(big).font(ws.sans(27, weight: .heavy)).monospacedDigit()
        guard big != "—" else { return numeral }
        return numeral + Text(" min").font(ws.sans(12, weight: .semibold))
    }

    /// Crowd for one board slot: a 3-segment gauge plus the word, on a tinted
    /// capsule. The segments count ROOM LEFT, not occupancy (see
    /// `Load.wsSpaceFraction`) — three lit ⟹ seats, one lit ⟹ almost full.
    ///
    /// With no occupancy from LTA the segments are dropped entirely and the
    /// chip says "No data". They can't simply go dark: under this reading an
    /// unlit gauge asserts "no room", which is a claim, not an absence of one.
    @ViewBuilder
    private func crowdChip(_ load: Load?) -> some View {
        HStack(spacing: 5) {
            if let load {
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { seg in
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(
                                Double(seg) < load.wsSpaceFraction * 3 - 0.1 ? 0.95 : 0.30))
                            .frame(width: 4, height: 6)
                    }
                }
            }
            Text(load?.wsShort ?? "No data")
                .font(ws.sans(10, weight: .semibold)).opacity(load == nil ? 0.7 : 0.95)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color.white.opacity(0.16), in: Capsule(style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(load.map { "Crowd: \($0.wsWord)" } ?? "Crowd unknown")
    }

    /// Arm/disarm the arrival alert. Solid white capsule when armed (maximum
    /// contrast on the gradient), translucent when resting.
    private func alertPill(alerted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: alerted ? "bell.fill" : "bell")
                    .font(.system(size: 10, weight: .bold))
                Text(alerted ? "Alert on" : "Alert me")
                    .font(ws.sans(11.5, weight: .bold))
            }
            .foregroundStyle(alerted ? SoftBlue.blue : .white)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(alerted ? Color.white : Color.white.opacity(0.22), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(alerted ? 0 : 0.45), lineWidth: 1))
        }
        .buttonStyle(SoftPressStyle())
    }

    // MARK: - (hero card removed)
    //
    // The gradient "featured bus" card — one service with its NEXT / THEN /
    // LATER board, crowd chips and the Alert-me pill — was removed on
    // 2026-07-26 (owner). The stop screen now goes header → route → ALL
    // SERVICES, where every service already carries the same ETA + crowd,
    // rather than promoting one of them into a card twice the height.
    //
    // Arrival alerts did NOT go with it: each ALL SERVICES row still arms one
    // by swipe (`notifyAction`) or long-press context menu.

    // `routeCard` (the standalone route disclosure that sat between the stop
    // card and All services) was DELETED 2026-07-26 — the route now lives in
    // the bus's own sheet. `routeTimeline` / `routeToggleTitle` stayed: the
    // sheet uses them.

    /// The stop's ONE empty / loading / error state.
    ///
    /// Designed 2026-07-26 (owner). A stop with no buses isn't a failure to
    /// apologise for — it's a normal night-time state, and the user still has
    /// things to do here: walk to it, save it for the morning, look at what
    /// routes serve it, retry. So the card states the situation plainly and
    /// then offers those actions, instead of being a lone sentence in an
    /// otherwise blank screen.
    private var heroPlaceholder: some View {
        let (icon, headline, detail): (String, String, String) = {
            switch store.arrivals[code] {
            case .empty:
                return ("moon.stars.fill", "No buses running",
                        "Nothing is timed at this stop right now — the last bus has gone.")
            case .error(let msg):
                return ("wifi.exclamationmark", "Can't reach live arrivals", msg)
            default:
                return ("arrow.clockwise",
                        "Getting live arrivals…", "Fetching this stop's departures from LTA.")
            }
        }()
        let isLoading: Bool = {
            if case .loaded = store.arrivals[code] { return false }
            if case .empty = store.arrivals[code] { return false }
            if case .error = store.arrivals[code] { return false }
            return true
        }()

        return VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(SoftBlue.blue)
                    .frame(width: 56, height: 56)
                    .background(SoftBlue.chipBg, in: Circle())
                    .symbolEffect(.pulse, isActive: isLoading)
                Text(headline)
                    .font(ws.sans(17, weight: .bold)).foregroundStyle(SoftBlue.ink)
                Text(detail)
                    .font(ws.sans(13, weight: .medium)).foregroundStyle(SoftBlue.sub)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 22).padding(.top, 28).padding(.bottom, 20)

            // The one fact that actually answers "so when CAN I get a bus" —
            // today's first and last departure for every service that serves
            // this stop, from LTA's BusRoutes feed (owner ask 2026-07-26).
            // Only on the closed state: during a network error these numbers
            // would sit next to a message saying we can't reach the network,
            // which reads as a contradiction.
            if arrivalsAreEmpty, !stopWindows.isEmpty {
                SoftRowDivider(inset: 0)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("FIRST & LAST BUS · \(dayTypeLabel.uppercased())")
                            .font(ws.sans(10.5, weight: .bold)).kerning(0.8)
                            .foregroundStyle(SoftBlue.sub)
                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 8)

                    ForEach(Array(stopWindows.enumerated()), id: \.offset) { i, row in
                        let pair = todaysPair(row.window)
                        HStack(spacing: 10) {
                            SoftServiceTile(no: row.service, size: 12, width: 50)
                            Spacer(minLength: 8)
                            // Fixed-width columns so the times line up down the
                            // list rather than drifting with each label.
                            Text(WSFmt.firstLast(pair.first, use24h: m.use24h))
                                .font(ws.mono(13, weight: .bold)).foregroundStyle(SoftBlue.ink)
                                .frame(width: 52, alignment: .trailing)
                            Text("–").font(ws.sans(12)).foregroundStyle(SoftBlue.sub)
                            Text(WSFmt.firstLast(pair.last, use24h: m.use24h))
                                .font(ws.mono(13, weight: .bold)).foregroundStyle(SoftBlue.ink)
                                .frame(width: 52, alignment: .trailing)
                        }
                        .padding(.vertical, 7)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Bus \(row.service), first \(WSFmt.firstLast(pair.first, use24h: m.use24h)), last \(WSFmt.firstLast(pair.last, use24h: m.use24h))")
                        if i < stopWindows.count - 1 { SoftRowDivider(inset: 0) }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }

            if !isLoading {
                SoftRowDivider(inset: 0)
                // What you can still do at a closed stop. NO "check again"
                // here (owner 2026-07-26): the stop is shut, so inviting a
                // refresh only promises something the next poll can't deliver.
                // The error state keeps a retry, because there the data really
                // might be one tap away.
                if case .error = store.arrivals[code] {
                    emptyAction(icon: "arrow.clockwise", title: "Try again",
                                subtitle: "Re-fetch this stop's arrivals") {
                        Task {
                            await store.refreshArrivals(stop: code)
                            refreshTick.toggle()
                        }
                    }
                    SoftRowDivider(inset: 54)
                }
                emptyAction(icon: "arrow.triangle.turn.up.right.diamond.fill",
                            title: "Walk here",
                            subtitle: "Directions in Apple Maps",
                            action: openDirections)
                SoftRowDivider(inset: 54)
                emptyAction(icon: isPinned ? "star.fill" : "star",
                            title: isPinned ? "Saved" : "Save this stop",
                            subtitle: isPinned ? "It's in your Favourites"
                                               : "Find it fast in the morning",
                            action: togglePin)
            }
        }
        .frame(maxWidth: .infinity)
        .softCard()
    }

    /// One action row inside the empty state.
    private func emptyAction(icon: String, title: String, subtitle: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SoftBlue.blue)
                    .frame(width: 34, height: 34)
                    .background(SoftBlue.chipBg,
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(ws.sans(14, weight: .semibold)).foregroundStyle(SoftBlue.ink)
                    Text(subtitle)
                        .font(ws.sans(11.5)).foregroundStyle(SoftBlue.sub)
                }
                Spacer(minLength: 8)
                WSIcon(glyph: .chevron, size: 12, color: SoftBlue.sub)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
    }

    /// Which set of LTA times applies today. Public holidays aren't in the
    /// feed, so Sunday's column is labelled to cover them — the same wording
    /// the Service Info screen uses.
    private var dayTypeLabel: String {
        switch Calendar.current.component(.weekday, from: Date()) {
        case 1:  return "Sun / P.H."
        case 7:  return "Saturday"
        default: return "Weekdays"
        }
    }

    private func todaysPair(_ w: OperatingWindow) -> (first: String?, last: String?) {
        switch Calendar.current.component(.weekday, from: Date()) {
        case 1:  return (w.firstSun, w.lastSun)
        case 7:  return (w.firstSat, w.lastSat)
        default: return (w.firstWD, w.lastWD)
        }
    }

    /// Hand this stop to Apple Maps as a walking destination.
    private func openDirections() {
        guard let stop = store.stopByCode[code] else { return }
        // `LTABusStop.coordinate` is fileprivate to the map layer — build the
        // coordinate from the raw lat/lon instead of widening that access.
        let coord = CLLocationCoordinate2D(latitude: stop.Latitude, longitude: stop.Longitude)
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coord))
        item.name = store.stopName(code)
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }


    /// "Route · N stops to dest" once the route is loaded for this service,
    /// falling back to a stop-count-free title before that (design shows the
    /// total stop count up front; we only know it once the route call resolves).
    private func routeToggleTitle(_ svc: Service) -> String {
        if routeLoadedFor == svc.no, let r = routeInfo, !r.stops.isEmpty {
            let remaining = max(0, r.stops.count - 1 - min(r.youIndex, r.stops.count - 1))
            return "Route · \(remaining) stop\(remaining == 1 ? "" : "s") to \(svc.dest)"
        }
        return "Route · to \(svc.dest)"
    }

    // MARK: - Route timeline (inside the hero card)

    /// One display row of the compact route skeleton.
    private enum RouteLine: Identifiable {
        case bus(RouteStopLive)      // where the bus currently is
        case gap(Int, String)        // "N stops" ellipsis (id-salt)
        case you(RouteStopLive)
        case stop(RouteStopLive)
        case past(RouteStopLive, Int) // stop BEFORE yours (index-salted id —
                                      // loop routes can visit a code twice)
        case final(RouteStopLive)

        var id: String {
            switch self {
            case .bus(let s):       return "bus-\(s.code)"
            case .gap(_, let k):    return "gap-\(k)"
            case .you(let s):       return "you-\(s.code)"
            case .stop(let s):      return s.code
            case .past(let s, let i): return "past-\(i)-\(s.code)"
            case .final(let s):     return "end-\(s.code)"
            }
        }
    }

    /// Owner spec: the timeline shows the bus's current position (when the
    /// live GPS resolves to a stop before yours, with a "N stops" gap row up
    /// to yours), then EVERY stop from yours to the final one — the list
    /// scrolls (bounded height), so the whole route is reachable.
    private func routeLines(_ r: RouteInfo) -> [RouteLine] {
        let you = min(max(r.youIndex, 0), r.stops.count - 1)
        var lines: [RouteLine] = []
        if showPreviousStops {
            // The whole approach, origin → your stop, with the bus shown
            // in place where its live position resolves.
            for i in 0..<you {
                if r.busIndex == i { lines.append(.bus(r.stops[i])) }
                else { lines.append(.past(r.stops[i], i)) }
            }
        } else if let b = r.busIndex, b < you {
            lines.append(.bus(r.stops[b]))
            if you - b > 1 { lines.append(.gap(you - b - 1, "approach")) }
        }
        lines.append(.you(r.stops[you]))
        let onward = Array(r.stops[(you + 1)...])
        for s in onward.dropLast() { lines.append(.stop(s)) }
        if let end = onward.last { lines.append(.final(end)) }
        return lines
    }

    @ViewBuilder
    private func routeTimeline(for no: String) -> some View {
        if routeLoadedFor == no, let r = routeInfo, !r.stops.isEmpty {
            let lines = routeLines(r)
            let you = min(max(r.youIndex, 0), r.stops.count - 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Earlier-stops toggle lives INSIDE the timeline as its
                    // first row — where the missing segment actually is —
                    // instead of a stray text link above the card (owner
                    // 2026-07-25: wanted to see the route BEFORE the shown
                    // segment; the option existed but was easy to miss).
                    if you > 0 {
                        earlierStopsRow(count: you)
                    }
                    ForEach(Array(lines.enumerated()), id: \.element.id) { i, line in
                        routeLineRow(line, index: i, isLast: i == lines.count - 1)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .frame(maxHeight: 230)
            .scrollIndicators(.visible)
        } else {
            Text("Loading route…").font(ws.sans(12, weight: .medium)).foregroundStyle(SoftBlue.sub)
                .padding(.top, 6)
        }
    }

    /// First row of the timeline: the collapsed origin-side segment, styled
    /// like a gap row (dotted spine) so it reads as part of the route line.
    private func earlierStopsRow(count: Int) -> some View {
        Button {
            if reduceMotion { showPreviousStops.toggle() }
            else { withAnimation(SoftMotion.flow) { showPreviousStops.toggle() } }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 3) {
                    ForEach(0..<3) { _ in
                        Circle().fill(SoftBlue.blue.opacity(0.4))
                            .frame(width: 2.5, height: 2.5)
                    }
                }
                .frame(width: 16)
                Text(showPreviousStops
                     ? "Hide earlier stops"
                     : "\(count) earlier stop\(count == 1 ? "" : "s") · show")
                    .font(ws.sans(11.5, weight: .semibold))
                    .foregroundStyle(SoftBlue.blue)
                Spacer(minLength: 0)
                Image(systemName: showPreviousStops ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(SoftBlue.blue)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
    }

    @ViewBuilder
    private func routeLineRow(_ line: RouteLine, index: Int, isLast: Bool) -> some View {
        switch line {
        case .bus(let s):
            timelineRow(index: index, isLast: isLast,
                        dot: AnyView(
                            ZStack {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(SoftBlue.chipBg)
                                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .strokeBorder(SoftBlue.blue.opacity(0.5), lineWidth: 1))
                                    .frame(width: 16, height: 16)
                                WSIcon(glyph: .busSingle, size: 9, color: SoftBlue.blue)
                            }),
                        name: s.name, nameStyle: (ws.sans(12.5, weight: .regular), SoftBlue.sub),
                        tag: "Bus is here", tagColor: SoftBlue.blue)
        case .gap(let n, _):
            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 3) {
                    ForEach(0..<3) { _ in
                        Circle().fill(SoftBlue.ink.opacity(0.2))
                            .frame(width: 2.5, height: 2.5)
                    }
                }
                .frame(width: 16)
                Text("\(n) stop\(n == 1 ? "" : "s")")
                    .font(ws.sans(10.5)).foregroundStyle(SoftBlue.sub)
            }
            .padding(.vertical, 3)
            .wsRouteRowEntrance(index: index, reduceMotion: reduceMotion)
        case .you(let s):
            timelineRow(index: index, isLast: isLast,
                        dot: AnyView(
                            Circle().fill(SoftBlue.blue)
                                .frame(width: 10, height: 10)),
                        name: s.name, nameStyle: (ws.sans(12.5, weight: .semibold), SoftBlue.ink),
                        tag: "You are here", tagColor: SoftBlue.sub)
        case .stop(let s):
            timelineRow(index: index, isLast: isLast,
                        dot: AnyView(
                            Circle().stroke(SoftBlue.ink.opacity(0.25), lineWidth: 2)
                                .frame(width: 8, height: 8)),
                        name: s.name, nameStyle: (ws.sans(12.5, weight: .regular), SoftBlue.sub),
                        tag: nil, tagColor: SoftBlue.sub)
        case .past(let s, _):
            // Already behind the bus/you — quietest treatment on the line.
            timelineRow(index: index, isLast: isLast,
                        dot: AnyView(
                            Circle().stroke(SoftBlue.ink.opacity(0.15), lineWidth: 2)
                                .frame(width: 8, height: 8)),
                        name: s.name,
                        nameStyle: (ws.sans(12.5, weight: .regular), SoftBlue.sub.opacity(0.7)),
                        tag: nil, tagColor: SoftBlue.sub)
        case .final(let s):
            timelineRow(index: index, isLast: isLast,
                        dot: AnyView(
                            Circle().stroke(SoftBlue.blue.opacity(0.7), lineWidth: 2)
                                .frame(width: 9, height: 9)),
                        name: s.name, nameStyle: (ws.sans(12.5, weight: .semibold), SoftBlue.ink),
                        tag: "Final stop", tagColor: SoftBlue.sub)
        }
    }

    private func timelineRow(index: Int, isLast: Bool, dot: AnyView,
                             name: String, nameStyle: (Font, Color),
                             tag: String?, tagColor: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                dot.frame(width: 16, height: 16)
                if !isLast {
                    Rectangle().fill(SoftBlue.ink.opacity(0.12))
                        .frame(width: 2, height: 16)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name)
                    .font(nameStyle.0).foregroundStyle(nameStyle.1)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let tag {
                    Text(tag).font(ws.sans(11)).foregroundStyle(tagColor).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 2)
        .wsRouteRowEntrance(index: index, reduceMotion: reduceMotion)
    }

    private func loadRoute(for no: String) async {
        guard var r = await store.route(service: no, stopCode: code) else { return }
        // Pin the live bus onto the route: nearest stop at/before yours to the
        // bus's GPS (same grounding rule as Track Bus). Absent telemetry keeps
        // the row hidden rather than guessing.
        if let coord = await store.liveBus(service: no, stopCode: code), !r.stops.isEmpty {
            let you = min(max(r.youIndex, 0), r.stops.count - 1)
            var best: (idx: Int, d: Double)? = nil
            for i in 0...you {
                let s = r.stops[i]
                let d = haversine(coord.latitude, coord.longitude, s.lat, s.lon)
                if best == nil || d < best!.d { best = (i, d) }
            }
            r.busIndex = best?.idx
            r.busCoord = coord
        }
        if reduceMotion { routeInfo = r } else { withAnimation(.easeOut(duration: 0.3)) { routeInfo = r } }
        routeLoadedFor = no
    }

    // MARK: - All services

    @ViewBuilder private var allServicesSection: some View {
        switch store.arrivals[code] {
        case .loaded(let all):
            // EVERY service, including the soonest. It used to be filtered out
            // because the hero card was already showing it; with the hero gone
            // that filter silently hid the most useful bus at the stop.
            let rest = all
            if !rest.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("All services")
                        .font(ws.sans(16, weight: .bold)).foregroundStyle(SoftBlue.ink)
                        .padding(.horizontal, 22)
                    VStack(spacing: 0) {
                        ForEach(Array(rest.enumerated()), id: \.element.id) { i, svc in
                            ServiceRow(svc: svc, code: code,
                                       entries: pillEntries(svc),
                                       // Tapping a row opens that bus in a
                                       // bottom sheet. It used to promote the
                                       // service into the hero card — with the
                                       // hero removed the tap changed something
                                       // above the fold and read as doing
                                       // nothing at all (owner 2026-07-26).
                                       onPromote: {
                                           routeExpanded = false
                                           showPreviousStops = false
                                           sheetDetent = .medium
                                           sheetNo = svc.no
                                       })
                            if i < rest.count - 1 { SoftRowDivider(inset: 64) }
                        }
                    }
                    // Clip first: the rows draw their own opaque backgrounds,
                    // so without this the top/bottom row's square corners sit
                    // proud of the card's rounded ones.
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .softCard(radius: 16)
                    .padding(.horizontal, 18)
                }
            }
        default:
            // Empty / error / loading are the placeholder card's job — this
            // section is only ever the LIST. It used to print the same
            // sentence again underneath it (owner 2026-07-25).
            EmptyView()
        }
    }

    // (The floating "Bus N · alert 3 & 1 min" pill that used to hover above
    // the bottom edge is gone — owner 2026-07-25, "weird bus 165 alert at the
    // bottom". It restated what the hero's "Alert on" pill and the row's bell
    // badge already say, and it collided with the anchored ad banner. Armed
    // state now lives only where the control that armed it lives.)

    // MARK: - Shared

    private func pillEntries(_ svc: Service) -> [(eta: ETA, load: Load?)] {
        var out: [(ETA, Load?)] = []
        let now = Date()
        if let d = svc.arrivalDate {
            out.append((fmtETA(max(0, Int(d.timeIntervalSince(now)))), svc.load))
        } else {
            out.append((fmtETA(wsLiveETASec(svc, now: now)), svc.load))
        }
        if let d = svc.followingDate {
            out.append((fmtETA(max(0, Int(d.timeIntervalSince(now)))), svc.followingLoad))
        }
        if let d = svc.thirdDate {
            out.append((fmtETA(max(0, Int(d.timeIntervalSince(now)))), svc.thirdLoad))
        }
        return out
    }
}

// MARK: - Private subview: one ALL SERVICES row with a swipe-to-notify action

private struct ServiceRow: View {
    let svc: Service
    let code: String
    let entries: [(eta: ETA, load: Load?)]
    var onPromote: () -> Void

    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var offset: CGFloat = 0
    @State private var dragStart: CGFloat = 0

    private let actionWidth: CGFloat = 88
    private var alerted: Bool { m.alert(kind: .arrival, busNo: svc.no, stopCode: code) != nil }
    private var later: [String] { entries.dropFirst().map(\.eta.big) }

    var body: some View {
        ZStack(alignment: .trailing) {
            notifyAction

            row
                .background(SoftBlue.card)   // opaque so the row occludes the action while closed
                .offset(x: offset)
                // Horizontal-only UIKit pan: the old SwiftUI DragGesture
                // claimed 12pt of movement in ANY direction, so a vertical
                // scroll that began on a row was eaten by the swipe handler
                // (owner bug 2026-07-25: "cannot scroll when my hand is
                // touching the bus row"). The UIKit recognizer refuses to
                // begin unless the pan is horizontal-dominant, so vertical
                // drags fall through to the ScrollView untouched.
                .gesture(WSHorizontalPan(
                    openAmount: $dragStart,
                    onChanged: { dx in
                        offset = max(-actionWidth - 24, min(0, dragStart + dx))
                    },
                    onEnded: { _ in
                        let shouldOpen = offset < -actionWidth / 2
                        withAnimation(SoftMotion.flow) {
                            offset = shouldOpen ? -actionWidth : 0
                        }
                        dragStart = shouldOpen ? -actionWidth : 0
                    }))
                .onTapGesture {
                    if offset != 0 {
                        withAnimation(SoftMotion.flow) { offset = 0 }
                        dragStart = 0
                    } else {
                        onPromote()
                    }
                }
                // NO context menu on these rows (owner 2026-07-26, twice).
                // A `.contextMenu` outside a List gets its own rounded,
                // shadowed platter at rest, so every row inside this flush
                // list showed rounded "cut outs" at its edges — setting an
                // explicit `.contextMenuPreview` shape did not suppress it.
                // Both of its actions have better homes: Notify is the swipe
                // tray, Favourite is in the row's sheet.
        }
        .clipped()
    }

    private var notifyAction: some View {
        Button {
            _ = m.toggleArrivalAlert(busNo: svc.no, stopCode: code,
                                     stopName: store.stopName(code), dest: svc.dest)
            withAnimation(SoftMotion.flow) { offset = 0 }
            dragStart = 0
        } label: {
            VStack(spacing: 3) {
                WSIcon(glyph: alerted ? .bellRing : .alerts, size: 16, color: SoftBlue.chipInk)
                Text(alerted ? "On ✓" : "Notify")
                    .font(ws.sans(12, weight: .bold)).foregroundStyle(SoftBlue.chipInk)
            }
            .frame(width: actionWidth)
            .frame(maxHeight: .infinity)
            .background(SoftBlue.chipBg)
        }
        .buttonStyle(SoftPressStyle())
        .sensoryFeedback(.success, trigger: alerted)
    }

    private var row: some View {
        // Hierarchy swap (field test 2026-07-24): at a known stop the ETA is
        // the ANSWER, so it's the row's primary element — larger tabular
        // numerals in a fixed-width trailing column so every row's ETA sits
        // on the same vertical line. Destination drops to secondary text.
        // The old bare mint "alerted" dot read as an unexplained live mark —
        // it's now a bell badge, the same glyph the alert controls use.
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                // Fixed width — every row's tile is identical, so the
                // destination and crowd word below it start on one line down
                // the whole list. 58pt holds the longest SG service ("961M")
                // at full size; anything longer scales inside the tile.
                SoftServiceTile(no: svc.no, size: 14, width: 58)
                if alerted {
                    // Armed-alert badge — solid blue circle + white bell
                    // (spec porting table; replaces the mint bell badge).
                    ZStack {
                        Circle().fill(SoftBlue.blue).frame(width: 15, height: 15)
                        WSIcon(glyph: .bellRing, size: 8, color: .white)
                    }
                    .offset(x: 6, y: -6)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("to \(svc.dest)")
                    .font(ws.sans(12.5, weight: .regular)).foregroundStyle(SoftBlue.sub)
                    .lineLimit(1)
                // Crowd is a WORD in 4b — amber/red text only when it matters.
                let load = entries.first?.load ?? svc.load
                Text(load.wsWord)
                    .font(ws.sans(10.5, weight: load == .sea ? .regular : .semibold))
                    .foregroundStyle(load == .sda ? SoftBlue.amber
                                     : load == .lsd ? SoftBlue.red : SoftBlue.sub)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                let big = entries.first?.eta.big ?? "—"
                let arriving = big == "Arr"
                // "Now", not "Arr" — the same word the hero and the pills use,
                // so one state has one name app-wide. Accent ink + heavier
                // weight are the row-level tell; the pulsing chip stays on the
                // hero, or a busy stop would flicker in three places at once.
                Text(arriving ? "Now" : big == "—" ? big : "\(big) min")
                    .font(ws.sans(17, weight: arriving ? .heavy : .bold)).monospacedDigit()
                    .foregroundStyle(arriving ? SoftBlue.chipInk : SoftBlue.ink)
                    .contentTransition(.numericText())
                if !later.isEmpty {
                    Text("then \(later.joined(separator: ", ")) min")
                        .font(ws.sans(10.5)).monospacedDigit().foregroundStyle(SoftBlue.sub)
                }
            }
            .frame(minWidth: 76, alignment: .trailing)
        }
        .padding(.horizontal, 15).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Private shared bits

// (ProgressTrack and CrowdDots retired with the 4b port: the hero ring is
// the approach indicator, and crowd is a word — docs/soft-blue-design.md §5.)

/// Staggered dot-pop + line-grow entrance for route timeline rows, gated
/// behind Reduce Motion.
private struct WSRouteRowEntrance: ViewModifier {
    let index: Int
    let reduceMotion: Bool
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 6)
            .onAppear {
                if reduceMotion { shown = true; return }
                withAnimation(SoftMotion.drift.delay(Double(min(index, 8)) * 0.03)) {
                    shown = true
                }
            }
    }
}
private extension View {
    func wsRouteRowEntrance(index: Int, reduceMotion: Bool) -> some View {
        modifier(WSRouteRowEntrance(index: index, reduceMotion: reduceMotion))
    }
}

// MARK: - Horizontal-only pan (scroll-safe row swipe)

/// UIKit pan recognizer for swipeable rows that begins ONLY for the drags the
/// row can actually use, so everything else falls through to the system:
///   • vertical-dominant drags → fail → the ScrollView scrolls (owner bug
///     2026-07-25: rows were eating scrolls);
///   • rightward drags on a CLOSED row → fail → the navigation edge-pop
///     back swipe works (owner bug 2026-07-25: rows were eating the back
///     gesture too — a row can only move left from rest, so a rightward
///     drag is never ours unless the action tray is open).
private struct WSHorizontalPan: UIGestureRecognizerRepresentable {
    /// The row's rest offset binding: < 0 means the action tray is open and
    /// a rightward drag legitimately belongs to us (it closes the tray).
    var openAmount: Binding<CGFloat>
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(openAmount: openAmount)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let dx = pan.translation(in: pan.view).x
        switch pan.state {
        case .changed:
            onChanged(dx)
        case .ended, .cancelled, .failed:
            onEnded(dx)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let openAmount: Binding<CGFloat>
        init(openAmount: Binding<CGFloat>) { self.openAmount = openAmount }

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer, let view = pan.view else { return false }
            let t = pan.translation(in: view)
            guard abs(t.x) > abs(t.y) else { return false }        // vertical → scroll
            if t.x > 0 { return openAmount.wrappedValue < 0 }      // rightward → back swipe, unless closing an open tray
            return true                                            // leftward → open the tray
        }
    }
}

/// Identifiable wrapper so a service number can drive `.sheet(item:)`.
private struct WSSheetService: Identifiable { let id: String }
