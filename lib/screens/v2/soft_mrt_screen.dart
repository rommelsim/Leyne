// SoftMrtScreen — MRT tab root (Leyne 2.7 Android, Phase 3 redesign).
//
// Flutter/Android port of ios-native/Leyne/V2/SoftMrtView.swift (Phase 3).
//
// Layout (mirrors SoftMrtView.swift Phase 3):
//   1. SliverAppBar — "MRT" title + map icon action button (top-right).
//   2. Disruption banner — compact, only when a line is affected.
//   3. NETWORK section:
//      a. Nearest-MRT featured tile (full-width, folded in from old
//         "Closest to you" section) — shown only when located.
//      b. 2-column grid of tappable line tiles (badge + status + name +
//         "Normal service / Disrupted").
//
// Navigation:
//   • Tap a line tile → pushes SoftMrtLineScreen (new, internal Navigator).
//   • Tap the nearest-station featured tile → pushes SoftMrtStationScreen.
//   • Map button → pushes MrtMapScreen (fullscreenDialog).
//   • onOpenStation callback still accepted (SoftRoot may wire it for Search)
//     but the MRT screen no longer calls it internally.
//
// DataStore getters used (READ-ONLY):
//   ds.trainAlerts, ds.crowdByLine, ds.forecastByLine, ds.liftMaintenance
// DataStore mutators used:
//   ds.refreshTrainAlertsIfStale, ds.refreshLiftMaintenanceIfStale

import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../data/mrt_geo.dart';
import '../../data/mrt_stations.dart';
import '../../services/location_service.dart';
import '../../theme.dart';
import '../../widgets/v2/soft_components.dart';
import '../../widgets/v2/soft_tab_bar.dart';
import 'mrt_map_screen.dart';
import 'soft_mrt_line_screen.dart';
import 'soft_mrt_station_screen.dart';

class SoftMrtScreen extends StatefulWidget {
  const SoftMrtScreen({
    super.key,
    required this.onTab,
    required this.onOpenStation,
  });

  final ValueChanged<SoftTab> onTab;

  /// Legacy callback kept so SoftRoot's constructor signature is unchanged.
  /// The MRT screen no longer calls it internally — navigation now happens
  /// via an internal Navigator.push. Search may still supply it for its own
  /// station-open path.
  final void Function(MrtGeoStation station, int distanceM, int walkMin)
  onOpenStation;

  @override
  State<SoftMrtScreen> createState() => _SoftMrtScreenState();
}

class _SoftMrtScreenState extends State<SoftMrtScreen> {
  /// Most-recently computed nearest station list, rebuilt on location changes.
  /// Only the first entry is used (featured tile). Capped at 1 to avoid
  /// doing unnecessary work for entries we don't render on this screen.
  List<MrtNearestResult> _nearest = [];

  @override
  void initState() {
    super.initState();
    LocationService.shared.addListener(_onLocationChanged);
    _refresh(force: false);
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
    final results = MrtGeo.nearest(lat: loc.lat, lon: loc.lon, limit: 1);
    setState(() => _nearest = results);
  }

