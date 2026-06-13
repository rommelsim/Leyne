// SoftMrtScreen — MRT tab root (Leyne 2.7 Android, Phase 2).
//
// Flutter/Android port of ios-native/Leyne/V2/SoftMrtView.swift.
//
// Layout (mirrors SoftMrtView.swift):
//   1. Title block — "MRT" + "Stations near you"
//   2. System map button → MrtMapScreen (full-screen sheet)
//   3. "Closest to you" section — up to 6 nearest stations from MrtGeo
//   4. "All lines" section — existing line-status board (intact)
//
// Four LTA DataMall feeds:
//   • TrainServiceAlerts       → per-line operating status (disrupted / normal)
//   • FacilitiesMaintenance v2 → network-wide lifts currently under maintenance
//   • PCDRealTime              → live per-station crowdedness, fetched lazily on expand
//   • PCDForecast              → 30-min crowd forecast, shown via Now/Next toggle
//
// Free for all users. Crowd colours (green/amber/red) and MRT line colours are
// the only colour in the otherwise-monochrome app — intentional, don't remove.

import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../data/mrt_geo.dart';
import '../../data/mrt_stations.dart';
import '../../services/location_service.dart';
import '../../theme.dart';
import '../../widgets/v2/soft_components.dart';
import '../../widgets/v2/soft_tab_bar.dart';
import 'mrt_map_screen.dart';

class SoftMrtScreen extends StatefulWidget {
  const SoftMrtScreen({
    super.key,
    required this.onTab,
    required this.onOpenStation,
  });

  final ValueChanged<SoftTab> onTab;

  /// Called when the user taps a nearest-station card. The root pushes the
  /// station detail screen. Walk/distance context is passed alongside.
  final void Function(MrtGeoStation station, int distanceM, int walkMin)
  onOpenStation;

  @override
  State<SoftMrtScreen> createState() => _SoftMrtScreenState();
}

class _SoftMrtScreenState extends State<SoftMrtScreen> {
  /// The line whose live station crowd is currently expanded (one at a time).
  MRTLine? _expandedLine;

  /// Whether the crowd section is showing the 30-min forecast (true) or live
  /// realtime data (false). Reset to false whenever the expanded line changes.
  bool _showForecast = false;

  /// Most-recently computed nearest station list (rebuilt on location changes).
  List<MrtNearestResult> _nearest = [];

