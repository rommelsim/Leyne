// SoftMrtStationScreen — MRT station detail view.
//
// Flutter/Android port of ios-native/Leyne/V2/SoftMrtStationView.swift.
//
// Shows station identity, disruption + free-bus/shuttle chips for any of the
// station's lines, lift maintenance at this station, and live crowd level per
// relevant line. No arrival times (LTA does not publish per-station arrivals).
//
// Can be opened from:
//   • The "Closest to you" nearest-stations section of SoftMrtScreen (with
//     distance/walk context).
//   • The Search screen (distance/walk may be null).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/data_store.dart';
import '../../data/forecast_window.dart' show ForecastWindow;
import '../../data/lta_models.dart'
    show LtaStationForecast, LtaStationForecastInterval;
import '../../data/models.dart' show NearbyStop, Service, fmtClock, fmtEta;
import '../../data/mrt_geo.dart';
import '../../data/mrt_stations.dart';
import '../../services/analytics_service.dart';
import '../../state/app_model.dart';
import '../../theme.dart';
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

  /// Walk/distance context — present when opened from the nearest-stations
  /// section, null when opened from Search.
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
    // Mirror iOS SoftMrtStationView.onAppear: log the station view keyed by its
    // first code (falling back to the name when codeless).
    AnalyticsService.stopViewed(
      code: widget.station.codes.isNotEmpty
          ? widget.station.codes.first
          : widget.station.name,
      kind: StopKind.mrt,
    );
  }

  void _refreshAll({required bool force}) {
    final ds = DataStore.shared;
    ds.refreshTrainAlertsIfStale(force: force);
    ds.refreshLiftMaintenanceIfStale(force: force);
    // Refresh crowd + 30-min forecast for all relevant lines, mirroring iOS
    // SoftMrtStationView.swift fetchCrowdForStation which calls both.
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
  /// scanning [station.codes]. Mirrors iOS SoftMrtStationView.swift
  /// `lineFromCode(_:)`: CG→EW, CE→CC, LRT prefix codes are skipped.
  List<MRTLine> _relevantLines() {
    final lines = <MRTLine>{};
    for (final code in widget.station.codes) {
      final line = _lineFromCode(code);
      if (line != null) lines.add(line);
    }
    return lines.toList();
  }

  static MRTLine? _lineFromCode(String code) {
    if (code.length < 2) return null;
    final prefix = code.substring(0, 2).toUpperCase();
    switch (prefix) {
      case 'EW':
      case 'CG': // Changi Airport branch runs on EWL operationally.
        return MRTLine.ew;
      case 'NS':
        return MRTLine.ns;
      case 'NE':
        return MRTLine.ne;
      case 'CC':
      case 'CE': // Circle extension — CC operationally.
        return MRTLine.cc;
      case 'DT':
        return MRTLine.dt;
      case 'TE':
        return MRTLine.te;
      default:
        return null; // LRT (PE, PW, SW, SE, BP) — skip.
    }
  }

  /// "9:41 AM" / "21:41" — current wall-clock time formatted per the app's
  /// 24h preference, for the title's "Updated h:mm" stamp.
  static String _updatedClock() {
    final now = DateTime.now();
    final hhmm =
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    return fmtClock(hhmm, use24h: AppModel.shared.use24h);
  }

  /// Alerts affecting any of this station's lines.
  List<TrainAlert> _stationAlerts(List<TrainAlert> allAlerts) {
    final stationLines = _relevantLines().toSet();
    return allAlerts.where((a) {
      if (a.line == null) return false;
      return stationLines.contains(a.line);
    }).toList();
  }

  /// Lift maintenance items that match this station by name (case-insensitive
  /// substring — LTA names occasionally differ slightly from the geo dataset).
  List<LiftMaintenance> _stationLifts(List<LiftMaintenance> all) {
    final nameLC = widget.station.name.toLowerCase();
    return all.where((item) {
      return item.stationName.toLowerCase().contains(nameLC) ||
          nameLC.contains(item.stationName.toLowerCase());
    }).toList();
  }

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
          final alerts = _stationAlerts(ds.trainAlerts);
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
                      _titleBlock(t, disrupted: alerts.isNotEmpty),
                      const SizedBox(height: 16),
                      // Disruption card
                      if (alerts.isNotEmpty) ...[
                        _DisruptionCard(alerts: alerts, t: t),
                        const SizedBox(height: 12),
                      ],
                      // Lift maintenance card
                      if (lifts.isNotEmpty) ...[
                        _StationLiftCard(lifts: lifts, t: t),
                        const SizedBox(height: 12),
                      ],
                      // Section order mirrors WSMrtStationView.swift: crowd
                      // now → bus stops at this station → crowd forecast.
                      if (lines.isNotEmpty) ...[
                        _StationCrowdHeadlineCard(
                          station: widget.station,
                          lines: lines,
                          crowdByLine: ds.crowdByLine,
                          t: t,
                        ),
                        const SizedBox(height: 12),
                        // Per-line platform rows ONLY at interchanges — on a
                        // single-line station they'd repeat the headline.
                        if (lines.length > 1) ...[
                          _CrowdSection(
                            station: widget.station,
                            lines: lines,
                            crowdByLine: ds.crowdByLine,
                            t: t,
                          ),
                          const SizedBox(height: 12),
                        ],
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
                      // Station-level crowd forecast — its own card at the
                      // end (iOS parity), not nested inside a per-line card.
                      if (lines.isNotEmpty)
                        _ForecastCard(
                          station: widget.station,
                          line: lines.first,
                          forecastRawByLine: ds.forecastRawByLine,
                          t: t,
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
  /// SoftMrtStationView.saveButton. Listens to AppModel so the icon reflects
  /// the current saved state; the Saved tab and MRT tab read the same list.
  Widget _saveAction(LyneTheme t) {
    return ListenableBuilder(
      listenable: AppModel.shared,
      builder: (context, _) {
        final saved = AppModel.shared.isMrtSaved(widget.station);
        // Bookmark, not star — iOS uses the bookmark glyph for every
        // save-a-place action (owner-reported mismatch).
        return IconButton(
          icon: Icon(
            saved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
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

  /// Station name + status/updated line + line pills (+ walk context).
  Widget _titleBlock(LyneTheme t, {required bool disrupted}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.station.name,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: t.fg,
            letterSpacing: -0.5,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        // Status + freshness line — mirrors WSMrtStationView.swift:97-98.
        // DataStore doesn't publicly expose a per-feed (crowd/train) last-
        // fetch timestamp, so — like iOS's own Date()-driven "UPD" stamp —
        // this reflects "now" at each data-driven rebuild rather than a
        // stored fetch time.
        Text(
          '${disrupted ? 'SERVICE DISRUPTED' : 'NORMAL SERVICE'} · '
          'Updated ${_updatedClock()}',
          style: t
              .mono(11, weight: FontWeight.w600, color: t.dim)
              .copyWith(letterSpacing: 0.4),
        ),
        const SizedBox(height: 6),
        // Line code pills + optional walk/distance.
        Row(
          children: [
            Wrap(
              spacing: 5,
              children: widget.station.codes.map((code) {
                return _LinePill(code: code);
              }).toList(),
            ),
            if (widget.walkMin != null) ...[
              const SizedBox(width: 8),
              Icon(Icons.directions_walk_rounded, size: 11, color: t.dim),
              const SizedBox(width: 2),
              Text(
                '${widget.walkMin} min',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: t.dim,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (widget.distanceM != null) ...[
                Text(
                  ' · ${_formatDistance(widget.distanceM!)}',
                  style: TextStyle(fontSize: 12, color: t.faint),
                ),
              ],
            ],
          ],
        ),
      ],
    );
  }
}

/// "350 m" / "1.2 km" — shared by the app-bar walk/distance chip and the
/// "Bus stops at this station" rows.
String _formatDistance(int m) {
  if (m < 1000) return '$m m';
  final km = m / 1000.0;
  return '${km.toStringAsFixed(km.truncateToDouble() == km ? 0 : 1)} km';
}

// ─── Line pill ─────────────────────────────────────────────────────────────

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
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

// ─── Disruption card ─────────────────────────────────────────────────────────

class _DisruptionCard extends StatelessWidget {
  const _DisruptionCard({required this.alerts, required this.t});

  final List<TrainAlert> alerts;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(LyneRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: LyneSeverity.warning.color,
              ),
              const SizedBox(width: 8),
              Text(
                'Service disruption',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: t.fg,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...alerts.map((alert) => _AlertRow(alert: alert, t: t)),
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert, required this.t});

  final TrainAlert alert;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            alert.title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: LyneSeverity.warning.color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            alert.detail,
            style: TextStyle(fontSize: 12, color: t.dim),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          // Free service chips
          if (alert.freeBus || alert.freeShuttle) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (alert.freeBus)
                  _FreeChip(
                    label: 'Free bus rides',
                    icon: Icons.directions_bus_rounded,
                    t: t,
                  ),
                if (alert.freeShuttle)
                  _FreeChip(
                    label: 'Free MRT shuttle',
                    icon: Icons.train_rounded,
                    t: t,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FreeChip extends StatelessWidget {
  const _FreeChip({required this.label, required this.icon, required this.t});

  final String label;
  final IconData icon;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: t.surfaceHi,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: t.dim),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: t.dim,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Lift maintenance card ────────────────────────────────────────────────────

class _StationLiftCard extends StatelessWidget {
  const _StationLiftCard({required this.lifts, required this.t});

  final List<LiftMaintenance> lifts;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(LyneRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.build_rounded,
                size: 14,
                color: LyneSeverity.warning.color,
              ),
              const SizedBox(width: 8),
              Text(
                'Lift maintenance',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: t.fg,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...lifts.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: t.faint,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item.detail,
                      style: TextStyle(fontSize: 13, color: t.dim),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bus stops at this station ─────────────────────────────────────────────
// Nearest ≤3 bus stops within 400 m, each with its live soonest arrival.
// Mirrors ios-native/Leyne/WhereSia/WSMrtStationView.swift's busCard (the
// only iOS surface with this feature so far — reimplemented here in this
// screen's own Material 3 card language, not WhereSia's dark/mono style).

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
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(LyneRadius.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header now lives inside the panel (owner decision 2026-07-03,
          // matching WSCard's title-inside-panel layout) — was previously a
          // separate label rendered above the card.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              'BUS STOPS AT THIS STATION',
              style: t
                  .mono(10, weight: FontWeight.w600, color: t.dim)
                  .copyWith(letterSpacing: 0.8),
            ),
          ),
          for (var i = 0; i < stops.length; i++) ...[
            _BusStopRow(
              stop: stops[i],
              arrival: arrivals[stops[i].stopCode],
              onOpenStop: onOpenStop,
              t: t,
            ),
            if (i < stops.length - 1)
              Divider(
                color: t.line,
                height: 1,
                thickness: 1,
                indent: 16,
                endIndent: 16,
              ),
          ],
        ],
      ),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stop.stopName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.fg,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${stop.stopCode} · ${_formatDistance(stop.distanceM)}',
                  style: t.mono(11, color: t.dim),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (soonest == null)
            Text('—', style: TextStyle(fontSize: 13, color: t.faint))
          else
            _EtaLabel(sec: soonest.etaSec, t: t),
          if (callback != null) ...[
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 16, color: t.faint),
          ],
        ],
      ),
    );

    if (callback == null) return content;

    return Semantics(
      button: true,
      label: soonest == null
          ? '${stop.stopName}, ${stop.stopCode}, '
                '${_formatDistance(stop.distanceM)}'
          : '${stop.stopName}, ${stop.stopCode}, '
                '${_formatDistance(stop.distanceM)}, '
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

// ─── Station crowd headline (aggregate) ────────────────────────────────────
// Single "Station crowd · now" card: the station-level reading — worst
// across the station's matched line codes — with a plain-language hint and
// a full-width meter. Mirrors WSMrtStationView.swift's crowdCard headline
// (110-131). The per-line detail below (_CrowdSection/_LineCrowdCard)
// independently gates its own duplicate "current reading" row to
// interchanges only, per that same source's interchange check.

/// Small "live data" indicator — dot + LIVE — mirroring WSLiveBadge in
/// ios-native/Leyne/WhereSia/WSComponents.swift. No shared widget has been
/// extracted for this yet; soft_stop_screen.dart / soft_bus_screen.dart each
/// hand-roll the same dot(t.soon) + mono "LIVE"(t.soon) convention inline —
/// this mirrors that existing style rather than inventing a new one.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.t});

  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Live data',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: t.soon, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            'LIVE',
            style: t
                .mono(10, weight: FontWeight.w700, color: t.soon)
                .copyWith(letterSpacing: 0.8),
          ),
        ],
      ),
    );
  }
}