  void _refresh({required bool force}) {
    DataStore.shared.refreshTrainAlertsIfStale(force: force);
    DataStore.shared.refreshLiftMaintenanceIfStale(force: force);
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

  void _openLine(MRTLine line) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SoftMrtLineScreen(
          line: line,
          onTab: widget.onTab,
          tabSelection: SoftTab.mrt,
        ),
      ),
    );
  }

  void _openStation(MrtGeoStation station, {int? distanceM, int? walkMin}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SoftMrtStationScreen(
          station: station,
          onBack: () => Navigator.of(context).pop(),
          onTab: widget.onTab,
          tabSelection: SoftTab.mrt,
          distanceM: distanceM,
          walkMin: walkMin,
        ),
      ),
    );
  }

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
                      // ── Disruption banner ───────────────────────────────
                      _DisruptionBanner(disrupted: disrupted, t: t),
                      const SizedBox(height: 20),

                      // ── NETWORK section header ──────────────────────────
                      const Eyebrow('Network'),
                      const SizedBox(height: 10),

                      // ── Nearest MRT featured tile (full-width) ──────────
                      if (loc != null && _nearest.isNotEmpty)
                        _NearestFeaturedTile(
                          result: _nearest.first,
                          onTap: () => _openStation(
                            _nearest.first.station,
                            distanceM: _nearest.first.distanceM,
                            walkMin: _nearest.first.walkMin,
                          ),
                          t: t,
                        ),
                      if (loc == null)
                        _NoLocationHint(
                          onUseLocation: () async {
                            await LocationService.shared.requestAndStart();
                            _rebuildNearest();
                          },
                          t: t,
                        ),

                      const SizedBox(height: 10),

                      // ── 2-column line grid ─────────────────────────────
                      _LineGrid(
                        disrupted: disrupted,
                        onTapLine: _openLine,
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
      pinned: false,
      floating: false,
      snap: false,
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
      actions: [
        // Direct map button — no ••• menu (mirrors iOS Phase 3 titleBlock).
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: IconButton(
            icon: Icon(Icons.map_rounded, size: 22, color: t.fg),
            onPressed: _openMap,
            tooltip: 'System map',
          ),
        ),
      ],
    );
  }
}

// ─── Disruption banner ────────────────────────────────────────────────────────
// Compact, only visible when disruptions exist. Mirrors SoftMrtView.swift
// topDisruptionBanner. When all clear, shows a quiet one-liner (no card surface).

class _DisruptionBanner extends StatelessWidget {
  const _DisruptionBanner({required this.disrupted, required this.t});

