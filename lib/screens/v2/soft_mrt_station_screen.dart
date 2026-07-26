// SoftMrtStationScreen — MRT station detail view.
//
// Flutter/Android port of ios-native/Leyne/WhereSia/WSMrtStationView.swift.
//
// One white card per line serving the station (line identity stays on the
// line badge — colour is never borrowed for status), each carrying a 5-station
// line-map strip centred on this station with the direction termini printed on
// its ends and this station's live crowd on its own node. A disruption
// surfaces as a capsule chip INSIDE the affected line's card, never as a
// separate aggregate panel. Lift maintenance gets one card per outage. Below
// that: the bus stops physically at this station and the real PCDForecast
// crowd forecast, kept whisper-quiet — never a banner.
//
// The crowd reading is stated exactly ONCE (on the strip's current node): LTA
// publishes it per STATION, not per direction or per platform, so the old
// headline card + "to <terminus> — Low" rows were the same number said four
// times.
//
// Can be opened from:
//   • The "Closest to you" nearest-stations section of SoftMrtScreen.
//   • The line screen / a neighbouring node on another station's strip.
//   • The Search screen, the Alerts screen and the Stop screen.
// None of those thread walk/distance context, so proximity is computed here
// from the live location fix rather than trusted from the caller.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/data_store.dart';
import '../../data/forecast_window.dart' show ForecastWindow;
import '../../data/geo.dart' show haversine;
import '../../data/lta_models.dart'
    show LtaStationForecast, LtaStationForecastInterval;
import '../../data/models.dart'
    show NearbyStop, Service, fmtDistance, fmtEta, wsFacilityText;
import '../../data/mrt_geo.dart';
import '../../data/mrt_stations.dart';
import '../../services/analytics_service.dart';
import '../../services/location_service.dart';
import '../../state/app_model.dart';
import '../../theme.dart';
import '../../theme/soft_blue.dart';
import '../../widgets/v2/soft_tab_bar.dart';

class SoftMrtStationScreen extends StatefulWidget {
  const SoftMrtStationScreen({
    super.key,
    required this.station,
    required this.onBack,
    required this.onTab,
    required this.tabSelection,
    this.distanceM,
    this.walkMin,
    this.onOpenStop,
  });

  final MrtGeoStation station;
  final VoidCallback onBack;
  final ValueChanged<SoftTab> onTab;
  final SoftTab tabSelection;

  /// Walk/distance context from the caller. Only the nearest-stations section
  /// ever passes it; every other push site (line screen, strip, alerts, stop
  /// screen, search) leaves it null — which is why the screen computes its own
  /// proximity from the live fix and treats these as a fallback only.
  final int? distanceM;
  final int? walkMin;

  /// Opens a bus stop from the "Bus stops at this station" section.
  /// Optional: SoftHomeScreen's push site doesn't thread this callback
  /// through (out of scope for this screen), so rows there degrade to
  /// non-tappable info-only instead of being hidden.
  final ValueChanged<String>? onOpenStop;

  @override
  State<SoftMrtStationScreen> createState() => _SoftMrtStationScreenState();
}