class _StationCrowdHeadlineCard extends StatelessWidget {
  const _StationCrowdHeadlineCard({
    required this.station,
    required this.lines,
    required this.crowdByLine,
    required this.t,
  });

  final MrtGeoStation station;
  final List<MRTLine> lines;
  final Map<MRTLine, List<StationCrowd>?> crowdByLine;
  final LyneTheme t;

  /// This station's matched reading on [line]: null while that line's crowd
  /// feed hasn't loaded yet, [CrowdLevel.unknown] once loaded but with no
  /// entry for any of this station's codes.
  CrowdLevel? _levelFor(MRTLine line) {
    final list = crowdByLine[line];
    if (list == null) return null;
    for (final crowd in list) {
      for (final code in station.codes) {
        if (crowd.code.toUpperCase() == code.toUpperCase()) return crowd.level;
      }
    }
    return CrowdLevel.unknown;
  }

  static int _severity(CrowdLevel level) {
    switch (level) {
      case CrowdLevel.low:
        return 1;
      case CrowdLevel.moderate:
        return 2;
      case CrowdLevel.high:
        return 3;
      case CrowdLevel.unknown:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Worst reading across the station's relevant lines, or null while every
    // one of them is still loading.
    var loaded = false;
    CrowdLevel? worst;
    for (final line in lines) {
      final level = _levelFor(line);
      if (level == null) continue;
      loaded = true;
      if (level != CrowdLevel.unknown &&
          (worst == null || _severity(level) > _severity(worst))) {
        worst = level;
      }
    }
    final level = loaded ? (worst ?? CrowdLevel.unknown) : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(LyneRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header now lives inside the panel (owner decision 2026-07-03,
          // matching WSCard's title-inside-panel layout in
          // WSMrtStationView.swift) — was previously a separate label
          // rendered above the card.
          Text(
            'STATION CROWD · NOW',
            style: t
                .mono(10, weight: FontWeight.w600, color: t.dim)
                .copyWith(letterSpacing: 0.8),
          ),
          const SizedBox(height: 10),
          if (level == null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: t.dim,
                  ),
                ),
                const SizedBox(width: 8),
                Text('Loading…', style: TextStyle(fontSize: 13, color: t.dim)),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _crowdLabel(level),
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: t.fg,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _crowdHeadlineHint(level),
                            style: t.mono(11, color: t.dim),
                          ),
                        ],
                      ),
                    ),
                    // LIVE badge — mirrors WSMrtStationView.swift's
                    // crowdCard (`if crowdNow != .unknown { WSLiveBadge() }`):
                    // top-aligned with the crowd word, hidden while loading
                    // or when the reading is unknown.
                    if (level != CrowdLevel.unknown) _LiveBadge(t: t),
                  ],
                ),
                const SizedBox(height: 10),
                _CrowdMeterBar(level: level, t: t),
              ],
            ),
        ],
      ),
    );
  }
}

