// SoftMrtScreen — MRT live-status board (Leyne 2.7 Android).
//
// Flutter/Android port of ios-native/Leyne/V2/SoftMrtView.swift.
//
// Three LTA DataMall feeds:
//   • TrainServiceAlerts       → per-line operating status (disrupted / normal)
//   • FacilitiesMaintenance v2 → network-wide lifts currently under maintenance
//   • PCDRealTime              → live per-station crowdedness, fetched lazily on expand
//
// Free for all users. Crowd colours (green/amber/red) and MRT line colours are
// the only colour in the otherwise-monochrome app — intentional, don't remove.

import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../theme.dart';
import '../../widgets/v2/soft_tab_bar.dart';

class SoftMrtScreen extends StatefulWidget {
  const SoftMrtScreen({super.key, required this.onTab});

  final ValueChanged<SoftTab> onTab;

  @override
  State<SoftMrtScreen> createState() => _SoftMrtScreenState();
}

class _SoftMrtScreenState extends State<SoftMrtScreen> {
  /// The line whose live station crowd is currently expanded (one at a time).
  MRTLine? _expandedLine;

  @override
  void initState() {
    super.initState();
    // Non-force refresh on mount — honours the staleness windows.
    _refresh(force: false);
  }

  void _refresh({required bool force}) {
    final ds = DataStore.shared;
    ds.refreshTrainAlertsIfStale(force: force);
    ds.refreshLiftMaintenanceIfStale(force: force);
    if (_expandedLine != null) {
      ds.refreshCrowd(_expandedLine!, force: force);
    }
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
      listenable: DataStore.shared,
      builder: (context, _) {
        final ds = DataStore.shared;
        final disrupted = _disruptedLines(ds.trainAlerts);
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
                      _OverallBanner(disrupted: disrupted, t: t),
                      _LiftMaintenanceCard(items: ds.liftMaintenance, t: t),
                      const SizedBox(height: 4),
                      _LinesList(
                        disrupted: disrupted,
                        crowdByLine: ds.crowdByLine,
                        expandedLine: _expandedLine,
                        onToggle: (line) {
                          setState(() {
                            if (_expandedLine == line) {
                              _expandedLine = null;
                            } else {
                              _expandedLine = line;
                              DataStore.shared.refreshCrowd(line);
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
      pinned: false,
      floating: true,
      snap: true,
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
            'Live line status',
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
    required this.expandedLine,
    required this.onToggle,
    required this.t,
  });

  final Map<MRTLine, TrainAlert> disrupted;
  final Map<MRTLine, List<StationCrowd>?> crowdByLine;
  final MRTLine? expandedLine;
  final ValueChanged<MRTLine> onToggle;
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
            isExpanded: expandedLine == line,
            onToggle: () => onToggle(line),
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
    required this.isExpanded,
    required this.onToggle,
    required this.t,
  });

  final MRTLine line;
  final TrainAlert? alert;
  final List<StationCrowd>? crowdData;
  final bool isExpanded;
  final VoidCallback onToggle;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
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
                child: _CrowdSection(crowdData: crowdData, t: t),
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
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOutCubic,
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
  const _CrowdSection({required this.crowdData, required this.t});

  final List<StationCrowd>? crowdData;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: t.line, height: 24, thickness: 1),
        if (crowdData == null) ...[
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
                'Loading live crowd…',
                style: TextStyle(fontSize: 13, color: t.dim),
              ),
            ],
          ),
        ] else if (crowdData!.isEmpty) ...[
          Text(
            'Crowd data unavailable right now.',
            style: TextStyle(fontSize: 13, color: t.faint),
          ),
        ] else ...[
          _CrowdLegend(t: t),
          const SizedBox(height: 10),
          ..._sortedCrowd(crowdData!).map(
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