class _SoftMrtStationScreenState extends State<SoftMrtStationScreen> {
  /// Bus stops physically at/around the station (≤ 400 m), nearest first,
  /// capped at 3. Computed once — the station's coordinates never change —
  /// so the (linear-scan) `stopsWithin` lookup doesn't re-run on every
  /// second's tick-driven rebuild.
  late final List<NearbyStop> _nearbyStops = DataStore.shared
      .stopsWithin(widget.station.lat, widget.station.lon, 400)
      .take(3)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _refreshAll(force: false);
    // Mirror iOS WSMrtStationView.onAppear: log the station view keyed by its
    // first code (falling back to the name when codeless).
    AnalyticsService.stopViewed(
      code: widget.station.codes.isNotEmpty
          ? widget.station.codes.first
          : widget.station.name,
      kind: StopKind.mrt,
    );
  }

  /// Jumps to a neighbouring station from the line-map strip — pushes a fresh
  /// station screen, mirroring how this screen is opened elsewhere (e.g.
  /// `_openInterchangeStation` in soft_stop_screen.dart / `_openMrtStation`
  /// in soft_home_screen.dart).
  void _openStation(BuildContext context, MrtGeoStation station) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SoftMrtStationScreen(
          station: station,
          onBack: () => Navigator.of(context).pop(),
          onTab: widget.onTab,
          tabSelection: widget.tabSelection,
          onOpenStop: widget.onOpenStop,
        ),
      ),
    );
  }

  void _refreshAll({required bool force}) {
    final ds = DataStore.shared;
    ds.refreshTrainAlertsIfStale(force: force);
    ds.refreshLiftMaintenanceIfStale(force: force);
    // Refresh crowd + 30-min forecast for all relevant lines, mirroring iOS
    // WSMrtStationView.onAppear which warms both.
    for (final line in _relevantLines()) {
      ds.refreshCrowd(line, force: force);
      ds.refreshForecast(line, force: force);
    }
    // Warm arrivals for the "Bus stops at this station" rows. Silent: this
    // section shows "—" until data lands rather than a loading spinner.
    for (final stop in _nearbyStops) {
      ds.ensureArrivals(stop.stopCode, force: force, silent: true);
    }
  }

  /// Derives the MRTLine values that are relevant for this station by
  /// scanning [station.codes]. Mirrors iOS `wsLine(forStationCode:)`:
  /// CG→EW, CE→CC, LRT prefix codes are skipped.
  List<MRTLine> _relevantLines() {
    final lines = <MRTLine>[];
    for (final code in widget.station.codes) {
      final line = _lineFromCodePrefix(code);
      if (line != null && !lines.contains(line)) lines.add(line);
    }
    return lines;
  }

  /// The first live disruption affecting [line], if any. Mirrors iOS
  /// `alert(for:)` — the notice belongs to the line's own card, so it is
  /// looked up per line rather than aggregated across the station.
  TrainAlert? _alertFor(List<TrainAlert> all, MRTLine line) {
    for (final a in all) {
      if (a.line == line) return a;
    }
    return null;
  }

  /// Lift outages LTA has tagged against this station. Exact (lowercased)
  /// name equality, mirroring iOS `liftsHere` — the old two-way `contains`
  /// match pulled in every "Bugis"-shaped neighbour of a short station name.
  List<LiftMaintenance> _stationLifts(List<LiftMaintenance> all) {
    final nameLC = widget.station.name.toLowerCase();
    return all
        .where((item) => item.stationName.toLowerCase() == nameLC)
        .toList();
  }

  /// "2 min walk · 51m away" — how far this station is, in the app's standard
  /// order. Computed here from the live fix (iOS `proximityLine`) rather than
  /// trusted from the caller, because only one of this screen's five push
  /// sites passes any. Both halves or neither: a walk time without a distance
  /// is the vaguer half of the same fact. Beyond ~50 km "away" stops being
  /// navigation info, so it is omitted — same as an unknown location.
  String? get _proximityLine {
    final loc = LocationService.shared.lastLocation;
    if (loc != null) {
      final d = haversine(loc.lat, loc.lon, widget.station.lat, widget.station.lon);
      if (d <= 50000) {
        final walk = (d / 80).round().clamp(1, 9999);
        return '$walk min walk · ${fmtDistance(d.round())} away';
      }
      return null;
    }
    // No fix: fall back to whatever context the caller happened to pass.
    final walk = widget.walkMin;
    final dist = widget.distanceM;
    if (walk == null || dist == null) return null;
    return '$walk min walk · ${fmtDistance(dist)} away';
  }

  /// Standard network-wide hours (owner decision 2026-07-03) — the app carries
  /// no per-station timetable, so every station shows the same window rather
  /// than an invented per-station first/last train. Mirrors iOS `hoursLine`.
  static String get _hoursLine =>
      AppModel.shared.use24h ? '05:30 – 00:00' : '5:30 AM – 12:00 AM';

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      // Pushed detail screen — iOS hides its floating tab bar on pushed
      // routes (WSRoot.swift); Android mirrors that via SoftDetailBottomBar
      // (AdBanner only, no tab bar), matching soft_mrt_line_screen.dart /
      // soft_settings_screen.dart. widget.onTab/tabSelection stay as ctor
      // params — still threaded through when this screen itself pushes
      // another (e.g. from SoftMrtLineScreen._openStation).
      bottomNavigationBar: const SoftDetailBottomBar(),
      body: ListenableBuilder(
        listenable: DataStore.shared,
        builder: (context, _) {
          final ds = DataStore.shared;
          final lifts = _stationLifts(ds.liftMaintenance);
          final lines = _relevantLines();

          return RefreshIndicator(
            onRefresh: () async => _refreshAll(force: true),
            color: t.fg,
            backgroundColor: t.surface,
            child: CustomScrollView(
              slivers: [
                _buildAppBar(t),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // Title block lives in the BODY, not the app bar — a
                      // multi-row Column inside SliverAppBar.title clips to
                      // toolbar height (owner-reported cut-off wording).
                      _titleBlock(),
                      const SizedBox(height: 16),
                      // ONE card per line, unconditionally (iOS parity): a
                      // single-line station used to get no strip, no termini
                      // and no per-line status at all, which is most of the
                      // network.
                      for (final line in lines) ...[
                        _LineCard(
                          line: line,
                          station: widget.station,
                          alert: _alertFor(ds.trainAlerts, line),
                          crowdList: ds.crowdByLine[line],
                          hoursLine: _hoursLine,
                          onOpenStation: (st) => _openStation(context, st),
                        ),
                        const SizedBox(height: 12),
                      ],
                      // One card per lift outage — iOS iterates `liftsHere`
                      // rather than folding them into a bulleted panel.
                      for (final lift in lifts) ...[
                        _LiftCard(lift: lift),
                        const SizedBox(height: 12),
                      ],
                      // Bus stops at this station (≤ 400 m, nearest 3, live ETA)
                      if (_nearbyStops.isNotEmpty) ...[
                        _BusStopsSection(
                          stops: _nearbyStops,
                          arrivals: ds.arrivals,
                          onOpenStop: widget.onOpenStop,
                          t: t,
                        ),
                        const SizedBox(height: 12),
                      ],
                      // Station-level crowd forecast — its own section at the
                      // end (iOS parity), not nested inside a per-line card.
                      if (lines.isNotEmpty)
                        _ForecastSection(
                          station: widget.station,
                          line: lines.first,
                          forecastRawByLine: ds.forecastRawByLine,
                        ),
                    ]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Trailing star toggle — saves/un-saves this station. Mirrors iOS
  /// WSMrtStationView's `saveButton`. Listens to AppModel so the icon reflects
  /// the current saved state; the Saved tab and MRT tab read the same list.
  Widget _saveAction(LyneTheme t) {
    return ListenableBuilder(
      listenable: AppModel.shared,
      builder: (context, _) {
        final saved = AppModel.shared.isMrtSaved(widget.station);
        // Star, not bookmark: iOS WSMrtStationView's `saveButton` uses
        // `star`/`star.fill` ("blue is the one accent... for the 'saved'
        // state"), matching the stop screen. Bookmark is iOS's glyph for
        // OTHER save contexts (WSSavedView's context menus).
        return IconButton(
          icon: Icon(
            saved ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 22,
            color: t.fg,
          ),
          tooltip: saved ? 'Remove from saved' : 'Save station',
          onPressed: () {
            if (AppModel.shared.hapticsEnabled) {
              HapticFeedback.selectionClick();
            }
            AppModel.shared.toggleMrtSaved(widget.station);
          },
        );
      },
    );
  }

  /// Minimal chrome bar — back + save only. The multi-row title block was
  /// clipping inside SliverAppBar.title (toolbar height), so it now renders
  /// as body content (_titleBlock), matching iOS where the bar carries only
  /// the eyebrow and the big title lives in the scroll content.
  SliverAppBar _buildAppBar(LyneTheme t) {
    return SliverAppBar(
      backgroundColor: t.bg,
      surfaceTintColor: Colors.transparent,
      pinned: false,
      floating: false,
      snap: false,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_rounded, size: 20, color: t.fg),
        onPressed: widget.onBack,
        tooltip: 'Back',
      ),
      actions: [_saveAction(t)],
    );
  }

  /// Station name + inline code pills, then the proximity line.
  Widget _titleBlock() {
    final proximity = _proximityLine;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Station codes sit INLINE with the name, not on their own row below
        // it (iOS 2026-07-25). Stacked, the amber CC20 pill landed directly
        // above the amber CCL badge on the first line card and the two read as
        // one fighting pair; on the title line the code is unmistakably part
        // of the station's identity and the card's badge is alone in its band.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                widget.station.name,
                style: SoftBlue.sans(
                  24,
                  weight: FontWeight.w700,
                  color: SoftBlue.ink,
                ).copyWith(letterSpacing: -0.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Wrap(
              spacing: 5,
              children: [
                for (final code in widget.station.codes) _LinePill(code: code),
              ],
            ),
            const SizedBox(width: 8),
            Text(
              'MRT',
              style: SoftBlue.sans(
                13,
                weight: FontWeight.w500,
                color: SoftBlue.sub,
              ),
            ),
          ],
        ),
        // Distance belongs TO the station, so it sits under the station's name
        // as its property — not stranded above it between the bar and title.
        if (proximity != null) ...[
          const SizedBox(height: 4),
          Text(
            proximity,
            style: SoftBlue.sans(
              12.5,
              weight: FontWeight.w500,
              color: SoftBlue.sub,
              tabular: true,
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Line pill (station code) ──────────────────────────────────────────────

class _LinePill extends StatelessWidget {
  const _LinePill({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final color = lineColorFor(code);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(LyneRadius.full),
      ),
      child: Text(
        code,
        style: SoftBlue.mono(11, weight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}

// ─── Per-line card ─────────────────────────────────────────────────────────
// Line badge · name · status → disruption chip → line-map strip (termini,
// crowd, tap hint) → the network's first/last train footnote.

class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.line,
    required this.station,
    required this.alert,
    required this.crowdList,
    required this.hoursLine,
    required this.onOpenStation,
  });

  final MRTLine line;
  final MrtGeoStation station;
  final TrainAlert? alert;
  final List<StationCrowd>? crowdList;
  final String hoursLine;
  final ValueChanged<MrtGeoStation> onOpenStation;

  @override
  Widget build(BuildContext context) {
    final seq = _lineSequenceFor(station, line);
    final matched = _matchCrowd(crowdList, station);
    final crowd = matched?.level ?? CrowdLevel.unknown;
    final disrupted = alert;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: SoftBlue.card,
        borderRadius: BorderRadius.circular(SoftBlue.cardRadius),
        boxShadow: SoftBlue.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The standard line badge — the three-letter PCD code in the
              // app's pill, not a 36pt tile carrying the two-letter station
              // prefix (which read as a station code, not a line).
              _LineBadge(line: line),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  line.displayName,
                  style: SoftBlue.sans(
                    14,
                    weight: FontWeight.w600,
                    color: SoftBlue.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Status sits with the line it describes — one word each way,
              // never a station-wide banner.
              Text(
                disrupted != null ? 'Delays' : 'Normal service',
                style: SoftBlue.sans(
                  11,
                  weight: FontWeight.w600,
                  color: disrupted != null ? SoftBlue.amber : SoftBlue.sub,
                ),
              ),
            ],
          ),
          // Disruption is a text capsule INSIDE this line's card, not a glow
          // edge, a pulsing badge or a separate aggregate panel (spec §5 —
          // all three are retired).
          if (disrupted != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: SoftDisruptionChip(text: disrupted.detail),
            ),
          ],
          // The route strip CARRIES the directions: it already runs from one
          // terminus towards the other, so the terminus names belong on its
          // ends — and the crowd reading, which LTA publishes per STATION,
          // belongs on this station's own node.
          if (seq.window.length > 1) ...[
            const SizedBox(height: 14),
            _LineMapStrip(
              lineColor: line.color,
              window: seq.window,
              currentId: station.id,
              towardsLeft: seq.left?.name,
              towardsRight: seq.right?.name,
              crowd: crowd,
              onOpen: onOpenStation,
            ),
          ],
          // Quiet reference footnote — not a departure time, so it doesn't get
          // the mono data treatment or an "OPEN DAILY" shout.
          const SizedBox(height: 14),
          Center(
            child: Text(
              hoursLine,
              style: SoftBlue.sans(
                11,
                weight: FontWeight.w500,
                color: SoftBlue.sub,
                tabular: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The line's identity badge — three-letter PCD code, mono bold on the line
/// colour. Same pill anatomy iOS's `LineBullet(isLineCode:)` uses.
class _LineBadge extends StatelessWidget {
  const _LineBadge({required this.line});

  final MRTLine line;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 26, minHeight: 21),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: line.color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        line.pcdLineCode,
        style: SoftBlue.mono(12, weight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}

// ─── Lift maintenance ──────────────────────────────────────────────────────

/// One card per outage (iOS iterates `liftsHere`): amber icon tile, the
/// "Lift maintenance" title, and LTA's shouty facility string tidied by
/// [wsFacilityText].
class _LiftCard extends StatelessWidget {
  const _LiftCard({required this.lift});

  final LiftMaintenance lift;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: SoftBlue.card,
        borderRadius: BorderRadius.circular(14),
        boxShadow: SoftBlue.cardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: SoftBlue.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(
              Icons.elevator_rounded,
              size: 14,
              color: SoftBlue.amber,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lift maintenance',
                  style: SoftBlue.sans(
                    12.5,
                    weight: FontWeight.w600,
                    color: SoftBlue.amber,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  wsFacilityText(lift.detail),
                  style: SoftBlue.sans(
                    11.5,
                    weight: FontWeight.w500,
                    color: SoftBlue.sub,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bus stops at this station ─────────────────────────────────────────────
// Nearest ≤3 bus stops within 400 m, each with its live soonest arrival.
// Mirrors WSMrtStationView's `busSection`: the heading sits ABOVE the card and
// each row leads with the same tinted bus tile the Nearby rows use — without
// it these rows were indistinguishable from the MRT content above.

class _BusStopsSection extends StatelessWidget {
  const _BusStopsSection({
    required this.stops,
    required this.arrivals,
    required this.onOpenStop,
    required this.t,
  });

  final List<NearbyStop> stops;
  final Map<String, ArrivalState> arrivals;
  final ValueChanged<String>? onOpenStop;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SoftSectionHead(title: 'Bus stops at this station'),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: SoftBlue.card,
            borderRadius: BorderRadius.circular(SoftBlue.cardRadius),
            boxShadow: SoftBlue.cardShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < stops.length; i++) ...[
                _BusStopRow(
                  stop: stops[i],
                  arrival: arrivals[stops[i].stopCode],
                  onOpenStop: onOpenStop,
                  t: t,
                ),
                if (i < stops.length - 1)
                  Divider(
                    color: SoftBlue.hairline,
                    height: 1,
                    thickness: 1,
                    indent: 16,
                    endIndent: 16,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _BusStopRow extends StatelessWidget {
  const _BusStopRow({
    required this.stop,
    required this.arrival,
    required this.onOpenStop,
    required this.t,
  });

  final NearbyStop stop;
  final ArrivalState? arrival;
  final ValueChanged<String>? onOpenStop;
  final LyneTheme t;

  /// The soonest arriving service across all routes at this stop, or null
  /// while arrivals haven't loaded yet (row shows "—" in that case).
  Service? get _soonest {
    final a = arrival;
    if (a == null || a.kind != ArrivalStateKind.loaded) return null;
    if (a.services.isEmpty) return null;
    return a.services.reduce((x, y) => x.etaSec <= y.etaSec ? x : y);
  }

  @override
  Widget build(BuildContext context) {
    final soonest = _soonest;
    final callback = onOpenStop;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: SoftBlue.chipBg,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.directions_bus_rounded,
              size: 16,
              color: SoftBlue.blue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stop.stopName,
                  style: SoftBlue.sans(
                    14.5,
                    weight: FontWeight.w600,
                    color: SoftBlue.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                // "Stop " prefix is not decoration — a bare 5-digit number is
                // ambiguous next to bus numbers and MRT codes (ui-checklist
                // §2), so the code never prints alone.
                SoftStopCode(
                  stop.stopCode,
                  suffix: fmtDistance(stop.distanceM),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (soonest == null)
            Text(
              '—',
              style: SoftBlue.sans(13, color: SoftBlue.sub),
            )
          else
            _EtaLabel(sec: soonest.etaSec, t: t),
          if (callback != null) ...[
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: SoftBlue.sub,
            ),
          ],
        ],
      ),
    );

    if (callback == null) return content;

    return Semantics(
      button: true,
      label: soonest == null
          ? '${stop.stopName}, stop ${stop.stopCode}, '
                '${fmtDistance(stop.distanceM)}'
          : '${stop.stopName}, stop ${stop.stopCode}, '
                '${fmtDistance(stop.distanceM)}, '
                'next bus in ${fmtEta(soonest.etaSec).big} '
                '${fmtEta(soonest.etaSec).small}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (AppModel.shared.hapticsEnabled) {
              HapticFeedback.selectionClick();
            }
            callback(stop.stopCode);
          },
          child: content,
        ),
      ),
    );
  }
}

class _EtaLabel extends StatelessWidget {
  const _EtaLabel({required this.sec, required this.t});

  final int sec;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    final eta = fmtEta(sec);
    final arriving = eta.big == 'Arr';
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          eta.big,
          style: t.mono(
            14,
            weight: FontWeight.w700,
            color: arriving ? t.soon : t.fg,
          ),
        ),
        if (!arriving) ...[
          const SizedBox(width: 2),
          Text(eta.small, style: t.mono(10, color: t.dim)),
        ],
      ],
    );
  }
}

// ─── Line sequencing (real dataset order — never invented) ─────────────────

/// Maps a station code prefix to its [MRTLine] — CG runs on the EWL and CE on
/// the CCL operationally; LRT prefixes (PE, PW, SW, SE, BP) have no line here.
MRTLine? _lineFromCodePrefix(String code) {
  if (code.length < 2) return null;
  switch (code.substring(0, 2).toUpperCase()) {
    case 'EW':
    case 'CG':
      return MRTLine.ew;
    case 'NS':
      return MRTLine.ns;
    case 'NE':
      return MRTLine.ne;
    case 'CC':
    case 'CE':
      return MRTLine.cc;
    case 'DT':
      return MRTLine.dt;
    case 'TE':
      return MRTLine.te;
    default:
      return null;
  }
}

/// Ordered stations sharing [line]'s code prefix on [station] (e.g. "EW"), a
/// 5-wide window centred on [station], and the terminus in EACH direction —
/// `left`/`right` matching the window's own order so the strip can label its
/// ends. Codes ascend left→right, so the low-code terminus is the left end; a
/// terminus station has only one of them. Mirrors iOS `lineSequence(for:)`.
({
  String prefix,
  List<MrtGeoStation> window,
  MrtGeoStation? left,
  MrtGeoStation? right,
})
_lineSequenceFor(MrtGeoStation station, MRTLine line) {
  String? code;
  for (final c in station.codes) {
    if (_lineFromCodePrefix(c) == line) {
      code = c;
      break;
    }
  }
  if (code == null) {
    return (prefix: line.code, window: [station], left: null, right: null);
  }
  final prefix = code.substring(0, 2).toUpperCase();
  final seq = <(MrtGeoStation, int)>[];
  for (final st in MrtGeo.all) {
    String? match;
    for (final c in st.codes) {
      if (c.toUpperCase().startsWith(prefix)) {
        match = c;
        break;
      }
    }
    if (match == null) continue;
    final digits =
        int.tryParse(
          match.substring(prefix.length).replaceAll(RegExp(r'[^0-9]'), ''),
        ) ??
        0;
    seq.add((st, digits));
  }
  seq.sort((a, b) => a.$2.compareTo(b.$2));
  final ordered = seq.map((e) => e.$1).toList();
  final idx = ordered.indexWhere((s) => s.id == station.id);
  if (idx < 0) {
    return (prefix: prefix, window: [station], left: null, right: null);
  }
  final lo = (idx - 2).clamp(0, ordered.length - 1);
  final hi = (idx + 2).clamp(0, ordered.length - 1);
  return (
    prefix: prefix,
    window: ordered.sublist(lo, hi + 1),
    left: idx > 0 ? ordered.first : null,
    right: idx < ordered.length - 1 ? ordered.last : null,
  );
}

/// Find a StationCrowd entry for this station from [list] by matching
/// against the station's codes. Mirrors iOS's crowd lookup.
StationCrowd? _matchCrowd(List<StationCrowd>? list, MrtGeoStation station) {
  if (list == null) return null;
  for (final crowd in list) {
    for (final code in station.codes) {
      if (crowd.code.toUpperCase() == code.toUpperCase()) return crowd;
    }
  }
  return null;
}

/// This station's full forecast interval list — matched by station code
/// against the raw per-station rows.
List<LtaStationForecastInterval> _stationIntervals(
  List<LtaStationForecast>? raw,
  MrtGeoStation station,
) {
  if (raw == null) return const [];
  for (final entry in raw) {
    for (final code in station.codes) {
      if (entry.station.toUpperCase() == code.toUpperCase()) {
        return entry.intervals;
      }
    }
  }
  return const [];
}

// ─── Line map strip ────────────────────────────────────────────────────────

/// 5-station strip centred on the current station — direction caps above, one
/// column per station (node + name + this station's crowd chip), a tap hint
/// below. Mirrors iOS `SoftLineMapStrip`.
class _LineMapStrip extends StatelessWidget {
  const _LineMapStrip({
    required this.lineColor,
    required this.window,
    required this.currentId,
    required this.crowd,
    required this.onOpen,
    this.towardsLeft,
    this.towardsRight,
  });

  final Color lineColor;
  final List<MrtGeoStation> window;
  final String currentId;

  /// Terminus in each direction — printed on the matching end of the strip,
  /// which is what replaced the old "to `<terminus>`" text rows.
  final String? towardsLeft;
  final String? towardsRight;

  /// This station's live crowd, shown on its own node. [CrowdLevel.unknown]
  /// prints nothing — uncertainty stays quiet.
  final CrowdLevel crowd;
  final ValueChanged<MrtGeoStation> onOpen;

  /// The current station's node diameter — also the rail's vertical anchor.
  static const double _dotSize = 19;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Direction ends. An arrow pointing off the strip says "the line
        // continues this way to …" without spending a row on it.
        if (towardsLeft != null || towardsRight != null) ...[
          Row(
            children: [
              Expanded(
                child: towardsLeft == null
                    ? const SizedBox.shrink()
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: _directionCap(towardsLeft!, trailingArrow: false),
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: towardsRight == null
                    ? const SizedBox.shrink()
                    : Align(
                        alignment: Alignment.centerRight,
                        child: _directionCap(towardsRight!, trailingArrow: true),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        // ONE column per station holding both the node and its name, with the
        // rail drawn behind at the node's centre. Two separate rows with
        // different width rules let the names drift out from under their
        // nodes; columns can't drift.
        LayoutBuilder(
          builder: (context, constraints) {
            // Inset by half a column so the rail starts and ends at the
            // first/last node's centre, never overshooting them.
            final inset = constraints.maxWidth / window.length / 2;
            return Stack(
              children: [
                Positioned(
                  left: inset,
                  right: inset,
                  top: _dotSize / 2 - 1.5,
                  child: Container(height: 3, color: lineColor),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final st in window)
                      Expanded(
                        child: _LineMapStop(
                          station: st,
                          current: st.id == currentId,
                          lineColor: lineColor,
                          crowd: crowd,
                          onTap: () => onOpen(st),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
        // The neighbouring nodes have always been buttons, but nothing on
        // screen said so — a diagram reads as a picture until told otherwise.
        // Dropped at a terminus-only window where there is nothing to tap.
        if (window.length > 1)
          ExcludeSemantics(
            // Each node already says its own name.
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.touch_app_rounded,
                    size: 9,
                    color: SoftBlue.sub,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Tap a station to open it',
                    style: SoftBlue.sans(
                      10.5,
                      weight: FontWeight.w500,
                      color: SoftBlue.sub,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _directionCap(String name, {required bool trailingArrow}) {
    final arrow = Text(
      trailingArrow ? '→' : '←',
      style: SoftBlue.sans(9, weight: FontWeight.w700, color: lineColor),
    );
    return Semantics(
      label: 'Towards $name',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!trailingArrow) ...[arrow, const SizedBox(width: 4)],
          Flexible(
            child: Text(
              name,
              style: SoftBlue.sans(
                11.5,
                weight: FontWeight.w600,
                color: lineColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailingArrow) ...[const SizedBox(width: 4), arrow],
        ],
      ),
    );
  }
}

class _LineMapStop extends StatelessWidget {
  const _LineMapStop({
    required this.station,
    required this.current,
    required this.lineColor,
    required this.crowd,
    required this.onTap,
  });

  final MrtGeoStation station;
  final bool current;
  final Color lineColor;
  final CrowdLevel crowd;
  final VoidCallback onTap;

  /// Amber/red only when the level is real information — otherwise the word
  /// carries it and the colour stays neutral.
  Color get _crowdChipColor {
    switch (crowd) {
      case CrowdLevel.moderate:
        return SoftBlue.amber;
      case CrowdLevel.high:
        return SoftBlue.red;
      case CrowdLevel.low:
      case CrowdLevel.unknown:
        return SoftBlue.sub;
    }
  }

  @override
  Widget build(BuildContext context) {
    final showCrowd = current && crowd != CrowdLevel.unknown;
    return Semantics(
      button: !current,
      label: current
          ? (showCrowd
                ? '${station.name}, current station, '
                      'crowd ${_crowdLabel(crowd)}'
                : '${station.name}, current station')
          : 'Open ${station.name}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: current ? null : onTap,
        // TOP alignment is load-bearing: centring a short column sank the
        // one-line neighbour names ~10pt while the current station — taller,
        // because of its crowd chip — stayed put, dropping the small dots
        // below the rail.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 62),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: _LineMapStrip._dotSize,
                height: _LineMapStrip._dotSize,
                child: Center(
                  child: current
                      // The current station is the WHITE ringed node — it has
                      // to sit ON the rail and read as "you are here"; the
                      // neighbours are the plain solid dots.
                      ? Container(
                          width: _LineMapStrip._dotSize,
                          height: _LineMapStrip._dotSize,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: lineColor, width: 3),
                          ),
                        )
                      : Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: lineColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 6),
              // maxWidth, not a fixed width: a 5-column strip on a narrow
              // phone gives each column ~58pt, and a hard 60 would overflow it.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 60),
                child: Text(
                  station.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SoftBlue.sans(
                    9,
                    weight: current ? FontWeight.w700 : FontWeight.w400,
                    color: current ? SoftBlue.ink : SoftBlue.sub,
                  ),
                ),
              ),
              // Crowd rides THIS station's node — LTA publishes it per
              // station, so it belongs to the place, not to a direction.
              // "Low" on its own answered nothing (low WHAT?), so the chip
              // says what is low. Colour carries severity, but the word never
              // depends on the colour being understood.
              if (showCrowd) ...[
                const SizedBox(height: 6),
                // scaleDown stands in for iOS's `minimumScaleFactor(0.8)`:
                // "Moderate crowd" is wider than one strip column, and the
                // capsule shrinking is far better than it clipping into the
                // neighbouring station's name.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _crowdChipColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_crowdLabel(crowd)} crowd',
                      maxLines: 1,
                      style: SoftBlue.sans(
                        9.5,
                        weight: FontWeight.w700,
                        color: _crowdChipColor,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Crowd forecast ────────────────────────────────────────────────────────

/// Station-level crowd forecast — the rest of today's PCDForecast series as
/// ~6 half-hour bars with the "now" slot highlighted and a "busiest around"
/// caption. Its own section at the end of the screen, heading above the card,
/// mirroring iOS `forecastSection`.
class _ForecastSection extends StatelessWidget {
  const _ForecastSection({
    required this.station,
    required this.line,
    required this.forecastRawByLine,
  });

  final MrtGeoStation station;
  final MRTLine line;
  final Map<MRTLine, List<LtaStationForecast>> forecastRawByLine;

  @override
  Widget build(BuildContext context) {
    final intervals = _stationIntervals(forecastRawByLine[line], station);
    // Quiet uncertainty: no data at all ⇒ hide the whole section — a titled
    // card announcing "unavailable" is exactly the loud uncertainty banner the
    // app forbids.
    if (intervals.isEmpty) return const SizedBox.shrink();
    // Data exists but the window is empty ⇒ the service day is over (see
    // ForecastWindow.build's closed gate) — this IS real information, so it
    // still gets its own card and message (not hidden, not "unavailable").
    final ended = ForecastWindow.build(intervals, now: DateTime.now()).isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SoftSectionHead(title: 'Crowd forecast'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: SoftBlue.card,
            borderRadius: BorderRadius.circular(SoftBlue.cardRadius),
            boxShadow: SoftBlue.cardShadow,
          ),
          child: ended
              ? Text(
                  'Service has ended for today — forecast returns in the '
                  'morning.',
                  style: SoftBlue.sans(
                    12,
                    weight: FontWeight.w500,
                    color: SoftBlue.sub,
                  ),
                )
              : _ForecastChart(intervals: intervals),
        ),
      ],
    );
  }
}

/// One bar's worth of forecast data: a half-hour slot's crowd level, its
/// time label ("now" for the active slot, else a clock time), and whether
/// it's the currently-active slot.
class _ForecastPoint {
  const _ForecastPoint({
    required this.time,
    required this.level,
    required this.isNow,
  });

  final String time;
  final CrowdLevel level;
  final bool isNow;
}

/// Gauge fill fraction per crowd level — 34/67/100%, unknown reads as empty.
/// Mirrors CrowdLevel.wsFraction in ios-native/Leyne/WhereSia/WSFormat.swift.
double _crowdFraction(CrowdLevel level) {
  switch (level) {
    case CrowdLevel.low:
      return 0.34;
    case CrowdLevel.moderate:
      return 0.67;
    case CrowdLevel.high:
      return 1.0;
    case CrowdLevel.unknown:
      return 0;
  }
}

class _ForecastChart extends StatelessWidget {
  const _ForecastChart({required this.intervals});

  final List<LtaStationForecastInterval> intervals;

  /// Builds the ~6-bar upcoming window: one slot back from "now" (so the
  /// active slot anchors the chart) through the next several. Windowing +
  /// the timezone-safe local start time now live in [ForecastWindow] (data
  /// layer, unit-tested) — see that file for why `.toLocal()` matters here.
  ///
  /// The 24-hour preference comes from [AppModel], the same source the rest of
  /// this screen reads — `MediaQuery.alwaysUse24HourFormat` is the SYSTEM
  /// setting and disagreed with the app's own toggle.
  List<_ForecastPoint> _window(BuildContext context) {
    final now = DateTime.now();
    final use24h = AppModel.shared.use24h;
    return [
      for (final p in ForecastWindow.build(intervals, now: now))
        _ForecastPoint(
          time: p.isNow ? 'now' : _clockLabel(p.localStart, use24h, context),
          level: p.level,
          isNow: p.isNow,
        ),
    ];
  }

  /// [dt] is expected to already be local (see [ForecastWindow]); `.toLocal()`
  /// here is a defensive no-op belt-and-braces against a future caller
  /// passing a raw UTC-flagged parse result — see forecast_window.dart for
  /// the bug class this guards against.
  static String _clockLabel(DateTime dt, bool use24h, BuildContext context) {
    final local = dt.toLocal();
    final tod = TimeOfDay(hour: local.hour, minute: local.minute);
    if (use24h) {
      final h = tod.hour.toString().padLeft(2, '0');
      final m = tod.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return tod.format(context);
  }

  /// The clearest peak among [points] — the highest-level slot, but only
  /// when the levels aren't all identical (a flat line has no "busiest").
  _ForecastPoint? _peakOf(List<_ForecastPoint> points) {
    final known = points.where((p) => p.level != CrowdLevel.unknown).toList();
    if (known.isEmpty) return null;
    final allSame = known.every((p) => p.level == known.first.level);
    if (allSame) return null;
    var peak = known.first;
    for (final p in known) {
      if (_crowdFraction(p.level) > _crowdFraction(peak.level)) peak = p;
    }
    return peak;
  }

  @override
  Widget build(BuildContext context) {
    final points = _window(context);
    if (points.isEmpty) return const SizedBox.shrink();
    final peak = _peakOf(points);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A bare bar chart of unlabelled heights answers nothing: low WHAT?
        // Say what is being measured and which way is worse, BEFORE the chart
        // — the reader shouldn't have to infer a scale from the picture.
        Text(
          'How crowded the platform is expected to be — taller means busier.',
          style: SoftBlue.sans(
            11.5,
            weight: FontWeight.w500,
            color: SoftBlue.sub,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < points.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(child: _ForecastBar(point: points[i])),
            ],
          ],
        ),
        if (peak != null) ...[
          const SizedBox(height: 12),
          RichText(
            text: TextSpan(
              style: SoftBlue.sans(
                11.5,
                weight: FontWeight.w500,
                color: SoftBlue.sub,
              ),
              children: [
                const TextSpan(text: 'Busiest around '),
                TextSpan(
                  text: peak.time,
                  style: SoftBlue.sans(
                    11.5,
                    weight: FontWeight.w700,
                    color: SoftBlue.ink,
                  ),
                ),
                const TextSpan(
                  text: '. Leave a little earlier to beat the crowd.',
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ForecastBar extends StatelessWidget {
  const _ForecastBar({required this.point});

  final _ForecastPoint point;

  static const double _trackHeight = 46;

  @override
  Widget build(BuildContext context) {
    final fraction = _crowdFraction(point.level);
    final isNow = point.isNow;
    return Semantics(
      label: point.level == CrowdLevel.unknown
          ? point.time
          : '${point.time}, ${_crowdLabel(point.level)} crowd',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The "now" ring sits OUTSIDE the bar (3pt clear), and the padding
          // is spent on every column — a border only the now column reserved
          // space for would make that column wider than its neighbours.
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              border: Border.all(
                color: isNow ? SoftBlue.ink : Colors.transparent,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Container(
              height: _trackHeight,
              decoration: BoxDecoration(
                color: SoftBlue.chipBg,
                borderRadius: BorderRadius.circular(7),
              ),
              alignment: Alignment.bottomCenter,
              child: AnimatedContainer(
                duration: SoftMotion.flowDuration,
                curve: SoftMotion.flowCurve,
                width: double.infinity,
                height: _trackHeight * fraction,
                decoration: BoxDecoration(
                  // The now column is the only saturated one — every bar in
                  // one neutral tone made "now" impossible to pick out.
                  color: SoftBlue.blue.withValues(alpha: isNow ? 0.95 : 0.55),
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            point.time,
            style: SoftBlue.mono(10, color: SoftBlue.sub),
          ),
          const SizedBox(height: 1),
          // The word line is ALWAYS laid out, even when blank. Only the "now"
          // column has something to say there, and rendering it conditionally
          // made that column one line taller — which, in a bottom-aligned row,
          // pushed its bar up and its time label out of line with the rest.
          Text(
            isNow && point.level != CrowdLevel.unknown
                ? _crowdLabel(point.level)
                : ' ',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SoftBlue.sans(
              9.5,
              weight: FontWeight.w700,
              color: isNow ? SoftBlue.ink : Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Crowd helpers ─────────────────────────────────────────────────────────

/// Station crowd word: Low · Moderate · High. Unknown prints an em dash — the
/// app never says "Unknown", which reads as a data failure rather than the
/// quiet absence it is. Mirrors `CrowdLevel.wsWord` (WSFormat.swift).
String _crowdLabel(CrowdLevel level) {
  switch (level) {
    case CrowdLevel.low:
      return 'Low';
    case CrowdLevel.moderate:
      return 'Moderate';
    case CrowdLevel.high:
      return 'High';
    case CrowdLevel.unknown:
      return '—';
  }
}