/// Plain-language hint under the crowd word. Mirrors CrowdLevel.wsHint in
/// ios-native/Leyne/WhereSia/WSFormat.swift.
String _crowdHeadlineHint(CrowdLevel level) {
  switch (level) {
    case CrowdLevel.low:
      return 'Plenty of room';
    case CrowdLevel.moderate:
      return 'Some queues at gantries';
    case CrowdLevel.high:
      return 'Busy — expect a wait';
    case CrowdLevel.unknown:
      return 'No live reading';
  }
}

/// Full-width horizontal crowd meter for the headline card.
class _CrowdMeterBar extends StatelessWidget {
  const _CrowdMeterBar({required this.level, required this.t});

  final CrowdLevel level;
  final LyneTheme t;

  static const double _height = 8;

  @override
  Widget build(BuildContext context) {
    final fraction = _crowdFraction(level);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: _height,
          decoration: BoxDecoration(
            color: t.surfaceHi,
            borderRadius: BorderRadius.circular(_height / 2),
          ),
          alignment: Alignment.centerLeft,
          child: AnimatedContainer(
            duration: LyneMotion.emphasis,
            curve: LyneMotion.enter,
            width: constraints.maxWidth * fraction,
            height: _height,
            decoration: BoxDecoration(
              color: _crowdColor(level, t),
              borderRadius: BorderRadius.circular(_height / 2),
            ),
          ),
        );
      },
    );
  }
}

