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
  });

  final MrtGeoStation station;
  final VoidCallback onBack;
  final ValueChanged<SoftTab> onTab;
  final SoftTab tabSelection;

  /// Walk/distance context — present when opened from the nearest-stations
  /// section, null when opened from Search.
  final int? distanceM;
  final int? walkMin;

  @override
  State<SoftMrtStationScreen> createState() => _SoftMrtStationScreenState();
}

class _SoftMrtStationScreenState extends State<SoftMrtStationScreen> {
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
      bottomNavigationBar: SoftBottomBar(
        selection: widget.tabSelection,
        onSelect: widget.onTab,
      ),
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
                      // Live crowd section (one card per relevant line)
                      if (lines.isNotEmpty) ...[
                        _CrowdSection(
                          station: widget.station,
                          lines: lines,
                          crowdByLine: ds.crowdByLine,
                          forecastByLine: ds.forecastByLine,
                          t: t,
                        ),
                      ],
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
        return IconButton(
          icon: Icon(
            saved ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 22,
            color: saved ? t.soon : t.fg,
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
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.station.name,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: t.fg,
              letterSpacing: -0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          // Line code pills + optional walk/distance.
          Row(
            children: [
              // Line code pills.
              Wrap(
                spacing: 5,
                children: widget.station.codes.map((code) {
                  return _LinePill(code: code);
                }).toList(),
              ),
              // Walk/distance context (only when opened from nearby).
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
      ),
    );
  }

  static String _formatDistance(int m) {
    if (m < 1000) return '$m m';
    final km = m / 1000.0;
    return '${km.toStringAsFixed(km.truncateToDouble() == km ? 0 : 1)} km';
  }
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
              const Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: Colors.orange,
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
              color: Colors.orange,
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
              const Icon(Icons.build_rounded, size: 14, color: Colors.orange),
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

// ─── Live crowd section ───────────────────────────────────────────────────────

class _CrowdSection extends StatelessWidget {
  const _CrowdSection({
    required this.station,
    required this.lines,
    required this.crowdByLine,
    required this.forecastByLine,
    required this.t,
  });

  final MrtGeoStation station;
  final List<MRTLine> lines;
  final Map<MRTLine, List<StationCrowd>?> crowdByLine;
  final Map<MRTLine, List<StationCrowd>?> forecastByLine;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'LIVE CROWD',
            style: t
                .mono(10, weight: FontWeight.w600, color: t.dim)
                .copyWith(letterSpacing: 0.8),
          ),
        ),
        ...lines.map((line) {
          final crowdList = crowdByLine[line];
          final forecastList = forecastByLine[line];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _LineCrowdCard(
              line: line,
              station: station,
              crowdList: crowdList,
              forecastList: forecastList,
              t: t,
            ),
          );
        }),
      ],
    );
  }
}

class _LineCrowdCard extends StatelessWidget {
  const _LineCrowdCard({
    required this.line,
    required this.station,
    required this.crowdList,
    required this.forecastList,
    required this.t,
  });

  final MRTLine line;
  final MrtGeoStation station;
  final List<StationCrowd>? crowdList;
  final List<StationCrowd>? forecastList;
  final LyneTheme t;

  /// Find a StationCrowd entry for this station from [list] by matching
  /// against the station's codes. Mirrors SoftMrtStationView.swift crowd lookup.
  StationCrowd? _matchFrom(List<StationCrowd>? list) {
    if (list == null) return null;
    for (final crowd in list) {
      for (final code in station.codes) {
        if (crowd.code.toUpperCase() == code.toUpperCase()) return crowd;
      }
    }
    return null;
  }

  int _levelRank(CrowdLevel l) {
    switch (l) {
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

  /// Trend arrow comparing now vs the 30-min forecast.
  /// Mirrors SoftMrtStationView.swift trendIcon(now:next:).
  IconData _trendIcon(CrowdLevel now, CrowdLevel next) {
    final a = _levelRank(now);
    final b = _levelRank(next);
    if (a == 0 || b == 0) return Icons.arrow_forward_rounded;
    if (b > a) return Icons.arrow_upward_rounded;
    if (b < a) return Icons.arrow_downward_rounded;
    return Icons.arrow_forward_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final matched = _matchFrom(crowdList);
    final forecastMatch = _matchFrom(forecastList);

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
                else ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _crowdColor(matched.level),
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
                  // 30-min forecast trend — mirrors SoftMrtStationView.swift.
                  // Shown when both current and forecast levels are known.
                  if (matched.level != CrowdLevel.unknown &&
                      forecastMatch != null &&
                      forecastMatch.level != CrowdLevel.unknown) ...[
                    const SizedBox(height: 3),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _trendIcon(matched.level, forecastMatch.level),
                          size: 10,
                          color: t.dim,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'In 30 min · ${_crowdLabel(forecastMatch.level)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: t.dim,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
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

// ─── Crowd helpers ────────────────────────────────────────────────────────────

Color _crowdColor(CrowdLevel level) {
  switch (level) {
    case CrowdLevel.low:
      return Colors.green;
    case CrowdLevel.moderate:
      return Colors.orange;
    case CrowdLevel.high:
      return Colors.red;
    case CrowdLevel.unknown:
      return const Color.fromRGBO(128, 128, 128, 0.35);
  }
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