  @override
  void initState() {
    super.initState();
    LocationService.shared.addListener(_onLocationChanged);
    // Non-force refresh on mount — honours the staleness windows.
    _refresh(force: false);
    // Kick off location if already authorised; mirrors SoftHomeScreen.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await LocationService.shared.startIfAuthorized();
      _rebuildNearest();
    });
  }

  @override
  void dispose() {
    LocationService.shared.removeListener(_onLocationChanged);
    super.dispose();
  }

  void _onLocationChanged() => _rebuildNearest();

  void _rebuildNearest() {
    final loc = LocationService.shared.lastLocation;
    if (loc == null) {
      if (_nearest.isNotEmpty) setState(() => _nearest = []);
      return;
    }
    final results = MrtGeo.nearest(lat: loc.lat, lon: loc.lon, limit: 6);
    setState(() => _nearest = results);
  }

  void _refresh({required bool force}) {
    final ds = DataStore.shared;
    ds.refreshTrainAlertsIfStale(force: force);
    ds.refreshLiftMaintenanceIfStale(force: force);
    if (_expandedLine != null) {
      if (_showForecast) {
        ds.refreshForecast(_expandedLine!, force: force);
      } else {
        ds.refreshCrowd(_expandedLine!, force: force);
      }
    }
    // Also rebuild nearest with fresh location.
    _rebuildNearest();
  }

  void _openMap() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const MrtMapScreen(),
      ),
    );
  }

  /// Disrupted lines derived from the LTA alerts, keyed by MRTLine enum.
  Map<MRTLine, TrainAlert> _disruptedLines(List<TrainAlert> alerts) {
    final map = <MRTLine, TrainAlert>{};
    for (final alert in alerts) {
      if (alert.line != null) map[alert.line!] = alert;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ListenableBuilder(
      listenable: Listenable.merge([DataStore.shared, LocationService.shared]),
      builder: (context, _) {
        final ds = DataStore.shared;
        final disrupted = _disruptedLines(ds.trainAlerts);
        final loc = LocationService.shared.lastLocation;

        return Scaffold(
          backgroundColor: t.bg,
          body: RefreshIndicator(
            onRefresh: () async => _refresh(force: true),
            color: t.fg,
            backgroundColor: t.surface,
            child: CustomScrollView(
              slivers: [
                _buildAppBar(t),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // ── System map button ──────────────────────────────
                      _MapButton(onTap: _openMap, t: t),
                      const SizedBox(height: 20),

                      // ── "Closest to you" nearest stations ──────────────
                      const Eyebrow('Closest to you'),
                      const SizedBox(height: 10),
                      if (loc == null)
                        _NoLocationCard(
                          onUseLocation: () async {
                            await LocationService.shared.requestAndStart();
                            _rebuildNearest();
                          },
                          t: t,
                        )
                      else if (_nearest.isEmpty)
                        _EmptyNearestCard(t: t)
                      else ...[
                        ..._nearest.map(
                          (result) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _NearestStationCard(
                              result: result,
                              onTap: () => widget.onOpenStation(
                                result.station,
                                result.distanceM,
                                result.walkMin,
                              ),
                              t: t,
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // ── "All lines" board (existing) ───────────────────
                      const Eyebrow('All lines'),
                      const SizedBox(height: 10),
                      _OverallBanner(disrupted: disrupted, t: t),
                      _LiftMaintenanceCard(items: ds.liftMaintenance, t: t),
                      const SizedBox(height: 4),
                      _LinesList(
                        disrupted: disrupted,
                        crowdByLine: ds.crowdByLine,
                        forecastByLine: ds.forecastByLine,
                        expandedLine: _expandedLine,
                        showForecast: _showForecast,
                        onToggle: (line) {
                          setState(() {
                            if (_expandedLine == line) {
                              _expandedLine = null;
                            } else {
                              _expandedLine = line;
                              _showForecast = false;
                              DataStore.shared.refreshCrowd(line);
                            }
                          });
                        },
                        onForecastToggle: (show) {
                          setState(() {
                            _showForecast = show;
                            if (_expandedLine != null) {
                              if (show) {
                                DataStore.shared.refreshForecast(
                                  _expandedLine!,
                                );
                              } else {
                                DataStore.shared.refreshCrowd(_expandedLine!);
                              }
                            }
                          });
                        },
                        t: t,
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: SoftBottomBar(
            selection: SoftTab.mrt,
            onSelect: widget.onTab,
          ),
        );
      },
    );
  }

  SliverAppBar _buildAppBar(LyneTheme t) {
    return SliverAppBar(
      backgroundColor: t.bg,
      surfaceTintColor: Colors.transparent,
      // floating/snap disabled so the app bar does not animate in from the top
      // when the MRT tab is mounted fresh (e.g. on a tab switch). Plain scroll-
      // away behaviour matches the other V2 tab screens.
      pinned: false,
      floating: false,
      snap: false,
      expandedHeight: null,
      flexibleSpace: null,
      titleSpacing: 20,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'MRT',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: t.fg,
              letterSpacing: -0.5,
            ),
          ),
          Text(
            'Stations near you',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: t.dim,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Overall disruption banner ────────────────────────────────────────────────

class _OverallBanner extends StatelessWidget {
  const _OverallBanner({required this.disrupted, required this.t});

  final Map<MRTLine, TrainAlert> disrupted;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    final count = disrupted.length;
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(LyneRadius.lg),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 22,
              color: Colors.orange,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count line${count == 1 ? '' : 's'} disrupted',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: t.fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap a line below for details.',
                    style: TextStyle(fontSize: 13, color: t.dim),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Lift maintenance card ────────────────────────────────────────────────────

class _LiftMaintenanceCard extends StatelessWidget {
  const _LiftMaintenanceCard({required this.items, required this.t});

  final List<LiftMaintenance> items;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
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
                const Spacer(),
                Text(
                  '${items.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: t.dim,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...items.map(
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.stationName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: t.fg,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            item.detail,
                            style: TextStyle(fontSize: 12, color: t.dim),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Per-line list ────────────────────────────────────────────────────────────

class _LinesList extends StatelessWidget {
  const _LinesList({
    required this.disrupted,
    required this.crowdByLine,
    required this.forecastByLine,
    required this.expandedLine,
    required this.showForecast,
    required this.onToggle,
    required this.onForecastToggle,
    required this.t,
  });

  final Map<MRTLine, TrainAlert> disrupted;
  final Map<MRTLine, List<StationCrowd>?> crowdByLine;
  final Map<MRTLine, List<StationCrowd>?> forecastByLine;
  final MRTLine? expandedLine;
  final bool showForecast;
  final ValueChanged<MRTLine> onToggle;
  final ValueChanged<bool> onForecastToggle;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: MRTLine.values.map((line) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _LineRow(
            line: line,
            alert: disrupted[line],
            crowdData: crowdByLine[line],
            forecastData: forecastByLine[line],
            isExpanded: expandedLine == line,
            showForecast: showForecast,
            onToggle: () => onToggle(line),
            onForecastToggle: onForecastToggle,
            t: t,
          ),
        );
      }).toList(),
    );
  }
}

// ─── Single line row (header + expandable crowd section) ─────────────────────

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.line,
    required this.alert,
    required this.crowdData,
    required this.forecastData,
    required this.isExpanded,
    required this.showForecast,
    required this.onToggle,
    required this.onForecastToggle,
    required this.t,
  });

  final MRTLine line;
  final TrainAlert? alert;
  final List<StationCrowd>? crowdData;
  final List<StationCrowd>? forecastData;
  final bool isExpanded;
  final bool showForecast;
  final VoidCallback onToggle;
  final ValueChanged<bool> onForecastToggle;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: LyneMotion.emphasis,
      curve: LyneMotion.standardCurve,
      alignment: Alignment.topCenter,
      child: Container(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row — always tappable.
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: _LineHeader(
                  line: line,
                  alert: alert,
                  isExpanded: isExpanded,
                  t: t,
                ),
              ),
            ),
            // Crowd section — only when expanded.
            if (isExpanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: _CrowdSection(
                  crowdData: crowdData,
                  forecastData: forecastData,
                  showForecast: showForecast,
                  onForecastToggle: onForecastToggle,
                  t: t,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Line header ──────────────────────────────────────────────────────────────

class _LineHeader extends StatelessWidget {
  const _LineHeader({
    required this.line,
    required this.alert,
    required this.isExpanded,
    required this.t,
  });

  final MRTLine line;
  final TrainAlert? alert;
  final bool isExpanded;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    final disrupted = alert != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Coloured line-code chip.
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
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: t.fg,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                disrupted ? (alert!.detail) : 'Operating normally',
                style: TextStyle(
                  fontSize: 13,
                  color: disrupted ? Colors.orange : t.dim,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              // Free service chips — only shown when disrupted and at least
              // one free-service option is available.
              if (disrupted && (alert!.freeBus || alert!.freeShuttle)) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (alert!.freeBus)
                      _FreeServiceChip(
                        label: 'Free bus rides',
                        icon: Icons.directions_bus_rounded,
                        t: t,
                      ),
                    if (alert!.freeShuttle)
                      _FreeServiceChip(
                        label: 'Free MRT shuttle',
                        icon: Icons.tram_rounded,
                        t: t,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          children: [
            Icon(
              disrupted ? Icons.error_rounded : Icons.check_circle_rounded,
              size: 16,
              color: disrupted
                  ? Colors.orange
                  : Colors.green.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 4),
            AnimatedRotation(
              turns: isExpanded ? 0.5 : 0,
              duration: LyneMotion.emphasis,
              curve: LyneMotion.standardCurve,
              child: Icon(Icons.expand_more_rounded, size: 18, color: t.faint),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Crowd section (expanded) ─────────────────────────────────────────────────

class _CrowdSection extends StatelessWidget {
  const _CrowdSection({
    required this.crowdData,
    required this.forecastData,
    required this.showForecast,
    required this.onForecastToggle,
    required this.t,
  });

  final List<StationCrowd>? crowdData;
  final List<StationCrowd>? forecastData;
  final bool showForecast;
  final ValueChanged<bool> onForecastToggle;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    final activeData = showForecast ? forecastData : crowdData;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: t.line, height: 24, thickness: 1),
        // Now / Next 30 min toggle — monochrome segmented control.
        _CrowdToggle(
          showForecast: showForecast,
          onToggle: onForecastToggle,
          t: t,
        ),
        const SizedBox(height: 12),
        if (activeData == null) ...[
          // Loading state.
          Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: t.dim,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                showForecast ? 'Loading forecast…' : 'Loading live crowd…',
                style: TextStyle(fontSize: 13, color: t.dim),
              ),
            ],
          ),
        ] else if (activeData.isEmpty) ...[
          Text(
            showForecast
                ? 'Forecast unavailable right now.'
                : 'Crowd data unavailable right now.',
            style: TextStyle(fontSize: 13, color: t.faint),
          ),
        ] else ...[
          _CrowdLegend(t: t),
          const SizedBox(height: 10),
          ..._sortedCrowd(activeData).map(
            (stop) => Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: _CrowdRow(stop: stop, t: t),
            ),
          ),
        ],
      ],
    );
  }

  /// Sort by the numeric suffix of the station code (e.g. "EW13" → 13).
  /// Mirrors iOS SoftMrtView.swift: sortedCrowd / codeNum.
  static List<StationCrowd> _sortedCrowd(List<StationCrowd> items) {
    int codeNum(String code) {
      final match = RegExp(r'\d+').firstMatch(code);
      return match == null ? 0 : int.tryParse(match.group(0)!) ?? 0;
    }

    final sorted = List<StationCrowd>.from(items);
    sorted.sort((a, b) => codeNum(a.code).compareTo(codeNum(b.code)));
    return sorted;
  }
}

// ─── Crowd toggle (Now / Next 30 min) ────────────────────────────────────────

class _CrowdToggle extends StatelessWidget {
  const _CrowdToggle({
    required this.showForecast,
    required this.onToggle,
    required this.t,
  });

  final bool showForecast;
  final ValueChanged<bool> onToggle;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: t.surfaceHi,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleSegment(
            label: 'Now',
            selected: !showForecast,
            onTap: () => onToggle(false),
            t: t,
          ),
          _ToggleSegment(
            label: 'Next 30 min',
            selected: showForecast,
            onTap: () => onToggle(true),
            t: t,
          ),
        ],
      ),
    );
  }
}