// ─── Live crowd section ───────────────────────────────────────────────────────

class _CrowdSection extends StatelessWidget {
  const _CrowdSection({
    required this.station,
    required this.lines,
    required this.crowdByLine,
    required this.t,
  });

  final MrtGeoStation station;
  final List<MRTLine> lines;
  final Map<MRTLine, List<StationCrowd>?> crowdByLine;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'BY PLATFORM',
            style: t
                .mono(10, weight: FontWeight.w600, color: t.dim)
                .copyWith(letterSpacing: 0.8),
          ),
        ),
        ...lines.map((line) {
          final crowdList = crowdByLine[line];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _LineCrowdCard(
              line: line,
              station: station,
              crowdList: crowdList,
              t: t,
            ),
          );
        }),
      ],
    );
  }
}

/// Find a StationCrowd entry for this station from [list] by matching
/// against the station's codes. Mirrors SoftMrtStationView.swift crowd lookup.
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

/// Per-platform crowd row for interchanges — line chip + name + reading.
/// (Forecast moved to its own station-level _ForecastCard, iOS parity.)
class _LineCrowdCard extends StatelessWidget {
  const _LineCrowdCard({
    required this.line,
    required this.station,
    required this.crowdList,
    required this.t,
  });

  final MRTLine line;
  final MrtGeoStation station;
  final List<StationCrowd>? crowdList;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    final matched = _matchCrowd(crowdList, station);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Line code chip.
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: line.color,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              line.code,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${line.displayName} Line',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.fg,
                  ),
                ),
                const SizedBox(height: 3),
                // Current crowd level indicator row.
                if (crowdList == null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: t.dim,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Loading…',
                        style: TextStyle(fontSize: 12, color: t.dim),
                      ),
                    ],
                  )
                else if (matched == null)
                  Text(
                    'Unavailable',
                    style: TextStyle(fontSize: 12, color: t.faint),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _crowdColor(matched.level, t),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _crowdLabel(matched.level),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: matched.level == CrowdLevel.unknown
                              ? t.dim
                              : t.fg,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          // Right-aligned station code for the matched entry.
          if (matched != null && matched.level != CrowdLevel.unknown) ...[
            const SizedBox(width: 12),
            Text(
              matched.code,
              style: TextStyle(
                fontSize: 11,
                color: t.faint,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Station-level crowd forecast card — the rest of today's PCDForecast
/// series as ~6 half-hour bars with the "now" slot highlighted and a
/// "busiest around" caption. Its own section at the end of the screen,
/// mirroring WSMrtStationView.swift's forecastCard.
class _ForecastCard extends StatelessWidget {
  const _ForecastCard({
    required this.station,
    required this.line,
    required this.forecastRawByLine,
    required this.t,
  });

  final MrtGeoStation station;
  final MRTLine line;
  final Map<MRTLine, List<LtaStationForecast>> forecastRawByLine;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    final intervals = _stationIntervals(forecastRawByLine[line], station);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header now lives inside the panel (owner decision 2026-07-03,
          // matching WSCard's title-inside-panel layout) — was previously a
          // separate label rendered above the card.
          Text(
            'CROWD FORECAST · TODAY',
            style: t
                .mono(10, weight: FontWeight.w600, color: t.dim)
                .copyWith(letterSpacing: 0.8),
          ),
          const SizedBox(height: 10),
          if (intervals.isNotEmpty)
            _ForecastChart(intervals: intervals, t: t)
          else
            Text(
              'Forecast unavailable right now.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: t.dim,
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Crowd forecast chart ───────────────────────────────────────────────────

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
  const _ForecastChart({required this.intervals, required this.t});

  final List<LtaStationForecastInterval> intervals;
  final LyneTheme t;

  /// Builds the ~6-bar upcoming window: one slot back from "now" (so the
  /// active slot anchors the chart) through the next several. Windowing +
  /// the timezone-safe local start time now live in [ForecastWindow] (data
  /// layer, unit-tested) — see that file for why `.toLocal()` matters here.
  List<_ForecastPoint> _window(BuildContext context) {
    final now = DateTime.now();
    final use24h = MediaQuery.of(context).alwaysUse24HourFormat;
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < points.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: _ForecastBar(point: points[i], t: t),
              ),
            ],
          ],
        ),
        if (peak != null) ...[
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: t.dim,
              ),
              children: [
                const TextSpan(text: 'Busiest around '),
                TextSpan(
                  text: peak.time,
                  style: TextStyle(fontWeight: FontWeight.w700, color: t.fg),
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
  const _ForecastBar({required this.point, required this.t});

  final _ForecastPoint point;
  final LyneTheme t;

  static const double _trackHeight = 38;

  @override
  Widget build(BuildContext context) {
    final fraction = _crowdFraction(point.level);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: _trackHeight,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: t.surfaceHi,
            borderRadius: BorderRadius.circular(6),
            border: point.isNow ? Border.all(color: t.fg, width: 1.5) : null,
          ),
          alignment: Alignment.bottomCenter,
          child: AnimatedContainer(
            duration: LyneMotion.emphasis,
            curve: LyneMotion.enter,
            width: double.infinity,
            height: (_trackHeight - 4) * fraction,
            decoration: BoxDecoration(
              color: _crowdColor(point.level, t),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          point.time,
          style: TextStyle(
            fontSize: 9,
            fontWeight: point.isNow ? FontWeight.w700 : FontWeight.w500,
            color: point.isNow ? t.fg : t.faint,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ─── Crowd helpers ────────────────────────────────────────────────────────────

/// Crowd indicator colour — NEUTRAL ink (owner decision 2026-07-03, iOS
/// WhereSia rule: crowd is never colour-coded; the level is carried by the
/// meter's fill length / bar height + the word, not a hue).
Color _crowdColor(CrowdLevel level, LyneTheme t) {
  return level == CrowdLevel.unknown ? t.faint : t.fg;
}

String _crowdLabel(CrowdLevel level) {
  switch (level) {
    case CrowdLevel.low:
      return 'Low';
    case CrowdLevel.moderate:
      return 'Moderate';
    case CrowdLevel.high:
      return 'High';
    case CrowdLevel.unknown:
      return 'Unknown';
  }
}
