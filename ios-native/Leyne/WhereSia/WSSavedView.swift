// WhereSia — Saved / Favourites (screen 9).
//
// One card per saved item — pinned bus stops, saved MRT stations, saved bus
// lines — each with live next-arrival inline. Swipe left to remove; EDIT (or
// a long drag) reorders; long-press → context menu offers rename (stops
// only) alongside remove. Mutations persist via AppModel's didSet observers.
// Wired to AppModel.pins / savedMrtStations / favServices.
//
// Soft Blue "4b" pass (2026-07-24 rollout, see docs/soft-blue-design.md):
// ported wholesale from the greendark board to the tinted-ground / white-card
// language — rows are floating white cards on `SoftBlue.bg`, the soonest ETA
// reads as a tinted chip (`chipBg`/`chipInk`), not mint tabular numerals. All
// data + mutation paths (rename, reorder, delete, EditMode) are unchanged —
// only how they're drawn. The star-in-a-circle empty state keeps
// `WSTheme.gold` as an identity colour (owner call) inside a restyled white
// card instead of a transparent circle on a dark ground.

import SwiftUI

struct WSSavedView: View {
    @Environment(AppModel.self) private var m: AppModel
    @Environment(DataStore.self) private var store: DataStore
    @Environment(\.ws) private var ws
    @Environment(\.wsPush) private var push
    @EnvironmentObject private var location: LocationManager

    @State private var editMode: EditMode = .inactive
    @State private var renaming: Pin?
    @State private var renameText = ""

    private var isEmpty: Bool {
        m.pins.isEmpty && m.savedMrtStations.isEmpty && m.favServices.isEmpty
    }