class _ToggleSegment extends StatelessWidget {
  const _ToggleSegment({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.t,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? t.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? t.fg : t.dim,
          ),
        ),
      ),
    );
  }
}

// ─── Free service chip ────────────────────────────────────────────────────────

class _FreeServiceChip extends StatelessWidget {
  const _FreeServiceChip({
    required this.label,
    required this.icon,
    required this.t,
  });

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

// ─── Crowd legend ─────────────────────────────────────────────────────────────

class _CrowdLegend extends StatelessWidget {
  const _CrowdLegend({required this.t});

  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    const levels = [CrowdLevel.low, CrowdLevel.moderate, CrowdLevel.high];
    return Row(
      children: [
        ...levels.map(
          (level) => Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _crowdColor(level, t: t),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  _crowdLabel(level),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: t.dim,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Single crowd row ─────────────────────────────────────────────────────────

class _CrowdRow extends StatelessWidget {
  const _CrowdRow({required this.stop, required this.t});

  final StationCrowd stop;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    final unknown = stop.level == CrowdLevel.unknown;
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: _crowdColor(stop.level, t: t),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            stop.name,
            style: TextStyle(fontSize: 15, color: unknown ? t.dim : t.fg),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _crowdLabel(stop.level),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: t.dim,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ─── Crowd helpers ────────────────────────────────────────────────────────────

/// Crowd level dot colour. `t` is used for the unknown/faint slot so the
/// colour adapts to dark/light mode correctly — the others are semantic
/// transit colours that don't change between modes.
Color _crowdColor(CrowdLevel level, {LyneTheme? t}) {
  switch (level) {
    case CrowdLevel.low:
      return Colors.green;
    case CrowdLevel.moderate:
      return Colors.orange;
    case CrowdLevel.high:
      return Colors.red;
    case CrowdLevel.unknown:
      return t?.faint ?? const Color.fromRGBO(128, 128, 128, 0.35);
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
      return '—'; // em dash
  }
}

// ─── System map button ────────────────────────────────────────────────────────

class _MapButton extends StatelessWidget {
  const _MapButton({required this.onTap, required this.t});

  final VoidCallback onTap;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(LyneRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(LyneRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: t.surfaceHi,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.map_rounded, size: 20, color: t.fg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'System map',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: t.fg,
                      ),
                    ),
                    Text(
                      'Zoomable MRT network map',
                      style: TextStyle(fontSize: 12, color: t.dim),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: t.faint),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Nearest station card ─────────────────────────────────────────────────────

/// A single nearby MRT station card — mirrors the Bus nearby card style.
/// Station name + coloured line-code pills + walk/distance + trailing chevron.
class _NearestStationCard extends StatelessWidget {
  const _NearestStationCard({
    required this.result,
    required this.onTap,
    required this.t,
  });

  final MrtNearestResult result;
  final VoidCallback onTap;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    final station = result.station;
    return Semantics(
      button: true,
      label: 'Open ${station.name} station',
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(LyneRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(LyneRadius.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Leading tram icon tile.
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.surfaceHi,
                    borderRadius: BorderRadius.circular(LyneRadius.md),
                  ),
                  child: Icon(Icons.tram_rounded, size: 20, color: t.fg),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        station.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: t.fg,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      // Line-code pills row.
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: station.codes.map((code) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: lineColorFor(code),
                              borderRadius: BorderRadius.circular(
                                LyneRadius.full,
                              ),
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
                        }).toList(),
                      ),
                      const SizedBox(height: 5),
                      // Walk + distance meta.
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.directions_walk, size: 12, color: t.dim),
                          const SizedBox(width: 3),
                          Text(
                            '${result.walkMin < 1 ? 1 : result.walkMin} min',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: t.dim,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '·',
                            style: TextStyle(fontSize: 12, color: t.faint),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _fmtDist(result.distanceM),
                            style: TextStyle(
                              fontSize: 12,
                              color: t.faint,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, size: 18, color: t.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _fmtDist(int m) {
    if (m < 1000) return '$m m';
    final km = m / 1000.0;
    return '${km.toStringAsFixed(km.truncateToDouble() == km ? 0 : 1)} km';
  }
}

// ─── No-location empty state ──────────────────────────────────────────────────

class _NoLocationCard extends StatelessWidget {
  const _NoLocationCard({required this.onUseLocation, required this.t});

  final VoidCallback onUseLocation;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(LyneRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.surfaceHi,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.location_off_rounded, size: 24, color: t.dim),
          ),
          const SizedBox(height: 12),
          Text(
            'Location off',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: t.fg,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Turn on location to see stations near you.',
            style: TextStyle(fontSize: 13, color: t.dim),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onUseLocation,
            style: FilledButton.styleFrom(
              backgroundColor: t.accent,
              foregroundColor: t.onAccent,
            ),
            child: const Text('Use location'),
          ),
        ],
      ),
    );
  }
}

// ─── Empty nearest state (geo not yet loaded) ─────────────────────────────────

class _EmptyNearestCard extends StatelessWidget {
  const _EmptyNearestCard({required this.t});

  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(LyneRadius.lg),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: t.dim),
          ),
          const SizedBox(width: 12),
          Text(
            'Finding nearby stations…',
            style: TextStyle(fontSize: 13, color: t.dim),
          ),
        ],
      ),
    );
  }
}