  final Map<MRTLine, TrainAlert> disrupted;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    if (disrupted.isEmpty) {
      // All-clear: quiet single line, no raised card (mirrors iOS).
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 13,
            color: LyneSeverity.normal.color.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 6),
          Text(
            'All lines running normally',
            style: TextStyle(fontSize: 13, color: t.dim),
          ),
        ],
      );
    }

    final count = disrupted.length;
    final sortedLines =
        disrupted.keys.toList()..sort((a, b) => a.code.compareTo(b.code));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: LyneSeverity.warning.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: LyneSeverity.warning.color,
          ),
          const SizedBox(width: 10),
          Text(
            '$count line${count == 1 ? '' : 's'} disrupted',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: t.fg,
            ),
          ),
          const SizedBox(width: 8),
          // Coloured line-code pills for disrupted lines.
          Wrap(
            spacing: 4,
            children: sortedLines.map((line) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: line.color,
                  borderRadius: BorderRadius.circular(LyneRadius.full),
                ),
                child: Text(
                  line.code,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─── Nearest MRT featured tile ────────────────────────────────────────────────
// Full-width tile at the top of the Network grid. Eyebrow "Nearest MRT" +
// station name + coloured line-code pills + walk/distance meta.
// Mirrors SoftMrtView.swift nearestFeaturedTile.

class _NearestFeaturedTile extends StatelessWidget {
  const _NearestFeaturedTile({
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
    final walkMin = result.walkMin < 1 ? 1 : result.walkMin;
    return Semantics(
      button: true,
      label: 'Nearest MRT, ${station.name}, $walkMin minute walk',
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Eyebrow row: walk icon + "Nearest MRT" + trailing chevron.
                Row(
                  children: [
                    Icon(
                      Icons.directions_walk_rounded,
                      size: 12,
                      color: t.soon,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'NEAREST MRT',
                      style: t
                          .mono(10, weight: FontWeight.w600, color: t.dim)
                          .copyWith(letterSpacing: 1.2),
                    ),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, size: 16, color: t.faint),
                  ],
                ),
                const SizedBox(height: 8),
                // Station name + line-code pills on the same row.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        station.name,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: t.fg,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Wrap(
                      spacing: 4,
                      children: station.codes.map((code) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: lineColorFor(code),
                            borderRadius:
                                BorderRadius.circular(LyneRadius.full),
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
                  ],
                ),
                const SizedBox(height: 6),
                // Walk + distance meta.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$walkMin min',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: t.soon,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      ' · ',
                      style: TextStyle(fontSize: 12, color: t.faint),
                    ),
                    Text(
                      _fmtDist(result.distanceM),
                      style: TextStyle(
                        fontSize: 12,
                        color: t.dim,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      ' away',
                      style: TextStyle(fontSize: 12, color: t.dim),
                    ),
                  ],
                ),
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

// ─── No-location hint ─────────────────────────────────────────────────────────
// Compact inline hint shown in place of the featured tile when location is
// unavailable. Lighter weight than the old full no-location card.

class _NoLocationHint extends StatelessWidget {
  const _NoLocationHint({required this.onUseLocation, required this.t});

  final VoidCallback onUseLocation;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onUseLocation,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.line),
        ),
        child: Row(
          children: [
            Icon(Icons.location_off_rounded, size: 16, color: t.faint),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Enable location to see your nearest station',
                style: TextStyle(fontSize: 13, color: t.dim),
              ),
            ),
            Text(
              'Enable',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 2-column line grid ───────────────────────────────────────────────────────
// Replaces the old inline-expand line list. Each tile is badge + status icon +
// name + status text. Mirrors SoftMrtView.swift networkSection LazyVGrid.

class _LineGrid extends StatelessWidget {
  const _LineGrid({
    required this.disrupted,
    required this.onTapLine,
    required this.t,
  });

  final Map<MRTLine, TrainAlert> disrupted;
  final ValueChanged<MRTLine> onTapLine;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    final lines = MRTLine.values;
    // Build rows of 2.
    final rows = <Widget>[];
    for (var i = 0; i < lines.length; i += 2) {
      rows.add(
        Row(
          children: [
            Expanded(
              child: _LineTile(
                line: lines[i],
                alert: disrupted[lines[i]],
                onTap: () => onTapLine(lines[i]),
                t: t,
              ),
            ),
            const SizedBox(width: 10),
            if (i + 1 < lines.length)
              Expanded(
                child: _LineTile(
                  line: lines[i + 1],
                  alert: disrupted[lines[i + 1]],
                  onTap: () => onTapLine(lines[i + 1]),
                  t: t,
                ),
              )
            else
              const Expanded(child: SizedBox()),
          ],
        ),
      );
      if (i + 2 < lines.length) rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }
}

// ─── Single line tile ─────────────────────────────────────────────────────────
// Coloured line-code badge (top-left) + status icon (top-right) + name +
// "Normal service / Disrupted" text. Tapping pushes SoftMrtLineScreen.
// Disrupted tiles get an orange border accent.

class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.line,
    required this.alert,
    required this.onTap,
    required this.t,
  });

  final MRTLine line;
  final TrainAlert? alert;
  final VoidCallback onTap;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    final disrupted = alert != null;
    return Semantics(
      button: true,
      label:
          '${line.displayName} Line, ${disrupted ? 'disrupted' : 'operating normally'}',
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 92),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: disrupted
                    ? LyneSeverity.warning.color.withValues(alpha: 0.4)
                    : t.line,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: line-code badge + status icon.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 28,
                      decoration: BoxDecoration(
                        color: line.color,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        line.code,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      disrupted
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_rounded,
                      size: 14,
                      color: disrupted
                          ? LyneSeverity.warning.color
                          : LyneSeverity.normal.color.withValues(alpha: 0.75),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Line name.
                Text(
                  line.displayName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.fg,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // Status text.
                Text(
                  disrupted ? 'Disrupted' : 'Normal service',
                  style: TextStyle(
                    fontSize: 11,
                    color: disrupted ? LyneSeverity.warning.color : t.dim,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