    var body: some View {
        let _ = m.tick
        Group {
            if isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(SoftBlue.bg.ignoresSafeArea())
        // Native nav bar + native Edit button (owner 2026-07-25) — the custom
        // title row and its text button are gone.
        .navigationTitle("Favourites")
        .navigationBarTitleDisplayMode(.inline)   // owner 2026-07-25: large titles left a big empty band at the top
        .toolbar {
            if !isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode == .active ? "Done" : "Edit") {
                        withAnimation(SoftMotion.flow) {
                            editMode = editMode == .active ? .inactive : .active
                        }
                    }
                    .sensoryFeedback(.selection, trigger: editMode)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light),
                         trigger: m.pins.count + m.savedMrtStations.count + m.favServices.count)
        .onAppear {
            for p in m.pins { store.ensureArrivals(stop: p.code) }
            for f in m.favServices { if let s = f.stop { store.ensureArrivals(stop: s) } }
            store.ensureRoutes()
            store.wsWarmCrowd(for: m.savedMrtStations)
        }
        .alert("Rename stop", isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nickname", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let pin = renaming { m.rename(code: pin.code, to: renameText) }
                renaming = nil
            }
        }
    }

    // MARK: list

    // MARK: hero ("Up next" — 2026-07-25 redesign, see soft_blue memory)
    //
    // Research-backed composition (Transit/Citymapper/Moovit patterns): the
    // screen is a personal departure board, not a bookmark list. The ONE
    // gradient hero spotlights the saved stop you can actually use right now
    // (nearest by walking distance), with "Leave in X min" converting the
    // ETA into a decision. Rows below each carry a mini board of live pills.

    /// Straight-line metres to a saved stop; nil without a fix or geo record.
    private func pinDistanceM(_ code: String) -> Int? {
        guard let loc = location.location, let stop = store.stopByCode[code] else { return nil }
        return Int(haversine(loc.coordinate.latitude, loc.coordinate.longitude,
                             stop.Latitude, stop.Longitude).rounded())
    }

    /// The hero pick: nearest saved stop when we have a fix, else the user's
    /// own first (top-ranked) pin.
    private var heroPin: Pin? {
        guard !m.pins.isEmpty else { return nil }
        guard location.location != nil else { return m.pins.first }
        return m.pins.min {
            (pinDistanceM($0.code) ?? .max) < (pinDistanceM($1.code) ?? .max)
        }
    }

    /// The decision half of the hero caption. The walk minutes it used to
    /// repeat now live in the shared CODE · MIN WALK format (owner
    /// 2026-07-25), so this returns only the leave call.
    private func leaveLine(etaSec: Int, walkMin: Int) -> String {
        let slack = etaSec / 60 - walkMin
        return slack <= 0 ? "Leave now" : "Leave in \(slack) min"
    }

    /// `Stop 11119 · 1 min walk · 68m away` — the shared format. Walk time and
    /// distance both need a location fix; without one the line degrades to the
    /// labelled code rather than guessing.
    private func metaLine(code: String, walk: Int?) -> String {
        guard let walk, let m = pinDistanceM(code) else { return wsStopCodeLabel(code) }
        return wsStopCodeLabel(code, suffix: "\(walk) min walk · \(fmtDistance(m)) away")
    }

    /// Walk minutes to a saved stop at ~80 m/min; nil without a location fix.
    private func pinWalkMin(_ code: String) -> Int? {
        pinDistanceM(code).map { max(1, Int((Double($0) / 80).rounded())) }
    }

    /// Next three DISTINCT services at a stop, soonest first — the hero board.
    private func boardServices(_ code: String) -> [Service] {
        var seen = Set<String>()
        return store.servicesFor(code)
            .sorted { wsLiveETASec($0) < wsLiveETASec($1) }
            .filter { seen.insert($0.no).inserted }
            .prefix(3).map { $0 }
    }

    // Restructured 2026-07-25 (owner) to match the Nearby hero: the saved stop
    // NAMES the card as its title, and the buses follow as a board. The
    // countdown ring came out for the same reason it did on Nearby — it spent
    // a third of the card on one bus's number while the other departures at
    // that stop had nowhere to go. "Leave in X min" survives as the caption:
    // it's the one line here that isn't just data, it's the decision.
    @ViewBuilder private var savedHero: some View {
        if let pin = heroPin {
            let name = pin.nickname.isEmpty ? store.stopName(pin.code) : pin.nickname
            let board = boardServices(pin.code)
            let walk = pinWalkMin(pin.code)
            Button { push(.busStop(code: pin.code, service: nil)) } label: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 10) {
                        WSIcon(glyph: .busSingle, size: 15, weight: .semibold, color: .white)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.20),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(name)
                                .font(ws.sans(21, weight: .heavy)).tracking(-0.3)
                                .lineLimit(2).minimumScaleFactor(0.7)
                                .fixedSize(horizontal: false, vertical: true)
                            // Shared metadata format: STOP · MIN WALK · AWAY.
                            Text(metaLine(code: pin.code, walk: walk))
                                .font(ws.sans(11.5, weight: .semibold)).monospacedDigit()
                                .opacity(0.85).lineLimit(1).minimumScaleFactor(0.8)
                            // The leave call is the one thing on this card
                            // that's a decision rather than data, so it gets
                            // its own capsule instead of a fourth field on a
                            // metadata line nobody would read that far into.
                            if let walk, let s = board.first {
                                Text(leaveLine(etaSec: wsLiveETASec(s), walkMin: walk))
                                    .font(ws.sans(11, weight: .bold)).monospacedDigit()
                                    .padding(.horizontal, 9).padding(.vertical, 3)
                                    .background(Color.white.opacity(0.20), in: Capsule())
                                    .padding(.top, 2)
                            }
                        }
                        Spacer(minLength: 0)
                    }

                    if board.isEmpty {
                        Text("No live arrivals right now")
                            .font(ws.sans(14, weight: .semibold))
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(board.enumerated()), id: \.element.id) { i, s in
                                if i > 0 {
                                    Rectangle().fill(Color.white.opacity(0.20))
                                        .frame(height: 1)
                                }
                                SoftHeroBoardRow(no: s.no, dest: s.dest,
                                                 etaBig: fmtETA(wsLiveETASec(s)).big,
                                                 lead: i == 0)
                            }
                        }
                    }
                }
                .foregroundStyle(.white)
                .padding(18)
                .background(SoftBlue.heroGradient,
                            in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: SoftBlue.blue.opacity(0.30), radius: 13, y: 8)
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(SoftPressStyle())
        }
    }

    /// Section header on the GROUND (matches Nearby's "Nearby stops") — its
    /// own list-row chrome, deliberately NOT the `row{}` helper, which wraps
    /// content in a white card (the headers rendered as stray pills — owner
    /// 2026-07-25).
    private func sectionHead(_ title: String) -> some View {
        Text(title)
            .font(ws.sans(16, weight: .bold)).foregroundStyle(SoftBlue.ink)
            .padding(.horizontal, 4).padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18))
            .deleteDisabled(true).moveDisabled(true)
    }

    // MARK: list

    private var list: some View {
        List {
            savedHero
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 5, leading: 18, bottom: 5, trailing: 18))
                .deleteDisabled(true).moveDisabled(true)

            if !m.pins.isEmpty {
                sectionHead("Bus stops")
            }
            ForEach(m.pins, id: \.code) { pin in
                row { savedStopCard(pin) }
                    .contextMenu {
                        Button {
                            renameText = pin.nickname
                            renaming = pin
                        } label: { Label("Rename", systemImage: "pencil") }
                        Button(role: .destructive) {
                            m.pins.removeAll { $0.code == pin.code }
                        } label: { Label("Remove", systemImage: "trash") }
                    }
            }
            .onDelete { m.pins.remove(atOffsets: $0) }
            .onMove { m.pins.move(fromOffsets: $0, toOffset: $1) }

            if !m.savedMrtStations.isEmpty {
                sectionHead("MRT stations")
            }
            ForEach(m.savedMrtStations) { st in
                row { savedStationCard(st) }
            }
            .onDelete { m.savedMrtStations.remove(atOffsets: $0) }
            .onMove { m.savedMrtStations.move(fromOffsets: $0, toOffset: $1) }

            // One native ad per screen, between the stops/stations and the
            // saved-lines group. Renders nothing until a creative loads;
            // pinned out of edit mode.
            NativeAdCard()
                .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .deleteDisabled(true).moveDisabled(true)

            if !m.favServices.isEmpty {
                sectionHead("Lines")
                ForEach(m.favServices) { fav in
                    row { lineCard(fav) }
                }
                .onDelete { m.favServices.remove(atOffsets: $0) }
                .onMove { m.favServices.move(fromOffsets: $0, toOffset: $1) }
            }

            // Tab bar is a bottom safeAreaInset (WSRoot) — the list is already
            // inset for it; this is breathing room, not clearance.
            Color.clear.frame(height: 8)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .deleteDisabled(true).moveDisabled(true)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(SoftBlue.bg)
        .environment(\.editMode, $editMode)
        .wsEntrance()
    }

    /// Shared row chrome: each row is its own floating white card, transparent
    /// list gutter (so the tinted ground reads between cards, not a system row).
    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .softCard(radius: 20)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: 18, bottom: 5, trailing: 18))
    }

    // MARK: cards

    /// The "this card is pinned" mark. The Favourites list looked identical to
    /// the Nearby list, so nothing on a card said it was saved — the state was
    /// implied by which tab you were on (owner 2026-07-25). A filled star in
    /// the app's save colour, sitting right after the name, states it on the
    /// card itself and matches the star the stop/station headers toggle.
    private var savedMark: some View {
        Image(systemName: "star.fill")
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(SoftBlue.chipInk)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(SoftBlue.chipBg, in: Capsule())
            .accessibilityLabel("Saved")
    }

    private func savedStopCard(_ pin: Pin) -> some View {
        // Mini departure board (2026-07-25 redesign): up to three live
        // services as segmented pills — three live numbers per card instead
        // of one, which is what actually cures the "too empty" screen.
        let services = store.servicesFor(pin.code)
            .sorted { wsLiveETASec($0) < wsLiveETASec($1) }
        let name = pin.nickname.isEmpty ? store.stopName(pin.code) : pin.nickname
        let road = store.roadName(pin.code)
        // Shared format: MIN WALK · METRES (SoftStopCode labels the code).
        // With no location fix there's neither, so the road name stands in as
        // the "where" rather than leaving the line blank.
        let meta: String? = {
            if let w = pinWalkMin(pin.code), let d = pinDistanceM(pin.code) {
                return "\(w) min walk · \(fmtDistance(d))"
            }
            return road.isEmpty ? nil : road
        }()
        return Button { push(.busStop(code: pin.code, service: nil)) } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(name).font(ws.sans(14.5, weight: .semibold)).foregroundStyle(SoftBlue.ink)
                                .lineLimit(1)
                            savedMark
                        }
                        SoftStopCode(code: pin.code, suffix: meta)
                    }
                    // Two pills, not three — three read as noise across a
                    // full list (owner 2026-07-25: "too many stuff going on").
                    if !services.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(services.prefix(2)) { s in
                                SoftBusTimePill(no: s.no, etaBig: fmtETA(wsLiveETASec(s)).big)
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
                WSIcon(glyph: .chevron, size: 13, color: SoftBlue.sub)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
    }

    private func savedStationCard(_ st: MrtGeoStation) -> some View {
        // Live crowd word joins the meta line (colour only when it's real
        // information: High = amber; Low/Moderate stay quiet).
        let crowd = store.wsCrowd(for: st)
        return Button { push(.mrtStation(st)) } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(st.name).font(ws.sans(14.5, weight: .semibold)).foregroundStyle(SoftBlue.ink)
                            .lineLimit(1)
                        savedMark
                    }
                    HStack(spacing: 0) {
                        Text(wsLineNames(from: st.codes))
                            .font(ws.sans(11.5)).monospacedDigit().foregroundStyle(SoftBlue.sub)
                        if let crowd, crowd != .unknown {
                            Text(" · \(crowd.wsWord) crowd")
                                .font(ws.sans(11.5, weight: crowd == .high ? .semibold : .regular))
                                .foregroundStyle(crowd == .high ? SoftBlue.amber : SoftBlue.sub)
                        }
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 5) { ForEach(st.codes.prefix(3), id: \.self) { LineBullet(code: $0) } }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
    }

    private func lineCard(_ fav: FavService) -> some View {
        let svc = fav.stop.flatMap { code in store.servicesFor(code).first { $0.no == fav.no } }
        return Button {
            if let stop = fav.stop { push(.busStop(code: stop, service: fav.no)) }
            else { push(.serviceInfo(no: fav.no, fromStop: nil)) }
        } label: {
            HStack(spacing: 12) {
                SoftServiceTile(no: fav.no, size: 15)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(svc?.dest ?? "Bus \(fav.no)")
                            .font(ws.sans(14.5, weight: .semibold)).foregroundStyle(SoftBlue.ink)
                            .lineLimit(1)
                        savedMark
                    }
                    Text(fav.stop.map { "at \(store.stopName($0))" } ?? "Anywhere near you")
                        .font(ws.sans(11.5)).foregroundStyle(SoftBlue.sub)
                }
                Spacer()
                if let svc {
                    let eta = fmtETA(wsLiveETASec(svc))
                    Text(eta.big == "Arr" ? "Arr" : "\(eta.big) min")
                        .font(ws.sans(12.5, weight: .bold)).monospacedDigit()
                        .foregroundStyle(SoftBlue.chipInk)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(SoftBlue.chipBg,
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
    }

    // MARK: empty state

    // Teaching empty state + instant candidates (research: the void is best
    // filled with the user's actual nearest stops and the save affordance
    // in context, not a lone illustration).
    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 14) {
                    ZStack {
                        Circle().fill(SoftBlue.chipBg).frame(width: 52, height: 52)
                        Image(systemName: "star")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(WSTheme.gold)
                    }
                    Text("Stops you save appear here\nwith live timings.")
                        .font(ws.sans(13, weight: .medium)).foregroundStyle(SoftBlue.sub)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .softCard(radius: 20)

                let suggestions = store.nearby.prefix(3)
                if !suggestions.isEmpty {
                    Text("Suggested · nearest to you")
                        .font(ws.sans(16, weight: .bold)).foregroundStyle(SoftBlue.ink)
                        .padding(.horizontal, 4).padding(.top, 8)
                    ForEach(suggestions) { stop in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(stop.stopName)
                                    .font(ws.sans(14.5, weight: .semibold))
                                    .foregroundStyle(SoftBlue.ink).lineLimit(1)
                                SoftStopCode(code: stop.stopCode,
                                             suffix: fmtDistance(stop.distanceM))
                            }
                            Spacer(minLength: 8)
                            Button {
                                withAnimation(SoftMotion.flow) {
                                    m.pins.append(Pin(code: stop.stopCode, nickname: ""))
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "star")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("Save").font(ws.sans(12, weight: .bold))
                                }
                                .foregroundStyle(SoftBlue.chipInk)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(SoftBlue.chipBg, in: Capsule())
                                .contentShape(Capsule())
                            }
                            .buttonStyle(SoftPressStyle())
                        }
                        .padding(.horizontal, 16).padding(.vertical, 13)
                        .softCard(radius: 18)
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 10)
        }
    }
}
